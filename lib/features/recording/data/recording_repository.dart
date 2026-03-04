import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/sensor_service.dart';
import '../../../core/services/weather_service.dart';
import '../../../core/services/lap_detection_service.dart';
import '../../../core/utils/geo_utils.dart';

/// Recording state exposed to the UI.
class RecordingState {
  RecordingState({
    required this.isRecording,
    required this.sessionId,
    required this.elapsedMs,
    required this.lapCount,
    required this.currentLapMs,
    required this.lastLapMs,
    required this.bestLapMs,
    required this.gpsAccuracy,
    required this.gpsPoints,
    this.weather,
  });

  final bool isRecording;
  final String? sessionId;
  final int elapsedMs;
  final int lapCount;
  final int currentLapMs;
  final int? lastLapMs;
  final int? bestLapMs;
  final double? gpsAccuracy;
  final List<GpsPoint> gpsPoints;
  final WeatherData? weather;

  RecordingState copyWith({
    bool? isRecording,
    String? sessionId,
    int? elapsedMs,
    int? lapCount,
    int? currentLapMs,
    int? lastLapMs,
    int? bestLapMs,
    double? gpsAccuracy,
    List<GpsPoint>? gpsPoints,
    WeatherData? weather,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      sessionId: sessionId ?? this.sessionId,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      lapCount: lapCount ?? this.lapCount,
      currentLapMs: currentLapMs ?? this.currentLapMs,
      lastLapMs: lastLapMs ?? this.lastLapMs,
      bestLapMs: bestLapMs ?? this.bestLapMs,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      gpsPoints: gpsPoints ?? this.gpsPoints,
      weather: weather ?? this.weather,
    );
  }

  factory RecordingState.initial() => RecordingState(
        isRecording: false,
        sessionId: null,
        elapsedMs: 0,
        lapCount: 0,
        currentLapMs: 0,
        lastLapMs: null,
        bestLapMs: null,
        gpsAccuracy: null,
        gpsPoints: const [],
      );
}

/// Orchestrates GPS, sensors, weather, and lap detection during a recording session.
///
/// All data is written to the local Drift database. Never writes directly to Supabase.
class RecordingRepository {
  RecordingRepository(this._db);

  final AppDatabase _db;
  final _locationService = LocationService();
  final _sensorService = SensorService();
  final _weatherService = WeatherService();
  final _lapDetection = LapDetectionService();
  final _uuid = const Uuid();

  StreamSubscription<GpsPoint>? _gpsSub;
  Timer? _elapsedTimer;

  String? _sessionId;
  String? _userId;
  DateTime? _sessionStart;
  DateTime? _lapStart;
  int _lapCount = 0;
  int? _lastLapMs;
  int? _bestLapMs;
  int? _circuitBestMs; // All-time best at this circuit for this user
  WeatherData? _weather;

  // GPS trace for current lap
  final List<GpsPoint> _currentLapPoints = [];
  // All points for the full session
  final List<GpsPoint> _allPoints = [];

  /// State stream for the UI.
  final _stateController = StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get stateStream => _stateController.stream;

  RecordingState get _currentState => RecordingState(
        isRecording: _sessionId != null,
        sessionId: _sessionId,
        elapsedMs: _sessionStart != null
            ? DateTime.now().difference(_sessionStart!).inMilliseconds
            : 0,
        lapCount: _lapCount,
        currentLapMs: _lapStart != null
            ? DateTime.now().difference(_lapStart!).inMilliseconds
            : 0,
        lastLapMs: _lastLapMs,
        bestLapMs: _bestLapMs,
        gpsAccuracy: _locationService.lastPoint?.accuracy,
        gpsPoints: List.unmodifiable(_allPoints),
        weather: _weather,
      );

  /// Start a new recording session.
  Future<String> startSession({
    required String userId,
    String? circuitId,
    String? carId,
  }) async {
    _userId = userId;
    _sessionId = _uuid.v4();
    _sessionStart = DateTime.now();
    _lapStart = _sessionStart;
    _lapCount = 0;
    _lastLapMs = null;
    _bestLapMs = null;
    _circuitBestMs = null;
    _currentLapPoints.clear();
    _allPoints.clear();

    // Load all-time best lap at this circuit for accurate PB detection
    if (circuitId != null) {
      _circuitBestMs = await _loadCircuitBest(userId, circuitId);
    }

    // Write session to local DB
    await _db.into(_db.localSessions).insert(
      LocalSessionsCompanion.insert(
        id: _sessionId!,
        userId: userId,
        startedAt: _sessionStart!,
        carId: Value(carId),
        circuitId: Value(circuitId),
      ),
    );

    // Start GPS
    await _locationService.startRecording();
    _gpsSub = _locationService.positionStream.listen(_onGpsPoint);

    // Start sensors
    _sensorService.startRecording();

    // Fetch weather (fire-and-forget)
    _fetchWeather();

    // Start elapsed timer (updates UI every 100ms)
    _elapsedTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _emitState(),
    );

    _emitState();
    return _sessionId!;
  }

  /// Manually trigger a lap split (when no start/finish line is set).
  Future<void> manualLapSplit() async {
    if (_sessionId == null) return;
    await _completeLap(DateTime.now());
  }

  /// Configure start/finish line for automatic lap detection.
  void setStartFinishLine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    _lapDetection.setStartFinishLine(lat1, lng1, lat2, lng2);
  }

  /// Stop recording and finalize the session.
  Future<String?> stopSession({bool isPublic = true}) async {
    if (_sessionId == null) return null;

    final sessionId = _sessionId!;

    // Complete final lap if we have points
    if (_currentLapPoints.isNotEmpty) {
      await _completeLap(DateTime.now());
    }

    // Update session end time
    await (_db.update(_db.localSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(LocalSessionsCompanion(
      endedAt: Value(DateTime.now()),
      weatherJson: Value(_weather != null ? jsonEncode(_weather!.toJson()) : null),
    ));

    // Enqueue session for sync
    final session = await _db.getSession(sessionId);
    if (session != null) {
      await _db.enqueueSync(
        targetTable: 'sessions',
        operation: 'insert',
        recordId: sessionId,
        payloadJson: jsonEncode({
          'id': sessionId,
          'user_id': _userId,
          'started_at': _sessionStart?.toIso8601String(),
          'ended_at': DateTime.now().toIso8601String(),
          'car_id': session.carId,
          'circuit_id': session.circuitId,
          'weather_json': _weather?.toJson(),
          'is_public': isPublic,
        }),
      );
    }

    // Stop services
    await _locationService.stopRecording();
    _sensorService.stopRecording();
    _gpsSub?.cancel();
    _elapsedTimer?.cancel();

    // Reset state
    _sessionId = null;
    _sessionStart = null;
    _lapStart = null;
    _emitState();

    return sessionId;
  }

  /// Handle incoming GPS point.
  void _onGpsPoint(GpsPoint point) {
    _currentLapPoints.add(point);
    _allPoints.add(point);

    // Check for automatic lap crossing
    final crossing = _lapDetection.processPoint(point);
    if (crossing != null) {
      _completeLap(crossing.crossingTime);
    }
  }

  /// Complete a lap and save data to local DB.
  Future<void> _completeLap(DateTime crossingTime) async {
    if (_sessionId == null || _lapStart == null) return;

    _lapCount++;
    final durationMs = crossingTime.difference(_lapStart!).inMilliseconds;

    // Track session-best for UI display
    if (_bestLapMs == null || durationMs < _bestLapMs!) {
      _bestLapMs = durationMs;
    }
    _lastLapMs = durationMs;

    // Determine if this is a circuit-wide personal best (not just session-best)
    final isPB = _circuitBestMs == null || durationMs < _circuitBestMs!;
    if (isPB) _circuitBestMs = durationMs;

    final lapId = _uuid.v4();

    // Save lap to DB
    await _db.into(_db.localLaps).insert(
      LocalLapsCompanion.insert(
        id: lapId,
        sessionId: _sessionId!,
        lapNumber: _lapCount,
        durationMs: durationMs,
        isPersonalBest: Value(isPB),
        traceJson: Value(GeoUtils.encodeTrace(_currentLapPoints)),
      ),
    );

    // Save sensor data for this lap
    final sensorSnapshot = _sensorService.captureLapData();
    await _db.into(_db.localLapSensorData).insert(
      LocalLapSensorDataCompanion.insert(
        id: _uuid.v4(),
        lapId: lapId,
        timestampsJson: jsonEncode(sensorSnapshot.timestamps),
        accelXJson: Value(jsonEncode(sensorSnapshot.accelX)),
        accelYJson: Value(jsonEncode(sensorSnapshot.accelY)),
        accelZJson: Value(jsonEncode(sensorSnapshot.accelZ)),
        gyroXJson: Value(jsonEncode(sensorSnapshot.gyroX)),
        gyroYJson: Value(jsonEncode(sensorSnapshot.gyroY)),
        gyroZJson: Value(jsonEncode(sensorSnapshot.gyroZ)),
        baroPressureJson: Value(jsonEncode(sensorSnapshot.baroPressure)),
        magHeadingJson: Value(jsonEncode(sensorSnapshot.magHeading)),
      ),
    );

    // Enqueue lap for sync (include trace for sectors/leaderboards/maps)
    await _db.enqueueSync(
      targetTable: 'laps',
      operation: 'insert',
      recordId: lapId,
      payloadJson: jsonEncode({
        'id': lapId,
        'session_id': _sessionId,
        'lap_number': _lapCount,
        'duration_ms': durationMs,
        'is_personal_best': isPB,
        'trace_json': GeoUtils.encodeTrace(_currentLapPoints),
      }),
    );

    // Enqueue sensor data for sync (telemetry needs to be accessible cross-device)
    final sensorId = sensorSnapshot.timestamps.isNotEmpty
        ? '${lapId}_sensors'
        : null;
    if (sensorId != null) {
      await _db.enqueueSync(
        targetTable: 'lap_sensor_data',
        operation: 'insert',
        recordId: sensorId,
        payloadJson: jsonEncode({
          'id': sensorId,
          'lap_id': lapId,
          'timestamps_json': sensorSnapshot.timestamps,
          'accel_x_json': sensorSnapshot.accelX,
          'accel_y_json': sensorSnapshot.accelY,
          'accel_z_json': sensorSnapshot.accelZ,
          'gyro_x_json': sensorSnapshot.gyroX,
          'gyro_y_json': sensorSnapshot.gyroY,
          'gyro_z_json': sensorSnapshot.gyroZ,
          'baro_pressure_json': sensorSnapshot.baroPressure,
          'mag_heading_json': sensorSnapshot.magHeading,
        }),
      );
    }

    // Reset for next lap
    _currentLapPoints.clear();
    _lapStart = crossingTime;
    _emitState();
  }

  /// Load the all-time best lap duration at a circuit for this user.
  Future<int?> _loadCircuitBest(String userId, String circuitId) async {
    final sessions = await (_db.select(_db.localSessions)
          ..where((t) =>
              t.userId.equals(userId) & t.circuitId.equals(circuitId)))
        .get();

    if (sessions.isEmpty) return null;

    int? best;
    for (final session in sessions) {
      final laps = await _db.getSessionLaps(session.id);
      for (final lap in laps) {
        if (best == null || lap.durationMs < best) {
          best = lap.durationMs;
        }
      }
    }
    return best;
  }

  /// Fetch weather data at the current GPS position.
  Future<void> _fetchWeather() async {
    // Wait for first GPS fix
    await Future.delayed(const Duration(seconds: 2));
    final point = _locationService.lastPoint;
    if (point == null) return;

    _weather = await _weatherService.fetchWeather(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    _emitState();
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_currentState);
    }
  }

  void dispose() {
    _locationService.dispose();
    _sensorService.dispose();
    _weatherService.dispose();
    _gpsSub?.cancel();
    _elapsedTimer?.cancel();
    _stateController.close();
  }
}

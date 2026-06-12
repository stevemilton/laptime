import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/sensor_service.dart';
import '../../../core/services/sync_payloads.dart';
import '../../../core/services/weather_service.dart';
import '../../../core/services/lap_detection_service.dart';
import '../../../core/utils/trace_codec.dart';

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
    this.speedMps,
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

  /// Current GPS speed in m/s (Doppler), for live display.
  final double? speedMps;
  final WeatherData? weather;

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

/// Orchestrates GPS, sensors, weather, and lap detection during a recording
/// session.
///
/// All data is written to the local Drift database. Never writes directly to
/// Supabase: every row is enqueued on the sync queue, parent before child
/// (session at start, then laps and sensor data as they complete), so the
/// strictly FIFO sync engine never hits a foreign-key violation.
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
  // In-flight lap persistence, awaited before the session is finalized.
  final List<Future<void>> _pendingPersists = [];

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
        speedMps: _locationService.lastPoint?.speed,
        weather: _weather,
      );

  /// Start a new recording session.
  ///
  /// When [circuitId] refers to a local circuit with a start/finish line,
  /// automatic lap detection is armed; otherwise laps are manual-split only.
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
    _pendingPersists.clear();
    _lapDetection.reset();

    if (circuitId != null) {
      await _armLapDetection(circuitId);
      // Load all-time best lap at this circuit for accurate PB detection
      _circuitBestMs = await _loadCircuitBest(userId, circuitId);
    }

    await _db.into(_db.localSessions).insert(
      LocalSessionsCompanion.insert(
        id: _sessionId!,
        userId: userId,
        startedAt: _sessionStart!,
        carId: Value(carId),
        circuitId: Value(circuitId),
      ),
    );

    // Enqueue the session row immediately (ended_at null) so laps synced
    // mid-session never reference a missing parent.
    final session = await _db.getSession(_sessionId!);
    if (session != null) {
      await _db.enqueueSync(
        targetTable: 'sessions',
        operation: 'insert',
        recordId: _sessionId!,
        payloadJson: jsonEncode(SyncPayloads.session(session)),
      );
    }

    await _locationService.startRecording();
    _gpsSub = _locationService.positionStream.listen(_onGpsPoint);

    _sensorService.startRecording();

    // Keep the screen awake — CoreMotion sensor streams stop delivering
    // when the device locks, even with background location active.
    unawaited(WakelockPlus.enable());

    _fetchWeather();

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
    final lapPoints = List<GpsPoint>.of(_currentLapPoints);
    _currentLapPoints.clear();
    _onLapBoundary(DateTime.now(), lapPoints);
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

    // The tail since the last crossing is an in-lap, not a real lap: it
    // must never count as a lap (or worse, a personal best). Only when the
    // session produced no laps at all do we keep it, unflagged, so the
    // session isn't empty.
    if (_lapCount == 0 && _currentLapPoints.length >= 2) {
      final lapPoints = List<GpsPoint>.of(_currentLapPoints);
      _currentLapPoints.clear();
      _onLapBoundary(DateTime.now(), lapPoints, neverPersonalBest: true);
    }

    // Make sure every lap (and its sensor data) is on disk before the
    // session is finalized and sector scoring reads it back.
    await Future.wait(_pendingPersists);
    _pendingPersists.clear();

    final endedAt = DateTime.now();
    await (_db.update(_db.localSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(LocalSessionsCompanion(
      endedAt: Value(endedAt),
      isPublic: Value(isPublic),
      weatherJson:
          Value(_weather != null ? jsonEncode(_weather!.toJson()) : null),
    ));

    // Enqueue the finalized session row (upsert overwrites the
    // start-of-session insert).
    final session = await _db.getSession(sessionId);
    if (session != null) {
      await _db.enqueueSync(
        targetTable: 'sessions',
        operation: 'update',
        recordId: sessionId,
        payloadJson: jsonEncode(SyncPayloads.session(session)),
      );
    }

    await _locationService.stopRecording();
    _sensorService.stopRecording();
    await _gpsSub?.cancel();
    _elapsedTimer?.cancel();
    unawaited(WakelockPlus.disable());

    _sessionId = null;
    _sessionStart = null;
    _lapStart = null;
    _emitState();

    return sessionId;
  }

  /// Finalize sessions that were left open by a crash or force-quit.
  ///
  /// The session row and its completed laps survived locally; only the
  /// finalization (ended_at + sync enqueue) was lost. Returns the number of
  /// sessions recovered.
  Future<int> recoverOrphanedSessions(String userId) async {
    final orphans = await (_db.select(_db.localSessions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.endedAt.isNull() &
              t.id.equals(_sessionId ?? '').not()))
        .get();

    for (final orphan in orphans) {
      final laps = await _db.getSessionLaps(orphan.id);
      final lapTotalMs =
          laps.fold<int>(0, (sum, lap) => sum + lap.durationMs);
      final endedAt = orphan.startedAt.add(Duration(milliseconds: lapTotalMs));

      await (_db.update(_db.localSessions)
            ..where((t) => t.id.equals(orphan.id)))
          .write(LocalSessionsCompanion(endedAt: Value(endedAt)));

      final updated = await _db.getSession(orphan.id);
      if (updated != null) {
        await _db.enqueueSync(
          targetTable: 'sessions',
          operation: 'update',
          recordId: orphan.id,
          payloadJson: jsonEncode(SyncPayloads.session(updated)),
        );
      }
    }
    return orphans.length;
  }

  /// Handle incoming GPS point.
  void _onGpsPoint(GpsPoint point) {
    _currentLapPoints.add(point);
    _allPoints.add(point);

    final crossing = _lapDetection.processPoint(point);
    if (crossing == null) return;

    // Split the trace at the interpolated crossing position: the segment
    // up to the crossing closes this lap; the crossing point also seeds
    // the next lap so traces stay continuous.
    final crossingPoint = GpsPoint(
      latitude: crossing.crossingLat,
      longitude: crossing.crossingLng,
      altitude: point.altitude,
      accuracy: point.accuracy,
      speed: point.speed,
      heading: point.heading,
      timestamp: crossing.crossingTime,
    );

    final lapPoints = List<GpsPoint>.of(_currentLapPoints)
      ..removeLast()
      ..add(crossingPoint);

    _currentLapPoints
      ..clear()
      ..add(crossingPoint)
      ..add(point);

    _onLapBoundary(crossing.crossingTime, lapPoints);
  }

  /// Close the current lap at [crossingTime].
  ///
  /// All recording state (lap count, bests, lap start, sensor buffers) is
  /// updated synchronously so GPS points arriving during persistence can
  /// never leak into the wrong lap; only the database writes are async.
  void _onLapBoundary(
    DateTime crossingTime,
    List<GpsPoint> lapPoints, {
    bool neverPersonalBest = false,
  }) {
    if (_sessionId == null || _lapStart == null) return;

    final lapStart = _lapStart!;
    _lapStart = crossingTime;
    _lapCount++;
    final lapNumber = _lapCount;
    final durationMs = crossingTime.difference(lapStart).inMilliseconds;
    final sensorSnapshot = _sensorService.captureLapData();

    var isPB = false;
    if (!neverPersonalBest) {
      if (_bestLapMs == null || durationMs < _bestLapMs!) {
        _bestLapMs = durationMs;
      }
      _lastLapMs = durationMs;

      // Circuit-wide personal best (not just session-best)
      isPB = _circuitBestMs == null || durationMs < _circuitBestMs!;
      if (isPB) _circuitBestMs = durationMs;
    }

    final persist = _persistLap(
      sessionId: _sessionId!,
      lapNumber: lapNumber,
      durationMs: durationMs,
      isPB: isPB,
      lapStart: lapStart,
      lapPoints: lapPoints,
      sensorSnapshot: sensorSnapshot,
    );
    _pendingPersists.add(persist);
    unawaited(persist);

    _emitState();
  }

  /// Save a completed lap and its sensor data, and enqueue both for sync.
  /// Never throws: a persistence failure must not abort session stop.
  Future<void> _persistLap({
    required String sessionId,
    required int lapNumber,
    required int durationMs,
    required bool isPB,
    required DateTime lapStart,
    required List<GpsPoint> lapPoints,
    required LapSensorSnapshot sensorSnapshot,
  }) async {
    try {
      await _persistLapInner(
        sessionId: sessionId,
        lapNumber: lapNumber,
        durationMs: durationMs,
        isPB: isPB,
        lapStart: lapStart,
        lapPoints: lapPoints,
        sensorSnapshot: sensorSnapshot,
      );
    } catch (e) {
      debugPrint('RecordingRepository: lap persist failed: $e');
    }
  }

  Future<void> _persistLapInner({
    required String sessionId,
    required int lapNumber,
    required int durationMs,
    required bool isPB,
    required DateTime lapStart,
    required List<GpsPoint> lapPoints,
    required LapSensorSnapshot sensorSnapshot,
  }) async {
    final lapId = _uuid.v4();
    final traceJson = TraceCodec.encode(lapPoints, lapStart);

    await _db.into(_db.localLaps).insert(
      LocalLapsCompanion.insert(
        id: lapId,
        sessionId: sessionId,
        lapNumber: lapNumber,
        durationMs: durationMs,
        isPersonalBest: Value(isPB),
        traceJson: Value(traceJson),
      ),
    );

    await _db.enqueueSync(
      targetTable: 'laps',
      operation: 'insert',
      recordId: lapId,
      payloadJson: jsonEncode({
        'id': lapId,
        'session_id': sessionId,
        'lap_number': lapNumber,
        'duration_ms': durationMs,
        'is_personal_best': isPB,
        'trace_json': TraceCodec.toJsonList(lapPoints, lapStart),
      }),
    );

    if (sensorSnapshot.timestamps.isEmpty) return;

    final sensorId = _uuid.v4();
    await _db.into(_db.localLapSensorData).insert(
      LocalLapSensorDataCompanion.insert(
        id: sensorId,
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

    // Column names and raw arrays match the remote lap_sensor_data table;
    // the sync engine chunks oversized payloads.
    await _db.enqueueSync(
      targetTable: 'lap_sensor_data',
      operation: 'insert',
      recordId: sensorId,
      payloadJson: jsonEncode({
        'id': sensorId,
        'lap_id': lapId,
        'timestamps': sensorSnapshot.timestamps,
        'accel_x': sensorSnapshot.accelX,
        'accel_y': sensorSnapshot.accelY,
        'accel_z': sensorSnapshot.accelZ,
        'gyro_x': sensorSnapshot.gyroX,
        'gyro_y': sensorSnapshot.gyroY,
        'gyro_z': sensorSnapshot.gyroZ,
        'baro_pressure': sensorSnapshot.baroPressure,
        'mag_heading': sensorSnapshot.magHeading,
      }),
    );
  }

  /// Arm automatic lap detection from a locally cached circuit's
  /// start/finish line ([[lat, lng], [lat, lng]]).
  Future<void> _armLapDetection(String circuitId) async {
    final circuit = await (_db.select(_db.localCircuits)
          ..where((t) => t.id.equals(circuitId)))
        .getSingleOrNull();
    final lineJson = circuit?.startFinishLineJson;
    if (lineJson == null || lineJson.isEmpty) return;

    try {
      final line = jsonDecode(lineJson) as List;
      if (line.length < 2) return;
      final p1 = line[0] as List;
      final p2 = line[1] as List;
      setStartFinishLine(
        (p1[0] as num).toDouble(),
        (p1[1] as num).toDouble(),
        (p2[0] as num).toDouble(),
        (p2[1] as num).toDouble(),
      );
    } catch (_) {
      // Malformed line: fall back to manual laps.
    }
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

  /// Fetch weather data at the current GPS position. Waits (up to ~30s)
  /// for the first GPS fix instead of giving up after one attempt.
  Future<void> _fetchWeather() async {
    final sessionId = _sessionId;
    GpsPoint? point;
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      if (_sessionId != sessionId) return; // session ended
      point = _locationService.lastPoint;
      if (point != null) break;
    }
    if (point == null) return;

    final result = await _weatherService.fetchWeather(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (_sessionId != sessionId) return;
    _weather = result.data;
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
    WakelockPlus.disable();
    _stateController.close();
  }
}

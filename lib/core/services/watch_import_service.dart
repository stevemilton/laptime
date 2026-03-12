import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';

/// Imports session data recorded on Apple Watch into the local Drift database.
///
/// Watch sessions arrive as JSON files via WatchConnectivity. This service
/// parses them and creates the same LocalSession/LocalLap/LocalLapSensorData
/// records as phone-recorded sessions, then enqueues everything for Supabase sync.
class WatchImportService {
  WatchImportService(this._db);

  final AppDatabase _db;

  /// Import a Watch session from a JSON file path.
  ///
  /// Returns the session ID on success, null on failure.
  Future<String?> importSessionFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[WatchImport] File not found: $filePath');
        return null;
      }

      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final sessionId = await _importSession(data);

      // Clean up the file after successful import
      await file.delete();
      debugPrint('[WatchImport] Imported session $sessionId');

      return sessionId;
    } catch (e, st) {
      debugPrint('[WatchImport] Import failed: $e\n$st');
      return null;
    }
  }

  Future<String> _importSession(Map<String, dynamic> data) async {
    final sessionId = data['id'] as String;
    final userId = data['userId'] as String;
    final startedAt = DateTime.parse(data['startedAt'] as String);
    final endedAt = DateTime.parse(data['endedAt'] as String);
    final laps = (data['laps'] as List?) ?? [];

    await _db.transaction(() async {
      final existingSession = await _db.getSession(sessionId);
      if (existingSession == null) {
        await _db.into(_db.localSessions).insert(
          LocalSessionsCompanion.insert(
            id: sessionId,
            userId: userId,
            startedAt: startedAt,
            endedAt: Value(endedAt),
          ),
        );
      }

      if (!await _db.hasPendingSyncItem(
        targetTable: 'sessions',
        recordId: sessionId,
      )) {
        await _db.enqueueSync(
          targetTable: 'sessions',
          operation: 'insert',
          recordId: sessionId,
          payloadJson: jsonEncode({
            'id': sessionId,
            'user_id': userId,
            'started_at': startedAt.toIso8601String(),
            'ended_at': endedAt.toIso8601String(),
            'is_public': true,
            'source': 'watch',
          }),
        );
      }

      for (final lapData in laps) {
        await _importLap(lapData as Map<String, dynamic>, sessionId);
      }
    });

    return sessionId;
  }

  Future<void> _importLap(Map<String, dynamic> data, String sessionId) async {
    final lapId = data['id'] as String;
    final lapNumber = data['lapNumber'] as int;
    final durationMs = data['durationMs'] as int;

    // Build trace JSON from GPS points
    final trace = data['trace'] as List? ?? [];
    final traceCoords = trace
        .map((p) => '[${p['lng']},${p['lat']}]')
        .join(',');
    final traceJson = '[$traceCoords]';

    final existingLap = await _db.getLap(lapId);
    if (existingLap == null) {
      await _db.into(_db.localLaps).insert(
        LocalLapsCompanion.insert(
          id: lapId,
          sessionId: sessionId,
          lapNumber: lapNumber,
          durationMs: durationMs,
          isPersonalBest: const Value(false),
          traceJson: Value(traceJson),
        ),
      );
    }

    if (!await _db.hasPendingSyncItem(targetTable: 'laps', recordId: lapId)) {
      await _db.enqueueSync(
        targetTable: 'laps',
        operation: 'insert',
        recordId: lapId,
        payloadJson: jsonEncode({
          'id': lapId,
          'session_id': sessionId,
          'lap_number': lapNumber,
          'duration_ms': durationMs,
          'is_personal_best': false,
          'trace_json': traceJson,
        }),
      );
    }

    // Import sensor data
    final sensorData = data['sensorData'] as Map<String, dynamic>?;
    if (sensorData != null) {
      await _importSensorData(sensorData, lapId);
    }
  }

  Future<void> _importSensorData(
    Map<String, dynamic> data,
    String lapId,
  ) async {
    final sensorId = '${lapId}_sensors';
    final timestamps = data['timestamps'] as List? ?? [];

    if (timestamps.isEmpty) return;

    final existingSensor = await _db.getLapSensorData(lapId);
    if (existingSensor == null) {
      await _db.into(_db.localLapSensorData).insert(
        LocalLapSensorDataCompanion.insert(
          id: sensorId,
          lapId: lapId,
          timestampsJson: jsonEncode(timestamps),
          accelXJson: Value(jsonEncode(data['accelX'] ?? [])),
          accelYJson: Value(jsonEncode(data['accelY'] ?? [])),
          accelZJson: Value(jsonEncode(data['accelZ'] ?? [])),
          gyroXJson: Value(jsonEncode(data['gyroX'] ?? [])),
          gyroYJson: Value(jsonEncode(data['gyroY'] ?? [])),
          gyroZJson: Value(jsonEncode(data['gyroZ'] ?? [])),
          baroPressureJson: Value(jsonEncode(data['baroPressure'] ?? [])),
          magHeadingJson: Value(jsonEncode(data['magHeading'] ?? [])),
        ),
      );
    }

    if (!await _db.hasPendingSyncItem(
      targetTable: 'lap_sensor_data',
      recordId: sensorId,
    )) {
      await _db.enqueueSync(
        targetTable: 'lap_sensor_data',
        operation: 'insert',
        recordId: sensorId,
        payloadJson: jsonEncode({
          'id': sensorId,
          'lap_id': lapId,
          'timestamps_json': timestamps,
          'accel_x_json': data['accelX'] ?? [],
          'accel_y_json': data['accelY'] ?? [],
          'accel_z_json': data['accelZ'] ?? [],
          'gyro_x_json': data['gyroX'] ?? [],
          'gyro_y_json': data['gyroY'] ?? [],
          'gyro_z_json': data['gyroZ'] ?? [],
          'baro_pressure_json': data['baroPressure'] ?? [],
          'mag_heading_json': data['magHeading'] ?? [],
        }),
      );
    }
  }

}

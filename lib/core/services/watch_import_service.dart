import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import 'sync_payloads.dart';

/// Imports session data recorded on Apple Watch into the local Drift database.
///
/// Watch sessions arrive as JSON files via WatchConnectivity (see
/// ios/WatchApp/SessionData.swift for the wire format: GPS points carry
/// lat/lng/alt/acc/spd/hdg/ts). This service parses them into the same
/// LocalSession/LocalLap/LocalLapSensorData records as phone-recorded
/// sessions — including trace format v2 ([lng, lat, tMs, speedMps]) — and
/// enqueues everything for Supabase sync via [SyncPayloads], so watch data
/// flows through the exact same pipeline as phone data.
class WatchImportService {
  WatchImportService(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

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
      if (await _db.getSession(sessionId) == null) {
        await _db.into(_db.localSessions).insert(
          LocalSessionsCompanion.insert(
            id: sessionId,
            userId: userId,
            startedAt: startedAt,
            endedAt: Value(endedAt),
            sessionNotes: const Value('Recorded on Apple Watch'),
          ),
        );
      }

      // Session is enqueued BEFORE its laps (FIFO parent-before-child) with
      // a full-row payload from SyncPayloads — the single source of truth
      // for the client -> server column mapping.
      if (!await _db.hasPendingSyncItem(
        targetTable: 'sessions',
        recordId: sessionId,
      )) {
        final session = await _db.getSession(sessionId);
        await _db.enqueueSync(
          targetTable: 'sessions',
          operation: 'insert',
          recordId: sessionId,
          payloadJson: jsonEncode(SyncPayloads.session(session!)),
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
    final isPersonalBest = (data['isPersonalBest'] as bool?) ?? false;

    var lap = await _db.getLap(lapId);
    if (lap == null) {
      lap = LocalLap(
        id: lapId,
        sessionId: sessionId,
        lapNumber: lapNumber,
        durationMs: durationMs,
        isPersonalBest: isPersonalBest,
        isPartial: false,
        traceJson: _traceV2Json(data['trace'] as List? ?? const []),
        createdAt: DateTime.now(),
      );
      await _db.into(_db.localLaps).insert(lap);
    }

    if (!await _db.hasPendingSyncItem(targetTable: 'laps', recordId: lapId)) {
      await _db.enqueueSync(
        targetTable: 'laps',
        operation: 'insert',
        recordId: lapId,
        payloadJson: jsonEncode(SyncPayloads.lap(lap)),
      );
    }

    // Import sensor data
    final sensorData = data['sensorData'] as Map<String, dynamic>?;
    if (sensorData != null) {
      await _importSensorData(sensorData, lapId);
    }
  }

  /// Convert watch GPS points ({lat, lng, spd m/s, ts epoch ms, ...}) into
  /// trace format v2: [[lng, lat, tMs since lap start, speedMps], ...].
  /// Discarding the watch's speed/timestamps here would break speed charts
  /// and sector timing for watch-recorded laps.
  String? _traceV2Json(List rawPoints) {
    if (rawPoints.isEmpty) return null;
    final firstTs = ((rawPoints.first as Map)['ts'] as num?)?.toInt() ?? 0;
    final entries = <List<num>>[];
    for (final raw in rawPoints) {
      final p = raw as Map<String, dynamic>;
      final lat = (p['lat'] as num?)?.toDouble();
      final lng = (p['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final ts = (p['ts'] as num?)?.toInt() ?? firstTs;
      final rawSpd = (p['spd'] as num?)?.toDouble() ?? 0;
      final spd = rawSpd < 0 ? 0.0 : rawSpd;
      entries.add([
        double.parse(lng.toStringAsFixed(6)),
        double.parse(lat.toStringAsFixed(6)),
        ts - firstTs,
        double.parse(spd.toStringAsFixed(2)),
      ]);
    }
    return entries.isEmpty ? null : jsonEncode(entries);
  }

  Future<void> _importSensorData(
    Map<String, dynamic> data,
    String lapId,
  ) async {
    final timestamps = data['timestamps'] as List? ?? [];
    if (timestamps.isEmpty) return;

    var sensorRow = await _db.getLapSensorData(lapId);
    if (sensorRow == null) {
      sensorRow = LocalLapSensorDataData(
        // Real UUID: the remote primary key is a UUID column.
        id: _uuid.v4(),
        lapId: lapId,
        timestampsJson: jsonEncode(timestamps),
        accelXJson: jsonEncode(data['accelX'] ?? []),
        accelYJson: jsonEncode(data['accelY'] ?? []),
        accelZJson: jsonEncode(data['accelZ'] ?? []),
        gyroXJson: jsonEncode(data['gyroX'] ?? []),
        gyroYJson: jsonEncode(data['gyroY'] ?? []),
        gyroZJson: jsonEncode(data['gyroZ'] ?? []),
        baroPressureJson: jsonEncode(data['baroPressure'] ?? []),
        magHeadingJson: jsonEncode(data['magHeading'] ?? []),
      );
      await _db.into(_db.localLapSensorData).insert(sensorRow);
    }

    if (!await _db.hasPendingSyncItem(
      targetTable: 'lap_sensor_data',
      recordId: sensorRow.id,
    )) {
      await _db.enqueueSync(
        targetTable: 'lap_sensor_data',
        operation: 'insert',
        recordId: sensorRow.id,
        payloadJson: jsonEncode(SyncPayloads.lapSensorData(sensorRow)),
      );
    }
  }
}

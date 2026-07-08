import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../providers/database_provider.dart';
import '../utils/geo_utils.dart';
import '../utils/trace_codec.dart';
import 'lap_detection_service.dart';
import 'location_service.dart';
import 'sync_payloads.dart';

/// Outcome of re-scoring a circuit's sessions after a start/finish line edit.
class RescoreResult {
  const RescoreResult({
    required this.sessionsChanged,
    required this.lapsBefore,
    required this.lapsAfter,
  });

  final int sessionsChanged;
  final int lapsBefore;
  final int lapsAfter;
}

/// Maintenance operations on stored laps: deleting a lap, recomputing
/// circuit personal bests, and re-splitting session traces after a
/// start/finish line change.
///
/// Laps are normally only created live during recording; everything here
/// exists so a badly placed start/finish line (or a junk lap) doesn't
/// poison a circuit's history forever. All mutations follow the offline-
/// first convention: local Drift writes plus sync-queue enqueues, children
/// before parents on delete.
class LapMaintenanceService {
  LapMaintenanceService(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  /// New lap boundaries within this tolerance of the old ones count as
  /// unchanged, so re-scoring is idempotent and never churns sensor data.
  static const _unchangedToleranceMs = 200;

  /// Delete a single lap (with its sector times and sensor data) and
  /// recompute the circuit personal best.
  Future<void> deleteLap(String lapId) async {
    final lap = await (_db.select(_db.localLaps)
          ..where((t) => t.id.equals(lapId)))
        .getSingleOrNull();
    if (lap == null) return;
    final session = await _db.getSession(lap.sessionId);

    await _deleteLapsCascading([lap]);

    final circuitId = session?.circuitId;
    if (session != null && circuitId != null) {
      await recomputePersonalBests(
        userId: session.userId,
        circuitId: circuitId,
      );
    }
  }

  /// Recompute the circuit-scoped [LocalLap.isPersonalBest] flags for a
  /// user: only the fastest non-partial lap(s) at the circuit keep the
  /// flag. Live recording sets the flag incrementally, so history edits
  /// (lap delete, line re-score) must call this to keep it truthful.
  Future<void> recomputePersonalBests({
    required String userId,
    required String circuitId,
  }) async {
    final rows = await (_db.select(_db.localLaps).join([
      innerJoin(
        _db.localSessions,
        _db.localSessions.id.equalsExp(_db.localLaps.sessionId),
        useColumns: false,
      ),
    ])
          ..where(_db.localSessions.userId.equals(userId) &
              _db.localSessions.circuitId.equals(circuitId)))
        .get();
    final laps = rows.map((r) => r.readTable(_db.localLaps)).toList();

    int? bestMs;
    for (final lap in laps) {
      if (lap.isPartial) continue;
      if (bestMs == null || lap.durationMs < bestMs) bestMs = lap.durationMs;
    }

    for (final lap in laps) {
      final shouldBePB = !lap.isPartial && lap.durationMs == bestMs;
      if (lap.isPersonalBest == shouldBePB) continue;

      await (_db.update(_db.localLaps)..where((t) => t.id.equals(lap.id)))
          .write(LocalLapsCompanion(isPersonalBest: Value(shouldBePB)));
      final updated = await (_db.select(_db.localLaps)
            ..where((t) => t.id.equals(lap.id)))
          .getSingle();
      await _db.enqueueSync(
        targetTable: 'laps',
        operation: 'update',
        recordId: lap.id,
        payloadJson: jsonEncode(SyncPayloads.lap(updated)),
      );
    }
  }

  /// Re-run lap detection over every stored session of [userId] at
  /// [circuitId], against the circuit's current start/finish line.
  ///
  /// Sessions whose lap boundaries come out unchanged are left untouched
  /// (sensor data preserved). Changed sessions get their laps rebuilt from
  /// the concatenated trace; the old laps' sensor data and sector times
  /// are deleted because they can no longer be attributed to a lap.
  Future<RescoreResult> rescoreCircuit({
    required String circuitId,
    required String userId,
  }) async {
    final circuit = await (_db.select(_db.localCircuits)
          ..where((t) => t.id.equals(circuitId)))
        .getSingleOrNull();
    final line = _parseLine(circuit?.startFinishLineJson);
    if (line == null) {
      return const RescoreResult(
          sessionsChanged: 0, lapsBefore: 0, lapsAfter: 0);
    }

    final sessions = await (_db.select(_db.localSessions)
          ..where((t) =>
              t.circuitId.equals(circuitId) & t.userId.equals(userId)))
        .get();

    var changed = 0;
    var before = 0;
    var after = 0;
    for (final session in sessions) {
      final outcome = await _rescoreSession(session, line);
      if (outcome == null) continue;
      changed++;
      before += outcome.$1;
      after += outcome.$2;
    }

    if (changed > 0) {
      await recomputePersonalBests(userId: userId, circuitId: circuitId);
    }
    return RescoreResult(
      sessionsChanged: changed,
      lapsBefore: before,
      lapsAfter: after,
    );
  }

  /// Re-split one session. Returns (oldLapCount, newLapCount) when the
  /// session was rebuilt, or null when it was left untouched.
  Future<(int, int)?> _rescoreSession(
    LocalSession session,
    List<List<double>> line,
  ) async {
    final laps = await _db.getSessionLaps(session.id);
    if (laps.isEmpty) return null;

    final points = _combinedTrace(session, laps);
    if (points.length < 2) return null;

    final crossings = _detectCrossings(points, line);
    final newSegments = _segment(points, crossings, session.startedAt);
    if (newSegments.isEmpty) return null;

    // Idempotence: identical boundaries → nothing to do.
    if (newSegments.length == laps.length) {
      var same = true;
      for (var i = 0; i < laps.length; i++) {
        if ((laps[i].durationMs - newSegments[i].durationMs).abs() >
                _unchangedToleranceMs ||
            laps[i].isPartial != newSegments[i].isPartial) {
          same = false;
          break;
        }
      }
      if (same) return null;
    }

    await _db.transaction(() async {
      await _deleteLapsCascading(laps, inTransaction: true);

      for (var i = 0; i < newSegments.length; i++) {
        final seg = newSegments[i];
        final lap = LocalLap(
          id: _uuid.v4(),
          sessionId: session.id,
          lapNumber: i + 1,
          durationMs: seg.durationMs,
          isPersonalBest: false,
          isPartial: seg.isPartial,
          traceJson: TraceCodec.encode(seg.points, seg.start),
          createdAt: DateTime.now(),
        );
        await _db.into(_db.localLaps).insert(lap);
        await _db.enqueueSync(
          targetTable: 'laps',
          operation: 'insert',
          recordId: lap.id,
          payloadJson: jsonEncode(SyncPayloads.lap(lap)),
        );
      }
    });

    return (laps.length, newSegments.length);
  }

  /// Rebuild the session's continuous GPS trace by concatenating its lap
  /// traces on the session timeline. Returns an empty list when any lap
  /// has no usable trace — a partial timeline would misplace crossings.
  List<GpsPoint> _combinedTrace(LocalSession session, List<LocalLap> laps) {
    final points = <GpsPoint>[];
    var offsetMs = 0;
    for (final lap in laps) {
      var trace = TraceCodec.decode(lap.traceJson);
      if (trace.length < 2) return const [];
      trace = TraceCodec.withTimestamps(trace, lap.durationMs);
      if (!TraceCodec.hasTimestamps(trace)) return const [];

      for (final p in trace) {
        final timestamp = session.startedAt
            .add(Duration(milliseconds: offsetMs + p.tMs!.round()));
        // Consecutive lap traces share the crossing point; keep the
        // timeline strictly monotonic.
        if (points.isNotEmpty &&
            !timestamp.isAfter(points.last.timestamp)) {
          continue;
        }
        points.add(GpsPoint(
          latitude: p.lat,
          longitude: p.lng,
          altitude: 0,
          accuracy: 5,
          speed: p.speedMps ?? _synthSpeed(points, p, timestamp),
          heading: 0,
          timestamp: timestamp,
        ));
      }
      offsetMs += lap.durationMs;
    }
    return points;
  }

  /// Legacy v1 traces carry no Doppler speed; derive one from segment
  /// distance over time so the detector's speed gate still works.
  double _synthSpeed(List<GpsPoint> soFar, TracePoint p, DateTime timestamp) {
    if (soFar.isEmpty) return 0;
    final prev = soFar.last;
    final dtMs = timestamp.difference(prev.timestamp).inMilliseconds;
    if (dtMs <= 0) return 0;
    final dist = GeoUtils.distanceMeters(
        prev.latitude, prev.longitude, p.lat, p.lng);
    return dist / (dtMs / 1000);
  }

  List<LineCrossing> _detectCrossings(
    List<GpsPoint> points,
    List<List<double>> line,
  ) {
    final detector = LapDetectionService()
      ..setStartFinishLine(line[0][0], line[0][1], line[1][0], line[1][1]);
    final crossings = <LineCrossing>[];
    for (final point in points) {
      final crossing = detector.processPoint(point);
      if (crossing != null) crossings.add(crossing);
    }
    return crossings;
  }

  /// Split the combined trace into laps, mirroring live recording:
  /// session start → first crossing is lap 1, crossings bound the laps in
  /// between, and the tail after the last crossing is kept only when the
  /// session would otherwise have no laps at all (flagged partial).
  List<_LapSegment> _segment(
    List<GpsPoint> points,
    List<LineCrossing> crossings,
    DateTime sessionStart,
  ) {
    if (crossings.isEmpty) {
      return [
        _LapSegment(
          start: sessionStart,
          durationMs: points.last.timestamp
              .difference(sessionStart)
              .inMilliseconds,
          points: points,
          isPartial: true,
        ),
      ];
    }

    final segments = <_LapSegment>[];
    var segStart = sessionStart;
    GpsPoint? seed; // previous crossing point, keeps traces continuous
    var pointIndex = 0;
    for (final crossing in crossings) {
      final segPoints = <GpsPoint>[?seed];
      while (pointIndex < points.length &&
          !points[pointIndex].timestamp.isAfter(crossing.crossingTime)) {
        segPoints.add(points[pointIndex]);
        pointIndex++;
      }
      final crossingPoint = _crossingPoint(
          crossing, points[pointIndex > 0 ? pointIndex - 1 : 0]);
      segPoints.add(crossingPoint);

      final durationMs =
          crossing.crossingTime.difference(segStart).inMilliseconds;
      if (durationMs > 0 && segPoints.length >= 2) {
        segments.add(_LapSegment(
          start: segStart,
          durationMs: durationMs,
          points: segPoints,
          isPartial: false,
        ));
      }
      segStart = crossing.crossingTime;
      seed = crossingPoint;
    }
    return segments;
  }

  GpsPoint _crossingPoint(LineCrossing crossing, GpsPoint nearby) {
    return GpsPoint(
      latitude: crossing.crossingLat,
      longitude: crossing.crossingLng,
      altitude: nearby.altitude,
      accuracy: nearby.accuracy,
      speed: nearby.speed,
      heading: nearby.heading,
      timestamp: crossing.crossingTime,
    );
  }

  /// Delete laps with their sector times and sensor data, locally and on
  /// the server (children before parents, stale queue items purged first).
  Future<void> _deleteLapsCascading(
    List<LocalLap> laps, {
    bool inTransaction = false,
  }) async {
    final lapIds = laps.map((l) => l.id).toList(growable: false);
    if (lapIds.isEmpty) return;

    final sensorRows = await (_db.select(_db.localLapSensorData)
          ..where((t) => t.lapId.isIn(lapIds)))
        .get();
    final sectorTimes = await (_db.select(_db.localSectorTimes)
          ..where((t) => t.lapId.isIn(lapIds)))
        .get();

    Future<void> run() async {
      await _db.removePendingSyncItems(
        targetTable: 'sector_times',
        recordIds: sectorTimes.map((t) => t.id),
      );
      await _db.removePendingSyncItems(
        targetTable: 'lap_sensor_data',
        recordIds: sensorRows.map((r) => r.id),
      );
      await _db.removePendingSyncItems(targetTable: 'laps', recordIds: lapIds);

      await (_db.delete(_db.localSectorTimes)
            ..where((t) => t.lapId.isIn(lapIds)))
          .go();
      for (final st in sectorTimes) {
        await _db.enqueueSync(
          targetTable: 'sector_times',
          operation: 'delete',
          recordId: st.id,
          payloadJson: jsonEncode({'id': st.id}),
        );
      }

      await (_db.delete(_db.localLapSensorData)
            ..where((t) => t.lapId.isIn(lapIds)))
          .go();
      for (final row in sensorRows) {
        await _db.enqueueSync(
          targetTable: 'lap_sensor_data',
          operation: 'delete',
          recordId: row.id,
          payloadJson: jsonEncode({'id': row.id}),
        );
      }

      await (_db.delete(_db.localLaps)..where((t) => t.id.isIn(lapIds))).go();
      for (final lapId in lapIds) {
        await _db.enqueueSync(
          targetTable: 'laps',
          operation: 'delete',
          recordId: lapId,
          payloadJson: jsonEncode({'id': lapId}),
        );
      }
    }

    if (inTransaction) {
      await run();
    } else {
      await _db.transaction(run);
    }
  }

  List<List<double>>? _parseLine(String? lineJson) {
    if (lineJson == null || lineJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(lineJson) as List;
      if (decoded.length < 2) return null;
      return [
        [
          ((decoded[0] as List)[0] as num).toDouble(),
          ((decoded[0] as List)[1] as num).toDouble(),
        ],
        [
          ((decoded[1] as List)[0] as num).toDouble(),
          ((decoded[1] as List)[1] as num).toDouble(),
        ],
      ];
    } catch (e) {
      debugPrint('LapMaintenanceService: malformed line json: $e');
      return null;
    }
  }
}

/// One rebuilt lap: its start time, duration, and trace points.
class _LapSegment {
  const _LapSegment({
    required this.start,
    required this.durationMs,
    required this.points,
    required this.isPartial,
  });

  final DateTime start;
  final int durationMs;
  final List<GpsPoint> points;
  final bool isPartial;
}

/// Riverpod provider for [LapMaintenanceService].
final lapMaintenanceServiceProvider = Provider<LapMaintenanceService>((ref) {
  return LapMaintenanceService(ref.watch(databaseProvider));
});

import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/sync_payloads.dart';
import '../../../core/utils/trace_codec.dart';

/// Data class representing a single entry on a sector leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.durationMs,
    this.carMake,
    this.carModel,
    this.carClass,
    required this.lapId,
    required this.sessionId,
    required this.rank,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int durationMs;
  final String? carMake;
  final String? carModel;
  final String? carClass;
  final String lapId;
  final String sessionId;
  final int rank;
}

/// Repository for sector CRUD operations and leaderboard queries.
///
/// Mutations are written to local SQLite first, then enqueued to the sync
/// queue. Leaderboards are inherently multi-user, so they read from
/// Supabase first and fall back to the local cache offline.
class SectorRepository {
  SectorRepository(this._db, {SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final AppDatabase _db;
  final SupabaseClient _supabase;
  static const _uuid = Uuid();

  /// Max distance between a trace and a sector gate point for the lap to
  /// count as passing through the gate.
  static const double gateToleranceMeters = 35;

  // ── Read operations ──

  /// Get all sectors for a circuit.
  Future<List<LocalSector>> getCircuitSectors(String circuitId) {
    return (_db.select(_db.localSectors)
          ..where((t) => t.circuitId.equals(circuitId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Stream of all sectors for a circuit (reactive).
  Stream<List<LocalSector>> watchCircuitSectors(String circuitId) {
    return (_db.select(_db.localSectors)
          ..where((t) => t.circuitId.equals(circuitId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// Get all sectors created by a specific user.
  Future<List<LocalSector>> getUserSectors(String userId) {
    return (_db.select(_db.localSectors)
          ..where((t) => t.createdBy.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Stream of all sectors created by a specific user (reactive).
  Stream<List<LocalSector>> watchUserSectors(String userId) {
    return (_db.select(_db.localSectors)
          ..where((t) => t.createdBy.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Pull other users' sectors for a circuit into the local cache.
  /// Safe to call offline (keeps the cache).
  Future<void> refreshCircuitSectors(String circuitId) async {
    try {
      final rows = await _supabase
          .from('sectors')
          .select('id, circuit_id, created_by, name, start_point_json, '
              'end_point_json, created_at')
          .eq('circuit_id', circuitId);

      for (final row in rows as List) {
        final map = row as Map<String, dynamic>;
        await _db.into(_db.localSectors).insertOnConflictUpdate(
              LocalSectorsCompanion.insert(
                id: map['id'] as String,
                circuitId: map['circuit_id'] as String,
                createdBy: map['created_by'] as String,
                name: map['name'] as String,
                startPointJson: Value(map['start_point_json'] != null
                    ? jsonEncode(map['start_point_json'])
                    : null),
                endPointJson: Value(map['end_point_json'] != null
                    ? jsonEncode(map['end_point_json'])
                    : null),
              ),
            );
      }
    } catch (e) {
      debugPrint('SectorRepository: sector refresh failed: $e');
    }
  }

  // ── Write operations ──

  /// Create a new sector definition for a circuit, then retroactively
  /// score every locally stored lap at that circuit against it.
  Future<String> createSector({
    required String circuitId,
    required String createdBy,
    required String name,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.into(_db.localSectors).insert(
      LocalSectorsCompanion.insert(
        id: id,
        circuitId: circuitId,
        createdBy: createdBy,
        name: name,
        startPointJson: Value(jsonEncode({'lat': startLat, 'lng': startLng})),
        endPointJson: Value(jsonEncode({'lat': endLat, 'lng': endLng})),
        createdAt: Value(now),
      ),
    );

    final sector = await (_db.select(_db.localSectors)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.enqueueSync(
      targetTable: 'sectors',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode(SyncPayloads.sector(sector)),
    );

    // Retroactive scoring is part of creation — it must not depend on the
    // calling screen remembering to do it.
    await persistSectorTimesForCircuit(id);

    return id;
  }

  /// Delete a sector and its associated times. Only the creator may delete.
  Future<void> deleteSector(String sectorId, {required String requestedBy}) async {
    final sector = await (_db.select(_db.localSectors)
          ..where((t) => t.id.equals(sectorId)))
        .getSingleOrNull();
    if (sector == null) return;
    if (sector.createdBy != requestedBy) {
      throw StateError('Only the sector creator can delete it');
    }

    // Delete associated sector times first
    await (_db.delete(_db.localSectorTimes)
          ..where((t) => t.sectorId.equals(sectorId)))
        .go();

    // Delete the sector itself
    await (_db.delete(_db.localSectors)
          ..where((t) => t.id.equals(sectorId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'sectors',
      operation: 'delete',
      recordId: sectorId,
      payloadJson: '{"id":"$sectorId"}',
    );
  }

  // ── Leaderboard operations ──

  /// Get the leaderboard for a sector, sorted by fastest time.
  ///
  /// Each user appears only once (their best time within the filter).
  /// Reads from Supabase first so other drivers' times appear; falls back
  /// to the local cache offline.
  Future<List<LeaderboardEntry>> getSectorLeaderboard(
    String sectorId, {
    String? carClass,
  }) async {
    var rows = await _fetchRemoteLeaderboardRows(sectorId);
    rows ??= await _localLeaderboardRows(sectorId);
    if (rows.isEmpty) return [];

    // Filter by car class BEFORE picking best-per-user, so a driver's
    // best time in this class still ranks them.
    if (carClass != null && carClass != 'All') {
      rows = rows.where((r) => r.carClass == carClass).toList();
    }

    final bestByUser = <String, _LeaderboardRow>{};
    for (final row in rows) {
      final existing = bestByUser[row.userId];
      if (existing == null || row.durationMs < existing.durationMs) {
        bestByUser[row.userId] = row;
      }
    }

    final sorted = bestByUser.values.toList()
      ..sort((a, b) => a.durationMs.compareTo(b.durationMs));

    return [
      for (var i = 0; i < sorted.length; i++)
        LeaderboardEntry(
          userId: sorted[i].userId,
          displayName: sorted[i].displayName ?? 'Driver',
          avatarUrl: sorted[i].avatarUrl,
          durationMs: sorted[i].durationMs,
          carMake: sorted[i].carMake,
          carModel: sorted[i].carModel,
          carClass: sorted[i].carClass,
          lapId: sorted[i].lapId,
          sessionId: sorted[i].sessionId,
          rank: i + 1,
        ),
    ];
  }

  Future<List<_LeaderboardRow>?> _fetchRemoteLeaderboardRows(
      String sectorId) async {
    try {
      final rows = await _supabase
          .from('sector_times')
          .select('user_id, lap_id, session_id, duration_ms, '
              'profiles(display_name, avatar_url), '
              'sessions(cars(make, model, class))')
          .eq('sector_id', sectorId)
          .order('duration_ms', ascending: true)
          .limit(500);

      return [
        for (final row in rows as List)
          _LeaderboardRow(
            userId: row['user_id'] as String,
            lapId: row['lap_id'] as String,
            sessionId: row['session_id'] as String,
            durationMs: (row['duration_ms'] as num).toInt(),
            displayName:
                (row['profiles'] as Map?)?['display_name'] as String?,
            avatarUrl: (row['profiles'] as Map?)?['avatar_url'] as String?,
            carMake: _carField(row, 'make'),
            carModel: _carField(row, 'model'),
            carClass: _carField(row, 'class'),
          ),
      ];
    } catch (e) {
      debugPrint('SectorRepository: remote leaderboard failed: $e');
      return null;
    }
  }

  static String? _carField(Map<String, dynamic> row, String field) {
    final car = (row['sessions'] as Map?)?['cars'];
    return car is Map ? car[field] as String? : null;
  }

  Future<List<_LeaderboardRow>> _localLeaderboardRows(String sectorId) async {
    final sectorTimes = await (_db.select(_db.localSectorTimes)
          ..where((t) => t.sectorId.equals(sectorId))
          ..orderBy([(t) => OrderingTerm.asc(t.durationMs)]))
        .get();

    final rows = <_LeaderboardRow>[];
    for (final st in sectorTimes) {
      final profile = await _db.getProfile(st.userId);
      final session = await _db.getSession(st.sessionId);
      LocalCar? car;
      if (session?.carId != null) {
        car = await (_db.select(_db.localCars)
              ..where((t) => t.id.equals(session!.carId!)))
            .getSingleOrNull();
      }
      rows.add(_LeaderboardRow(
        userId: st.userId,
        lapId: st.lapId,
        sessionId: st.sessionId,
        durationMs: st.durationMs,
        displayName: profile?.displayName,
        avatarUrl: profile?.avatarUrl,
        carMake: car?.make,
        carModel: car?.model,
        carClass: car?.carClass,
      ));
    }
    return rows;
  }

  // ── Sector time computation ──

  /// Compute and store the sector time for one lap.
  ///
  /// Returns the duration in milliseconds, or null when the lap's trace
  /// doesn't pass through both gates (or has no usable trace). Idempotent:
  /// a (sector, lap) pair is only stored once.
  Future<int?> saveSectorTime(String sectorId, String lapId) async {
    // Idempotency guard
    final existing = await (_db.select(_db.localSectorTimes)
          ..where(
              (t) => t.sectorId.equals(sectorId) & t.lapId.equals(lapId))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing.durationMs;

    final sector = await (_db.select(_db.localSectors)
          ..where((t) => t.id.equals(sectorId)))
        .getSingleOrNull();
    if (sector == null) return null;

    final startPoint = _parsePoint(sector.startPointJson);
    final endPoint = _parsePoint(sector.endPointJson);
    if (startPoint == null || endPoint == null) return null;

    final lap = await (_db.select(_db.localLaps)
          ..where((t) => t.id.equals(lapId)))
        .getSingleOrNull();
    if (lap == null || lap.traceJson == null) return null;

    var trace = TraceCodec.decode(lap.traceJson);
    if (trace.length < 2) return null;
    // Legacy traces have no timestamps; synthesise them from the lap
    // duration, allocated proportionally to distance.
    trace = TraceCodec.withTimestamps(trace, lap.durationMs);
    if (!TraceCodec.hasTimestamps(trace)) return null;

    final startCrossing = _findGateCrossing(
      trace,
      startPoint['lat']!,
      startPoint['lng']!,
    );
    if (startCrossing == null) return null;

    // The end gate must be crossed AFTER the start gate.
    final endCrossing = _findGateCrossing(
      trace,
      endPoint['lat']!,
      endPoint['lng']!,
      fromIndex: startCrossing.segmentIndex + 1,
    );
    if (endCrossing == null) return null;

    final durationMs =
        (endCrossing.timestampMs - startCrossing.timestampMs).round();
    if (durationMs <= 0) return null;

    final session = await _db.getSession(lap.sessionId);
    if (session == null) return null;

    final id = _uuid.v4();
    await _db.into(_db.localSectorTimes).insert(
      LocalSectorTimesCompanion.insert(
        id: id,
        sectorId: sectorId,
        lapId: lapId,
        sessionId: lap.sessionId,
        userId: session.userId,
        durationMs: durationMs,
      ),
    );

    final stored = await (_db.select(_db.localSectorTimes)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.enqueueSync(
      targetTable: 'sector_times',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode(SyncPayloads.sectorTime(stored)),
    );

    return durationMs;
  }

  /// Compute sector times for all laps at the sector's circuit.
  Future<void> persistSectorTimesForCircuit(String sectorId) async {
    final sector = await (_db.select(_db.localSectors)
          ..where((t) => t.id.equals(sectorId)))
        .getSingleOrNull();
    if (sector == null) return;

    final sessions = await (_db.select(_db.localSessions)
          ..where((t) => t.circuitId.equals(sector.circuitId)))
        .get();

    for (final session in sessions) {
      final laps = await _db.getSessionLaps(session.id);
      for (final lap in laps) {
        await saveSectorTime(sectorId, lap.id);
      }
    }
  }

  /// Score every lap of a freshly recorded session against all of its
  /// circuit's sectors (including other users' sectors, refreshed first).
  /// Called from the recording flow after a session is saved.
  Future<void> persistSectorTimesForSession(String sessionId) async {
    final session = await _db.getSession(sessionId);
    final circuitId = session?.circuitId;
    if (circuitId == null) return;

    await refreshCircuitSectors(circuitId);
    final sectors = await getCircuitSectors(circuitId);
    if (sectors.isEmpty) return;

    final laps = await _db.getSessionLaps(sessionId);
    for (final sector in sectors) {
      for (final lap in laps) {
        await saveSectorTime(sector.id, lap.id);
      }
    }
  }

  // ── Private helpers ──

  /// Parse a JSON point string into lat/lng map.
  Map<String, double>? _parsePoint(String? json) {
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return {
        'lat': (decoded['lat'] as num).toDouble(),
        'lng': (decoded['lng'] as num).toDouble(),
      };
    } catch (_) {
      return null;
    }
  }

  /// Find where the trace passes a gate point, by closest approach.
  ///
  /// Projects the gate point onto every trace segment (in a local
  /// meters frame, so it works at any latitude and for any track
  /// orientation) and takes the segment with the minimum perpendicular
  /// distance. Returns null when the trace never comes within
  /// [gateToleranceMeters] of the gate.
  _GateCrossing? _findGateCrossing(
    List<TracePoint> trace,
    double gateLat,
    double gateLng, {
    int fromIndex = 0,
  }) {
    // Local equirectangular projection centred on the gate.
    final metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * cos(gateLat * pi / 180);

    double bestDist = double.infinity;
    var bestIndex = -1;
    var bestFraction = 0.0;

    for (var i = max(0, fromIndex); i < trace.length - 1; i++) {
      final x1 = (trace[i].lng - gateLng) * metersPerDegLng;
      final y1 = (trace[i].lat - gateLat) * metersPerDegLat;
      final x2 = (trace[i + 1].lng - gateLng) * metersPerDegLng;
      final y2 = (trace[i + 1].lat - gateLat) * metersPerDegLat;

      final dx = x2 - x1;
      final dy = y2 - y1;
      final lenSq = dx * dx + dy * dy;
      final t = lenSq > 0
          ? (-(x1 * dx + y1 * dy) / lenSq).clamp(0.0, 1.0)
          : 0.0;
      final px = x1 + t * dx;
      final py = y1 + t * dy;
      final dist = sqrt(px * px + py * py);

      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
        bestFraction = t;
      }
    }

    if (bestIndex < 0 || bestDist > gateToleranceMeters) return null;

    final tA = trace[bestIndex].tMs ?? 0;
    final tB = trace[bestIndex + 1].tMs ?? tA;
    return _GateCrossing(
      segmentIndex: bestIndex,
      timestampMs: tA + bestFraction * (tB - tA),
    );
  }
}

/// Result of locating a gate pass within a trace.
class _GateCrossing {
  const _GateCrossing({
    required this.segmentIndex,
    required this.timestampMs,
  });

  final int segmentIndex;
  final double timestampMs;
}

/// Internal leaderboard row, source-agnostic (remote or local cache).
class _LeaderboardRow {
  const _LeaderboardRow({
    required this.userId,
    required this.lapId,
    required this.sessionId,
    required this.durationMs,
    this.displayName,
    this.avatarUrl,
    this.carMake,
    this.carModel,
    this.carClass,
  });

  final String userId;
  final String lapId;
  final String sessionId;
  final int durationMs;
  final String? displayName;
  final String? avatarUrl;
  final String? carMake;
  final String? carModel;
  final String? carClass;
}

/// Riverpod provider for SectorRepository.
final sectorRepositoryProvider = Provider<SectorRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return SectorRepository(db);
});

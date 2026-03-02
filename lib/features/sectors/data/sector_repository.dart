import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/geo_utils.dart';

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
/// All mutations are written to local SQLite first, then enqueued
/// to the sync queue for eventual upload to Supabase.
class SectorRepository {
  SectorRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

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

  // ── Write operations ──

  /// Create a new sector definition for a circuit.
  ///
  /// Writes to local DB, then enqueues the change to the sync queue.
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

    final startPointJson = jsonEncode({'lat': startLat, 'lng': startLng});
    final endPointJson = jsonEncode({'lat': endLat, 'lng': endLng});

    await _db.into(_db.localSectors).insert(
      LocalSectorsCompanion.insert(
        id: id,
        circuitId: circuitId,
        createdBy: createdBy,
        name: name,
        startPointJson: Value(startPointJson),
        endPointJson: Value(endPointJson),
        createdAt: Value(now),
      ),
    );

    await _db.enqueueSync(
      targetTable: 'sectors',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'circuit_id': circuitId,
        'created_by': createdBy,
        'name': name,
        'start_point_json': startPointJson,
        'end_point_json': endPointJson,
        'created_at': now.toIso8601String(),
      }),
    );

    return id;
  }

  /// Delete a sector and its associated times.
  Future<void> deleteSector(String sectorId) async {
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
  /// Each user appears only once (their best time). Optionally
  /// filter by car class.
  Future<List<LeaderboardEntry>> getSectorLeaderboard(
    String sectorId, {
    String? carClass,
  }) async {
    // Get all sector times for this sector
    final sectorTimes = await (_db.select(_db.localSectorTimes)
          ..where((t) => t.sectorId.equals(sectorId))
          ..orderBy([(t) => OrderingTerm.asc(t.durationMs)]))
        .get();

    if (sectorTimes.isEmpty) return [];

    // Group by user, keep only the fastest time per user
    final bestByUser = <String, LocalSectorTime>{};
    for (final st in sectorTimes) {
      if (!bestByUser.containsKey(st.userId) ||
          st.durationMs < bestByUser[st.userId]!.durationMs) {
        bestByUser[st.userId] = st;
      }
    }

    // Sort by duration
    final sorted = bestByUser.values.toList()
      ..sort((a, b) => a.durationMs.compareTo(b.durationMs));

    // Build leaderboard entries with profile and car data
    final entries = <LeaderboardEntry>[];
    var rank = 0;

    for (final st in sorted) {
      // Look up profile
      final profile = await _db.getProfile(st.userId);

      // Look up the session to get car info
      final session = await _db.getSession(st.sessionId);
      LocalCar? car;
      if (session?.carId != null) {
        car = await (_db.select(_db.localCars)
              ..where((t) => t.id.equals(session!.carId!)))
            .getSingleOrNull();
      }

      // Apply car class filter if specified
      if (carClass != null && carClass != 'All' && car?.carClass != carClass) {
        continue;
      }

      rank++;
      entries.add(LeaderboardEntry(
        userId: st.userId,
        displayName: profile?.displayName ?? 'Driver',
        avatarUrl: profile?.avatarUrl,
        durationMs: st.durationMs,
        carMake: car?.make,
        carModel: car?.model,
        carClass: car?.carClass,
        lapId: st.lapId,
        sessionId: st.sessionId,
        rank: rank,
      ));
    }

    return entries;
  }

  // ── Sector time computation ──

  /// Compute the sector time for a specific lap by finding where the
  /// lap's GPS trace crosses the sector start and end lines.
  ///
  /// Returns the computed duration in milliseconds, or null if the
  /// trace doesn't cross both sector boundaries.
  Future<int?> computeSectorTimes(String sectorId, String lapId) async {
    // Get the sector definition
    final sector = await (_db.select(_db.localSectors)
          ..where((t) => t.id.equals(sectorId)))
        .getSingleOrNull();
    if (sector == null) return null;

    // Parse sector boundary points
    final startPoint = _parsePoint(sector.startPointJson);
    final endPoint = _parsePoint(sector.endPointJson);
    if (startPoint == null || endPoint == null) return null;

    // Get the lap and its GPS trace
    final lap = await (_db.select(_db.localLaps)
          ..where((t) => t.id.equals(lapId)))
        .getSingleOrNull();
    if (lap == null || lap.traceJson == null) return null;

    final trace = _parseTrace(lap.traceJson!);
    if (trace.length < 2) return null;

    // Build sector boundary lines (perpendicular gate lines ~20m wide)
    const gateHalfWidth = 0.0002; // approx 20m in degrees

    // Find where trace crosses start line
    final startCrossing = _findLineCrossing(
      trace,
      startPoint['lat']!,
      startPoint['lng']!,
      gateHalfWidth,
    );

    // Find where trace crosses end line
    final endCrossing = _findLineCrossing(
      trace,
      endPoint['lat']!,
      endPoint['lng']!,
      gateHalfWidth,
    );

    if (startCrossing == null || endCrossing == null) return null;
    if (endCrossing.timestamp <= startCrossing.timestamp) return null;

    final durationMs =
        (endCrossing.timestamp - startCrossing.timestamp).round();
    if (durationMs <= 0) return null;

    // Get session info for the lap
    final session = await _db.getSession(lap.sessionId);
    if (session == null) return null;

    // Store the computed sector time
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

    return durationMs;
  }

  /// Compute sector times for all laps at the sector's circuit.
  Future<void> batchComputeSectorTimes(String sectorId) async {
    final sector = await (_db.select(_db.localSectors)
          ..where((t) => t.id.equals(sectorId)))
        .getSingleOrNull();
    if (sector == null) return;

    // Get all sessions at this circuit
    final sessions = await (_db.select(_db.localSessions)
          ..where((t) => t.circuitId.equals(sector.circuitId)))
        .get();

    for (final session in sessions) {
      // Get all laps for this session
      final laps = await _db.getSessionLaps(session.id);

      for (final lap in laps) {
        // Check if we already have a sector time for this lap
        final existing = await (_db.select(_db.localSectorTimes)
              ..where((t) =>
                  t.sectorId.equals(sectorId) & t.lapId.equals(lap.id)))
            .getSingleOrNull();

        if (existing == null) {
          await computeSectorTimes(sectorId, lap.id);
        }
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

  /// Parse a trace JSON string into a list of trace points.
  List<_TracePoint> _parseTrace(String traceJson) {
    try {
      final decoded = jsonDecode(traceJson) as List;
      return decoded.map((p) {
        if (p is List) {
          // Format: [lng, lat] or [lng, lat, timestamp]
          return _TracePoint(
            lat: (p[1] as num).toDouble(),
            lng: (p[0] as num).toDouble(),
            timestamp: p.length > 2 ? (p[2] as num).toDouble() : 0,
          );
        } else if (p is Map) {
          return _TracePoint(
            lat: (p['lat'] as num? ?? p['latitude'] as num).toDouble(),
            lng: (p['lng'] as num? ?? p['longitude'] as num).toDouble(),
            timestamp: (p['timestamp'] as num?)?.toDouble() ?? 0,
          );
        }
        throw FormatException('Unknown trace point format');
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Find where a GPS trace crosses a gate point, using line-segment
  /// intersection with a perpendicular gate line.
  _CrossingResult? _findLineCrossing(
    List<_TracePoint> trace,
    double gateLat,
    double gateLng,
    double gateHalfWidth,
  ) {
    // Create a perpendicular gate line at the gate point
    // Gate runs east-west by default
    final gateLat1 = gateLat;
    final gateLng1 = gateLng - gateHalfWidth;
    final gateLat2 = gateLat;
    final gateLng2 = gateLng + gateHalfWidth;

    for (var i = 0; i < trace.length - 1; i++) {
      final p1 = trace[i];
      final p2 = trace[i + 1];

      final intersection = GeoUtils.lineSegmentIntersection(
        p1.lat,
        p1.lng,
        p2.lat,
        p2.lng,
        gateLat1,
        gateLng1,
        gateLat2,
        gateLng2,
      );

      if (intersection != null) {
        // Interpolate timestamp at crossing point
        final segmentLength = GeoUtils.distanceMeters(
          p1.lat, p1.lng, p2.lat, p2.lng,
        );
        final crossingDist = GeoUtils.distanceMeters(
          p1.lat, p1.lng, intersection.lat, intersection.lng,
        );
        final ratio = segmentLength > 0 ? crossingDist / segmentLength : 0.0;
        final timestamp =
            p1.timestamp + ratio * (p2.timestamp - p1.timestamp);

        return _CrossingResult(
          lat: intersection.lat,
          lng: intersection.lng,
          timestamp: timestamp,
          segmentIndex: i,
        );
      }
    }

    return null;
  }
}

/// Internal trace point representation.
class _TracePoint {
  const _TracePoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  final double lat;
  final double lng;
  final double timestamp;
}

/// Result of finding where a trace crosses a gate line.
class _CrossingResult {
  const _CrossingResult({
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.segmentIndex,
  });

  final double lat;
  final double lng;
  final double timestamp;
  final int segmentIndex;
}

/// Riverpod provider for SectorRepository.
final sectorRepositoryProvider = Provider<SectorRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return SectorRepository(db);
});

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/services/sync_payloads.dart';
import '../../../core/utils/geo_utils.dart';

/// A circuit with its distance from the user's current position.
class NearbyCircuit {
  const NearbyCircuit({required this.circuit, required this.distanceMeters});

  final LocalCircuit circuit;
  final double distanceMeters;
}

/// Repository for circuits: remote catalogue with a local cache, nearest-
/// circuit detection, and user-created circuits (synced via the queue).
///
/// Circuits are inherently shared data, so reads refresh from Supabase when
/// possible and fall back to the local cache offline.
class CircuitRepository {
  CircuitRepository(this._db, this._supabase);

  final AppDatabase _db;
  final SupabaseClient _supabase;
  final _uuid = const Uuid();

  /// Last successful catalogue pull (shared across instances). Several
  /// screens trigger refreshes; without a freshness window each visit
  /// would re-download the whole table.
  static DateTime? _lastRefresh;
  static const _refreshTtl = Duration(minutes: 5);

  /// Pull the circuit catalogue from Supabase into the local cache.
  /// Safe to call offline (keeps the existing cache). No-op while the
  /// last successful pull is fresher than [_refreshTtl] unless [force].
  /// Returns true when a network pull actually updated the cache.
  Future<bool> refreshFromRemote({bool force = false}) async {
    if (!force &&
        _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _refreshTtl) {
      return false;
    }
    try {
      final rows = await _supabase.from('circuits').select(
          'id, name, country, gps_lat, gps_lng, start_finish_line_json, length_m');

      await _db.batch((batch) {
        for (final row in rows as List) {
          final map = row as Map<String, dynamic>;
          batch.insert(
            _db.localCircuits,
            LocalCircuitsCompanion.insert(
              id: map['id'] as String,
              name: map['name'] as String,
              country: Value((map['country'] as String?) ?? 'GB'),
              gpsLat: (map['gps_lat'] as num).toDouble(),
              gpsLng: (map['gps_lng'] as num).toDouble(),
              startFinishLineJson: Value(
                map['start_finish_line_json'] != null
                    ? jsonEncode(map['start_finish_line_json'])
                    : null,
              ),
              lengthM: Value((map['length_m'] as num?)?.toInt()),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
      _lastRefresh = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('CircuitRepository: remote refresh failed: $e');
      return false;
    }
  }

  /// All cached circuits sorted by distance from ([lat], [lng]).
  Future<List<NearbyCircuit>> circuitsByDistance(
    double lat,
    double lng,
  ) async {
    final circuits = await _db.getAllCircuits();
    final nearby = circuits
        .map((c) => NearbyCircuit(
              circuit: c,
              distanceMeters:
                  GeoUtils.distanceMeters(lat, lng, c.gpsLat, c.gpsLng),
            ))
        .toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return nearby;
  }

  /// Nearest circuit within [maxMeters] of the position, or null.
  Future<LocalCircuit?> nearestCircuit(
    double lat,
    double lng, {
    double maxMeters = 5000,
  }) async {
    final sorted = await circuitsByDistance(lat, lng);
    if (sorted.isEmpty) return null;
    final nearest = sorted.first;
    return nearest.distanceMeters <= maxMeters ? nearest.circuit : null;
  }

  Future<LocalCircuit?> getCircuit(String circuitId) {
    return (_db.select(_db.localCircuits)
          ..where((t) => t.id.equals(circuitId)))
        .getSingleOrNull();
  }

  /// Create a user-defined circuit with a start/finish line
  /// ([[lat, lng], [lat, lng]]), cache it locally, and enqueue for sync.
  Future<LocalCircuit> createCircuit({
    required String userId,
    required String name,
    required double gpsLat,
    required double gpsLng,
    required List<List<double>> startFinishLine,
    String country = 'GB',
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.localCircuits).insert(
          LocalCircuitsCompanion.insert(
            id: id,
            name: name,
            country: Value(country),
            gpsLat: gpsLat,
            gpsLng: gpsLng,
            startFinishLineJson: Value(jsonEncode(startFinishLine)),
          ),
        );

    final circuit = await getCircuit(id);
    await _db.enqueueSync(
      targetTable: 'circuits',
      operation: 'insert',
      recordId: id,
      payloadJson:
          jsonEncode(SyncPayloads.circuit(circuit!, createdBy: userId)),
    );
    return circuit;
  }
}

/// Riverpod provider for [CircuitRepository].
final circuitRepositoryProvider = Provider<CircuitRepository>((ref) {
  return CircuitRepository(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
  );
});

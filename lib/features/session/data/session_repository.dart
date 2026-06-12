import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/sync_payloads.dart';

/// Repository for session CRUD operations using the local Drift database.
///
/// All mutations are written to local SQLite first, then enqueued
/// to the sync queue for eventual upload to Supabase.
class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  // ── Read operations ──

  /// Get a single session by ID.
  Future<LocalSession?> getSession(String sessionId) {
    return _db.getSession(sessionId);
  }

  /// Watch a single session by ID (reactive stream).
  Stream<LocalSession?> watchSession(String sessionId) {
    return (_db.select(_db.localSessions)
          ..where((t) => t.id.equals(sessionId)))
        .watchSingleOrNull();
  }

  /// Stream of all sessions for a given user, ordered by most recent first.
  Stream<List<LocalSession>> watchUserSessions(String userId) {
    return _db.watchUserSessions(userId);
  }

  /// Get all laps for a session, ordered by lap number.
  Future<List<LocalLap>> getSessionLaps(String sessionId) {
    return _db.getSessionLaps(sessionId);
  }

  /// Watch all laps for a session (reactive stream).
  Stream<List<LocalLap>> watchSessionLaps(String sessionId) {
    return _db.watchSessionLaps(sessionId);
  }

  /// Get a single lap by ID.
  Future<LocalLap?> getLap(String lapId) {
    return (_db.select(_db.localLaps)..where((t) => t.id.equals(lapId)))
        .getSingleOrNull();
  }

  /// Watch a single lap by ID (reactive stream).
  Stream<LocalLap?> watchLap(String lapId) {
    return (_db.select(_db.localLaps)..where((t) => t.id.equals(lapId)))
        .watchSingleOrNull();
  }

  /// Get sensor data for a specific lap.
  Future<LocalLapSensorDataData?> getLapSensorData(String lapId) {
    return (_db.select(_db.localLapSensorData)
          ..where((t) => t.lapId.equals(lapId)))
        .getSingleOrNull();
  }

  /// Get the circuit associated with a session.
  Future<LocalCircuit?> getCircuit(String circuitId) {
    return (_db.select(_db.localCircuits)
          ..where((t) => t.id.equals(circuitId)))
        .getSingleOrNull();
  }

  /// Get a car by ID.
  Future<LocalCar?> getCar(String carId) {
    return (_db.select(_db.localCars)..where((t) => t.id.equals(carId)))
        .getSingleOrNull();
  }

  /// Stream all cars for a user (for the car picker).
  Stream<List<LocalCar>> watchUserCars(String userId) {
    return _db.watchUserCars(userId);
  }

  // ── Write operations ──

  /// Discard (delete) a session and all its associated laps and sensor data.
  ///
  /// Removes everything from local DB and enqueues delete operations
  /// for Supabase sync so the data is cleaned up server-side too.
  Future<void> discardSession(String sessionId) async {
    final laps = await getSessionLaps(sessionId);
    final lapIds = laps.map((lap) => lap.id).toList(growable: false);
    // Sensor rows have UUID primary keys — look them up rather than
    // deriving ids (the legacy '<lapId>_sensors' scheme no longer exists).
    final sensorRows = lapIds.isEmpty
        ? const <LocalLapSensorDataData>[]
        : await (_db.select(_db.localLapSensorData)
              ..where((t) => t.lapId.isIn(lapIds)))
            .get();
    final sensorIds =
        sensorRows.map((row) => row.id).toList(growable: false);

    await _db.transaction(() async {
      // Remove stale queued inserts/updates first so a retry cannot recreate
      // data after the delete operations have been processed.
      await _db.removePendingSyncItems(
        targetTable: 'lap_sensor_data',
        recordIds: sensorIds,
      );
      await _db.removePendingSyncItems(
        targetTable: 'laps',
        recordIds: lapIds,
      );
      await _db.removePendingSyncItems(
        targetTable: 'sessions',
        recordIds: [sessionId],
      );

      for (final lapId in lapIds) {
        await (_db.delete(_db.localLapSensorData)
              ..where((t) => t.lapId.equals(lapId)))
            .go();
      }

      for (final sensorId in sensorIds) {
        await _db.enqueueSync(
          targetTable: 'lap_sensor_data',
          operation: 'delete',
          recordId: sensorId,
          payloadJson: jsonEncode({'id': sensorId}),
        );
      }

      for (final lapId in lapIds) {
        await (_db.delete(_db.localLaps)
              ..where((t) => t.id.equals(lapId)))
            .go();

        await _db.enqueueSync(
          targetTable: 'laps',
          operation: 'delete',
          recordId: lapId,
          payloadJson: jsonEncode({'id': lapId}),
        );
      }

      await (_db.delete(_db.localSessions)
            ..where((t) => t.id.equals(sessionId)))
          .go();

      await _db.enqueueSync(
        targetTable: 'sessions',
        operation: 'delete',
        recordId: sessionId,
        payloadJson: jsonEncode({'id': sessionId}),
      );
    });
  }

  /// Update session details (car, tyres, track condition, notes, privacy).
  ///
  /// Writes to local DB, then enqueues the change to the sync queue.
  /// Uses drift's [Value] tristate (same convention as the car/profile
  /// repositories): `Value.absent()` leaves the field untouched,
  /// `Value(null)` clears it.
  Future<void> updateSession({
    required String sessionId,
    Value<String?> circuitName = const Value.absent(),
    Value<String?> carId = const Value.absent(),
    Value<String?> trackCondition = const Value.absent(),
    Value<String?> tyreBrand = const Value.absent(),
    Value<String?> tyreCompound = const Value.absent(),
    Value<int?> tyreAgeLaps = const Value.absent(),
    Value<String?> setupNotes = const Value.absent(),
    Value<String?> sessionNotes = const Value.absent(),
    bool? isPublic,
  }) async {
    final companion = LocalSessionsCompanion(
      circuitName: circuitName,
      carId: carId,
      trackCondition: trackCondition,
      tyreBrand: tyreBrand,
      tyreCompound: tyreCompound,
      tyreAgeLaps: tyreAgeLaps,
      setupNotes: setupNotes,
      sessionNotes: sessionNotes,
      isPublic: isPublic != null ? Value(isPublic) : const Value.absent(),
    );

    await (_db.update(_db.localSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(companion);

    // Enqueue the full updated row so the server-side upsert is complete.
    final session = await getSession(sessionId);
    if (session != null) {
      await _db.enqueueSync(
        targetTable: 'sessions',
        operation: 'update',
        recordId: sessionId,
        payloadJson: jsonEncode(SyncPayloads.session(session)),
      );
    }
  }
}

/// Riverpod provider for SessionRepository.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return SessionRepository(db);
});

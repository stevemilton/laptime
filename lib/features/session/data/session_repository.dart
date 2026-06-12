import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/sync_payloads.dart';

/// Sentinel distinguishing "parameter not provided" from an explicit null
/// (which clears the field).
const Object _unset = Object();

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

  /// Update session details (car, tyres, track condition, notes, privacy).
  ///
  /// Writes to local DB, then enqueues the change to the sync queue.
  /// Omitted parameters leave the field untouched; passing null explicitly
  /// clears it.
  Future<void> updateSession({
    required String sessionId,
    Object? circuitName = _unset,
    Object? carId = _unset,
    Object? trackCondition = _unset,
    Object? tyreBrand = _unset,
    Object? tyreCompound = _unset,
    Object? tyreAgeLaps = _unset,
    Object? setupNotes = _unset,
    Object? sessionNotes = _unset,
    bool? isPublic,
  }) async {
    Value<String?> str(Object? raw) =>
        identical(raw, _unset) ? const Value.absent() : Value(raw as String?);

    final companion = LocalSessionsCompanion(
      circuitName: str(circuitName),
      carId: str(carId),
      trackCondition: str(trackCondition),
      tyreBrand: str(tyreBrand),
      tyreCompound: str(tyreCompound),
      tyreAgeLaps: identical(tyreAgeLaps, _unset)
          ? const Value.absent()
          : Value(tyreAgeLaps as int?),
      setupNotes: str(setupNotes),
      sessionNotes: str(sessionNotes),
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

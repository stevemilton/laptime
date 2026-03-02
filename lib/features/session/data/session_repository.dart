import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';

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
  Future<void> updateSession({
    required String sessionId,
    String? circuitName,
    String? carId,
    String? trackCondition,
    String? tyreBrand,
    String? tyreCompound,
    int? tyreAgeLaps,
    String? setupNotes,
    String? sessionNotes,
    bool? isPublic,
  }) async {
    final companion = LocalSessionsCompanion(
      circuitName: Value(circuitName),
      carId: carId != null ? Value(carId) : const Value.absent(),
      trackCondition: trackCondition != null
          ? Value(trackCondition)
          : const Value.absent(),
      tyreBrand: tyreBrand != null ? Value(tyreBrand) : const Value.absent(),
      tyreCompound:
          tyreCompound != null ? Value(tyreCompound) : const Value.absent(),
      tyreAgeLaps:
          tyreAgeLaps != null ? Value(tyreAgeLaps) : const Value.absent(),
      setupNotes: Value(setupNotes),
      sessionNotes: Value(sessionNotes),
      isPublic: isPublic != null ? Value(isPublic) : const Value.absent(),
    );

    await (_db.update(_db.localSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(companion);

    // Build payload for sync queue
    final session = await getSession(sessionId);
    if (session != null) {
      final payload = <String, dynamic>{
        'id': session.id,
        'user_id': session.userId,
        'car_id': session.carId,
        'circuit_id': session.circuitId,
        'circuit_name': session.circuitName,
        'started_at': session.startedAt.toIso8601String(),
        'ended_at': session.endedAt?.toIso8601String(),
        'track_condition': session.trackCondition,
        'tyre_brand': session.tyreBrand,
        'tyre_compound': session.tyreCompound,
        'tyre_age_laps': session.tyreAgeLaps,
        'setup_notes': session.setupNotes,
        'session_notes': session.sessionNotes,
        'weather_json': session.weatherJson,
        'is_public': session.isPublic,
      };

      await _db.enqueueSync(
        targetTable: 'sessions',
        operation: 'update',
        recordId: sessionId,
        payloadJson: jsonEncode(payload),
      );
    }
  }
}

/// Riverpod provider for SessionRepository.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return SessionRepository(db);
});

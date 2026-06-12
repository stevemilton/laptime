import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'sync_payloads.dart';
import 'sync_service.dart';

/// Re-enqueues all of a user's local data for upload.
///
/// Historically the sync queue dead-lettered items whose payloads didn't
/// match the remote schema (see docs/V2_CODE_REVIEW.md, D1-D7). The data
/// still exists locally; this sweep rebuilds the queue from local rows
/// using the corrected [SyncPayloads] builders so it can finally upload.
///
/// Safe to run repeatedly: all server writes are idempotent upserts.
class ReconciliationService {
  ReconciliationService({
    required AppDatabase database,
    required SyncService syncService,
  })  : _db = database,
        _sync = syncService;

  final AppDatabase _db;
  final SyncService _sync;

  bool _running = false;

  /// Enqueue every locally stored record owned by [userId], in
  /// parent-before-child order, then trigger a sync pass.
  Future<void> resyncAll(String userId) async {
    if (_running) return;
    _running = true;
    try {
      // Drop the dead-letter graveyard: stale payloads in failed items are
      // superseded by the fresh full-row payloads enqueued below.
      await _db.purgeDeadLetters();

      final profile = await _db.getProfile(userId);
      if (profile != null) {
        await _enqueue('profiles', profile.id, SyncPayloads.profile(profile));
      }

      final cars = await (_db.select(_db.localCars)
            ..where((t) => t.userId.equals(userId)))
          .get();
      for (final car in cars) {
        await _enqueue('cars', car.id, SyncPayloads.car(car));
      }

      final sessions = await (_db.select(_db.localSessions)
            ..where((t) => t.userId.equals(userId)))
          .get();
      for (final session in sessions) {
        await _enqueue('sessions', session.id, SyncPayloads.session(session));

        final laps = await _db.getSessionLaps(session.id);
        for (final lap in laps) {
          await _enqueue('laps', lap.id, SyncPayloads.lap(lap));

          final sensor = await (_db.select(_db.localLapSensorData)
                ..where((t) => t.lapId.equals(lap.id)))
              .get();
          for (final row in sensor) {
            await _enqueue(
                'lap_sensor_data', row.id, SyncPayloads.lapSensorData(row));
          }
        }
      }

      final sectors = await (_db.select(_db.localSectors)
            ..where((t) => t.createdBy.equals(userId)))
          .get();
      for (final sector in sectors) {
        await _enqueue('sectors', sector.id, SyncPayloads.sector(sector));
      }

      final sectorTimes = await (_db.select(_db.localSectorTimes)
            ..where((t) => t.userId.equals(userId)))
          .get();
      for (final time in sectorTimes) {
        await _enqueue(
            'sector_times', time.id, SyncPayloads.sectorTime(time));
      }

      debugPrint('ReconciliationService: resync enqueued for $userId');
      _sync.requestSync();
    } finally {
      _running = false;
    }
  }

  Future<void> _enqueue(
    String table,
    String recordId,
    Map<String, dynamic> payload,
  ) async {
    // Skip if an identical pending item already exists (e.g. resync tapped
    // twice before the queue drains).
    final existing = await (_db.select(_db.localSyncQueue)
          ..where((t) =>
              t.targetTable.equals(table) &
              t.recordId.equals(recordId) &
              t.operation.equals('insert'))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.localSyncQueue)
            ..where((t) => t.id.equals(existing.id)))
          .write(LocalSyncQueueCompanion(
        payloadJson: Value(jsonEncode(payload)),
        retryCount: const Value(0),
        errorMessage: const Value(null),
      ));
      return;
    }

    await _db.enqueueSync(
      targetTable: table,
      operation: 'insert',
      recordId: recordId,
      payloadJson: jsonEncode(payload),
    );
  }
}

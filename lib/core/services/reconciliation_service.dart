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
  ///
  /// All reads happen up front and all queue writes go through one batch
  /// in a single transaction — this runs at app startup after the v2
  /// update, where thousands of per-row statements would stall first
  /// launch for seconds.
  Future<void> resyncAll(String userId) async {
    if (_running) return;
    _running = true;
    try {
      // Drop the dead-letter graveyard: stale payloads in failed items are
      // superseded by the fresh full-row payloads enqueued below.
      await _db.purgeDeadLetters();

      // (table, recordId) pairs already pending, fetched once.
      final pendingRows = await (_db.select(_db.localSyncQueue)
            ..where((t) => t.operation.equals('insert')))
          .get();
      final pendingByKey = {
        for (final row in pendingRows) '${row.targetTable}|${row.recordId}': row,
      };

      // Ordered (table, recordId, payload) triples: parents before children.
      final entries = <(String, String, Map<String, dynamic>)>[];

      final profile = await _db.getProfile(userId);
      if (profile != null) {
        entries.add(('profiles', profile.id, SyncPayloads.profile(profile)));
      }

      final cars = await (_db.select(_db.localCars)
            ..where((t) => t.userId.equals(userId)))
          .get();
      for (final car in cars) {
        entries.add(('cars', car.id, SyncPayloads.car(car)));
      }

      // Circuits before the sessions that reference them. The cache can't
      // tell user-created circuits from catalogue ones, so all are
      // re-enqueued; the sync engine inserts circuits with
      // ignoreDuplicates, making catalogue rows a no-op.
      final circuits = await _db.getAllCircuits();
      for (final circuit in circuits) {
        entries.add((
          'circuits',
          circuit.id,
          SyncPayloads.circuit(circuit, createdBy: userId),
        ));
      }

      final sessions = await (_db.select(_db.localSessions)
            ..where((t) => t.userId.equals(userId)))
          .get();
      for (final session in sessions) {
        entries.add(('sessions', session.id, SyncPayloads.session(session)));

        final laps = await _db.getSessionLaps(session.id);
        for (final lap in laps) {
          entries.add(('laps', lap.id, SyncPayloads.lap(lap)));

          final sensor = await (_db.select(_db.localLapSensorData)
                ..where((t) => t.lapId.equals(lap.id)))
              .get();
          for (final row in sensor) {
            entries.add(
                ('lap_sensor_data', row.id, SyncPayloads.lapSensorData(row)));
          }
        }
      }

      final sectors = await (_db.select(_db.localSectors)
            ..where((t) => t.createdBy.equals(userId)))
          .get();
      for (final sector in sectors) {
        entries.add(('sectors', sector.id, SyncPayloads.sector(sector)));
      }

      final sectorTimes = await (_db.select(_db.localSectorTimes)
            ..where((t) => t.userId.equals(userId)))
          .get();
      for (final time in sectorTimes) {
        entries.add(
            ('sector_times', time.id, SyncPayloads.sectorTime(time)));
      }

      await _db.batch((batch) {
        for (final (table, recordId, payload) in entries) {
          final existing = pendingByKey['$table|$recordId'];
          if (existing != null) {
            // Refresh the stale pending payload instead of duplicating it.
            batch.update(
              _db.localSyncQueue,
              LocalSyncQueueCompanion(
                payloadJson: Value(jsonEncode(payload)),
                retryCount: const Value(0),
                errorMessage: const Value(null),
              ),
              where: (t) => t.id.equals(existing.id),
            );
          } else {
            batch.insert(
              _db.localSyncQueue,
              LocalSyncQueueCompanion.insert(
                targetTable: table,
                operation: 'insert',
                recordId: recordId,
                payloadJson: jsonEncode(payload),
              ),
            );
          }
        }
      });

      debugPrint(
          'ReconciliationService: ${entries.length} items enqueued for $userId');
      _sync.requestSync();
    } finally {
      _running = false;
    }
  }
}

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/profiles_table.dart';
import 'tables/cars_table.dart';
import 'tables/circuits_table.dart';
import 'tables/sessions_table.dart';
import 'tables/laps_table.dart';
import 'tables/lap_sensor_data_table.dart';
import 'tables/sectors_table.dart';
import 'tables/sector_times_table.dart';
import 'tables/follows_table.dart';
import 'tables/teams_table.dart';
import 'tables/crews_table.dart';
import 'tables/team_join_requests_table.dart';
import 'tables/disclaimer_table.dart';
import 'tables/session_likes_table.dart';
import 'tables/session_comments_table.dart';
import 'tables/sync_queue_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  LocalProfiles,
  LocalCars,
  LocalCircuits,
  LocalSessions,
  LocalLaps,
  LocalLapSensorData,
  LocalSectors,
  LocalSectorTimes,
  LocalFollows,
  LocalTeams,
  LocalTeamMembers,
  LocalCrews,
  LocalCrewMembers,
  LocalTeamJoinRequests,
  LocalDisclaimerAcceptances,
  LocalSessionLikes,
  LocalSessionComments,
  LocalSyncQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For testing
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // v2: Add new car fields for enthusiast features
          await m.addColumn(localCars, localCars.imageUrl);
          await m.addColumn(localCars, localCars.powerHp);
          await m.addColumn(localCars, localCars.weightKg);
          await m.addColumn(localCars, localCars.drivetrain);
          await m.addColumn(localCars, localCars.engineCapacity);
          await m.addColumn(localCars, localCars.modifications);
          await m.addColumn(localCars, localCars.tyreSetup);
        }
        if (from < 3) {
          // v3: Add circuit name directly on sessions
          await m.addColumn(localSessions, localSessions.circuitName);
        }
        if (from < 4) {
          // v4: Expand team system (crews, join requests, team metadata)
          await m.addColumn(localTeams, localTeams.location);
          await m.addColumn(localTeams, localTeams.logoUrl);
          await m.addColumn(localTeams, localTeams.verified);
          await m.createTable(localCrews);
          await m.createTable(localCrewMembers);
          await m.createTable(localTeamJoinRequests);
          // Migrate 'owner' role to 'admin'
          await customStatement(
              "UPDATE local_team_members SET role = 'admin' WHERE role = 'owner'");
        }
        if (from < 5) {
          // v5: Social feed — likes and comments
          await m.createTable(localSessionLikes);
          await m.createTable(localSessionComments);
        }
        if (from < 6) {
          // v6: Mark incomplete laps so PBs/sector scoring can skip them
          await m.addColumn(localLaps, localLaps.isPartial);
        }
      },
    );
  }

  // ── Sync Queue helpers ──

  Future<int> enqueueSync({
    required String targetTable,
    required String operation,
    required String recordId,
    required String payloadJson,
  }) {
    return into(localSyncQueue).insert(
      LocalSyncQueueCompanion.insert(
        targetTable: targetTable,
        operation: operation,
        recordId: recordId,
        payloadJson: payloadJson,
        ),
      );
  }

  /// Returns whether a queue item already exists for a given record.
  Future<bool> hasPendingSyncItem({
    required String targetTable,
    required String recordId,
  }) async {
    final existing = await (select(localSyncQueue)
          ..where((t) =>
              t.targetTable.equals(targetTable) &
              t.recordId.equals(recordId))
          ..limit(1))
        .getSingleOrNull();
    return existing != null;
  }

  /// Removes queued sync items for the given records.
  Future<void> removePendingSyncItems({
    required String targetTable,
    required Iterable<String> recordIds,
  }) async {
    final ids = recordIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;

    await (delete(localSyncQueue)
          ..where((t) =>
              t.targetTable.equals(targetTable) & t.recordId.isIn(ids)))
        .go();
  }

  Future<List<LocalSyncQueueData>> getPendingSyncItems({
    int limit = 50,
    int maxRetries = 5,
  }) {
    return (select(localSyncQueue)
          ..where((t) => t.retryCount.isSmallerThanValue(maxRetries))
          // createdAt has second precision; the autoincrement id is the
          // true FIFO key for items enqueued in the same second.
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(limit))
        .get();
  }

  /// Total number of items still eligible for sync (not dead-lettered).
  Future<int> pendingSyncCount({int maxRetries = 5}) async {
    final countExp = localSyncQueue.id.count();
    final query = selectOnly(localSyncQueue)
      ..addColumns([countExp])
      ..where(localSyncQueue.retryCount.isSmallerThanValue(maxRetries));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Items that exhausted their retries and need user-visible recovery.
  Future<List<LocalSyncQueueData>> getDeadLetterItems({int maxRetries = 5}) {
    return (select(localSyncQueue)
          ..where(
              (t) => t.retryCount.isBiggerOrEqualValue(maxRetries))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// Number of dead-lettered items.
  Future<int> deadLetterCount({int maxRetries = 5}) async {
    final countExp = localSyncQueue.id.count();
    final query = selectOnly(localSyncQueue)
      ..addColumns([countExp])
      ..where(localSyncQueue.retryCount.isBiggerOrEqualValue(maxRetries));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Give all dead-lettered items another full set of retries.
  Future<void> resetDeadLetters({int maxRetries = 5}) {
    return (update(localSyncQueue)
          ..where((t) => t.retryCount.isBiggerOrEqualValue(maxRetries)))
        .write(const LocalSyncQueueCompanion(
      retryCount: Value(0),
      errorMessage: Value(null),
    ));
  }

  /// Permanently remove dead-lettered insert/update items (used by
  /// reconciliation, which re-enqueues fresh payloads built from the local
  /// rows). Dead-lettered DELETES are reset for retry instead — the local
  /// row is gone, so a purged delete could never be rebuilt.
  Future<void> purgeDeadLetters({int maxRetries = 5}) async {
    await (delete(localSyncQueue)
          ..where((t) =>
              t.retryCount.isBiggerOrEqualValue(maxRetries) &
              t.operation.equals('delete').not()))
        .go();
    await (update(localSyncQueue)
          ..where((t) => t.retryCount.isBiggerOrEqualValue(maxRetries)))
        .write(const LocalSyncQueueCompanion(
      retryCount: Value(0),
      errorMessage: Value(null),
    ));
  }

  Future<void> markSyncCompleted(int queueId) {
    return (delete(localSyncQueue)..where((t) => t.id.equals(queueId))).go();
  }

  /// Delete every row in every table. Called on sign-out and account
  /// deletion so the next user (or a fresh sign-in) starts clean and no
  /// stale queue items are pushed under another user's credentials.
  Future<void> wipeAllData() async {
    await transaction(() async {
      for (final table in allTables) {
        await customStatement('DELETE FROM ${table.actualTableName}');
      }
    });
  }

  /// Persist an updated payload (e.g. after replacing local image paths with
  /// public URLs). This prevents retries from re-uploading local files that
  /// may have been cleaned up by the OS.
  Future<void> updateSyncPayload(int queueId, String payloadJson) {
    return (update(localSyncQueue)..where((t) => t.id.equals(queueId))).write(
      LocalSyncQueueCompanion(payloadJson: Value(payloadJson)),
    );
  }

  Future<void> markSyncFailed(int queueId, String error) async {
    await transaction(() async {
      final item = await (select(localSyncQueue)
            ..where((t) => t.id.equals(queueId)))
          .getSingleOrNull();
      if (item == null) return;

      await (update(localSyncQueue)..where((t) => t.id.equals(queueId))).write(
        LocalSyncQueueCompanion(
          retryCount: Value(item.retryCount + 1),
          lastAttemptedAt: Value(DateTime.now()),
          errorMessage: Value(error),
        ),
      );
    });
  }

  // ── Profile helpers ──

  Future<LocalProfile?> getProfile(String userId) {
    return (select(localProfiles)..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
  }

  // ── Car helpers ──

  Stream<List<LocalCar>> watchUserCars(String userId) {
    return (select(localCars)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  // ── Session helpers ──

  Stream<List<LocalSession>> watchUserSessions(String userId) {
    return (select(localSessions)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .watch();
  }

  Future<LocalSession?> getSession(String sessionId) {
    return (select(localSessions)..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
  }

  // ── Lap helpers ──

  Stream<List<LocalLap>> watchSessionLaps(String sessionId) {
    return (select(localLaps)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.lapNumber)]))
        .watch();
  }

  Future<List<LocalLap>> getSessionLaps(String sessionId) {
    return (select(localLaps)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.lapNumber)]))
        .get();
  }

  Future<LocalLap?> getLap(String lapId) {
    return (select(localLaps)..where((t) => t.id.equals(lapId)))
        .getSingleOrNull();
  }

  Future<LocalLapSensorDataData?> getLapSensorData(String lapId) {
    return (select(localLapSensorData)..where((t) => t.lapId.equals(lapId)))
        .getSingleOrNull();
  }

  // ── Circuit helpers ──

  Future<List<LocalCircuit>> getAllCircuits() {
    return (select(localCircuits)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  // ── Circuit session helpers ──

  Future<List<LocalSession>> getCircuitSessions(String circuitId) {
    return (select(localSessions)
          ..where((t) => t.circuitId.equals(circuitId))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .get();
  }

  // ── Disclaimer helpers ──

  Future<LocalDisclaimerAcceptance?> getLatestDisclaimer(String userId) {
    return (select(localDisclaimerAcceptances)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.acceptedAt)])
          ..limit(1))
        .getSingleOrNull();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'laptime.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

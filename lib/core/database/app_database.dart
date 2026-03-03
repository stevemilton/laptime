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
  LocalSyncQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For testing
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

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

  Future<List<LocalSyncQueueData>> getPendingSyncItems({int limit = 50}) {
    return (select(localSyncQueue)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> markSyncCompleted(int queueId) {
    return (delete(localSyncQueue)..where((t) => t.id.equals(queueId))).go();
  }

  Future<void> markSyncFailed(int queueId, String error) async {
    // Read current retry count, then write incremented value
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

  // ── Circuit helpers ──

  Future<List<LocalCircuit>> getAllCircuits() {
    return (select(localCircuits)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
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

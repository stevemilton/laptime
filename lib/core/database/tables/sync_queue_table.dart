import 'package:drift/drift.dart';

/// Offline-first sync queue. Every local mutation is enqueued here
/// and processed by the SyncService when connectivity is available.
class LocalSyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetTable => text()(); // e.g. 'sessions', 'laps', 'cars'
  TextColumn get operation => text()(); // 'insert', 'update', 'delete'
  TextColumn get recordId => text()(); // UUID of the record
  TextColumn get payloadJson => text()(); // Full record as JSON
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptedAt => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();
}

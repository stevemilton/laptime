import 'package:drift/drift.dart';

class LocalSessions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get carId => text().nullable()();
  TextColumn get circuitId => text().nullable()();
  TextColumn get circuitName => text().nullable()(); // User-entered circuit/track name
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get trackCondition => text().nullable()(); // dry, damp, wet, mixed
  TextColumn get tyreBrand => text().nullable()();
  TextColumn get tyreCompound => text().nullable()();
  IntColumn get tyreAgeLaps => integer().nullable()();
  TextColumn get setupNotes => text().nullable()();
  TextColumn get sessionNotes => text().nullable()();
  TextColumn get weatherJson => text().nullable()(); // Full API response as JSON string
  BoolColumn get isPublic => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

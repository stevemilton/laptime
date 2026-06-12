import 'package:drift/drift.dart';

class LocalLaps extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  IntColumn get lapNumber => integer()();
  IntColumn get durationMs => integer()();
  BoolColumn get isPersonalBest => boolean().withDefault(const Constant(false))();
  // Incomplete lap (e.g. the only segment of a session with no completed
  // laps). Excluded from personal bests and sector scoring.
  BoolColumn get isPartial => boolean().withDefault(const Constant(false))();
  // GPS trace v2: JSON array of [lng, lat, tMs, speedMps] (see TraceCodec)
  TextColumn get traceJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

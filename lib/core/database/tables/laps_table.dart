import 'package:drift/drift.dart';

class LocalLaps extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  IntColumn get lapNumber => integer()();
  IntColumn get durationMs => integer()();
  BoolColumn get isPersonalBest => boolean().withDefault(const Constant(false))();
  // GPS trace stored as JSON array of {lat, lng, timestamp, accuracy, speed, bearing}
  TextColumn get traceJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

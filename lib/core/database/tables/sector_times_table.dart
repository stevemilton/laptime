import 'package:drift/drift.dart';

class LocalSectorTimes extends Table {
  TextColumn get id => text()();
  TextColumn get sectorId => text()();
  TextColumn get lapId => text()();
  TextColumn get sessionId => text()();
  TextColumn get userId => text()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get computedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

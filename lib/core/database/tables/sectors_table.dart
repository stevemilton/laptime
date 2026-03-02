import 'package:drift/drift.dart';

class LocalSectors extends Table {
  TextColumn get id => text()();
  TextColumn get circuitId => text()();
  TextColumn get createdBy => text()();
  TextColumn get name => text()();
  // Points stored as JSON: {"lat": ..., "lng": ...}
  TextColumn get startPointJson => text().nullable()();
  TextColumn get endPointJson => text().nullable()();
  TextColumn get lineJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

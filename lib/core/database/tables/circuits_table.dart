import 'package:drift/drift.dart';

class LocalCircuits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get country => text().withDefault(const Constant('GB'))();
  RealColumn get gpsLat => real()();
  RealColumn get gpsLng => real()();
  // Start/finish line stored as JSON-encoded list of [lat,lng] pairs
  TextColumn get startFinishLineJson => text().nullable()();
  IntColumn get lengthM => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

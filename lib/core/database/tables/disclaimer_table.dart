import 'package:drift/drift.dart';

class LocalDisclaimerAcceptances extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get acceptedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get appVersion => text()();
  TextColumn get disclaimerVersion => text()();

  @override
  Set<Column> get primaryKey => {id};
}

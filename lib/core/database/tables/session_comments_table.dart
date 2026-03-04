import 'package:drift/drift.dart';

class LocalSessionComments extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get userId => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

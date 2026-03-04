import 'package:drift/drift.dart';

class LocalSessionLikes extends Table {
  TextColumn get sessionId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sessionId, userId};
}

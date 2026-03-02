import 'package:drift/drift.dart';

class LocalFollows extends Table {
  TextColumn get followerId => text()();
  TextColumn get followingId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {followerId, followingId};
}

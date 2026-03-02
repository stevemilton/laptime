import 'package:drift/drift.dart';

class LocalTeams extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get code => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalTeamMembers extends Table {
  TextColumn get teamId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {teamId, userId};
}

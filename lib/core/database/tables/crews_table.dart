import 'package:drift/drift.dart';

class LocalCrews extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get name => text()();
  TextColumn get inviteCode => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCrewMembers extends Table {
  TextColumn get crewId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {crewId, userId};
}

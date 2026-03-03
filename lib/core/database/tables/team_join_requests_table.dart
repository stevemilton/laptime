import 'package:drift/drift.dart';

class LocalTeamJoinRequests extends Table {
  TextColumn get id => text()();
  TextColumn get teamId => text()();
  TextColumn get userId => text()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending|approved|rejected|cancelled
  TextColumn get message => text().nullable()();
  DateTimeColumn get requestedAt =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get reviewedBy => text().nullable()();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  TextColumn get rejectionReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

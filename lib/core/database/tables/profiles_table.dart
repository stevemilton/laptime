import 'package:drift/drift.dart';

class LocalProfiles extends Table {
  TextColumn get id => text()(); // UUID from Supabase auth
  TextColumn get displayName => text().withDefault(const Constant('Driver'))();
  TextColumn get handle => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

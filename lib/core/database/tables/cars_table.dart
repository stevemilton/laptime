import 'package:drift/drift.dart';

class LocalCars extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get make => text()();
  TextColumn get model => text()();
  IntColumn get year => integer().nullable()();
  TextColumn get carClass => text().nullable()(); // 'class' is reserved
  TextColumn get colour => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

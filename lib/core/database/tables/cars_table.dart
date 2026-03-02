import 'package:drift/drift.dart';

class LocalCars extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get make => text()();
  TextColumn get model => text()();
  IntColumn get year => integer().nullable()();
  TextColumn get carClass => text().nullable()(); // 'class' is reserved
  TextColumn get colour => text().nullable()();
  TextColumn get imageUrl => text().nullable()(); // local file path or remote URL
  IntColumn get powerHp => integer().nullable()(); // horsepower
  IntColumn get weightKg => integer().nullable()(); // kerb weight in kg
  TextColumn get drivetrain => text().nullable()(); // FWD, RWD, AWD, etc.
  TextColumn get engineCapacity => text().nullable()(); // e.g. "2.0L", "600cc"
  TextColumn get modifications => text().nullable()(); // freeform mods description
  TextColumn get tyreSetup => text().nullable()(); // default tyre brand/compound
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

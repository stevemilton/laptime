import 'package:drift/drift.dart';

class LocalLapSensorData extends Table {
  TextColumn get id => text()();
  TextColumn get lapId => text()();
  // All sensor data stored as JSON-encoded arrays for efficient bulk read/write
  TextColumn get timestampsJson => text()(); // double[]
  TextColumn get accelXJson => text().nullable()(); // float[]
  TextColumn get accelYJson => text().nullable()();
  TextColumn get accelZJson => text().nullable()();
  TextColumn get gyroXJson => text().nullable()();
  TextColumn get gyroYJson => text().nullable()();
  TextColumn get gyroZJson => text().nullable()();
  TextColumn get baroPressureJson => text().nullable()();
  TextColumn get magHeadingJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

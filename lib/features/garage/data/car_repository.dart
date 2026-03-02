// ignore_for_file: use_null_aware_elements

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';

/// Repository for car CRUD operations (Garage feature).
class CarRepository {
  CarRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Watch all cars for a user.
  Stream<List<LocalCar>> watchUserCars(String userId) {
    return _db.watchUserCars(userId);
  }

  /// Get all cars for a user.
  Future<List<LocalCar>> getUserCars(String userId) {
    return (_db.select(_db.localCars)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Get a single car by ID.
  Future<LocalCar?> getCar(String carId) {
    return (_db.select(_db.localCars)
          ..where((t) => t.id.equals(carId)))
        .getSingleOrNull();
  }

  /// Create a new car.
  Future<String> createCar({
    required String userId,
    required String make,
    required String model,
    int? year,
    String? carClass,
    String? colour,
    String? imageUrl,
    int? powerHp,
    int? weightKg,
    String? drivetrain,
    String? engineCapacity,
    String? modifications,
    String? tyreSetup,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.into(_db.localCars).insert(
      LocalCarsCompanion.insert(
        id: id,
        userId: userId,
        make: make,
        model: model,
        year: Value(year),
        carClass: Value(carClass),
        colour: Value(colour),
        imageUrl: Value(imageUrl),
        powerHp: Value(powerHp),
        weightKg: Value(weightKg),
        drivetrain: Value(drivetrain),
        engineCapacity: Value(engineCapacity),
        modifications: Value(modifications),
        tyreSetup: Value(tyreSetup),
        createdAt: Value(now),
      ),
    );

    await _db.enqueueSync(
      targetTable: 'cars',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'user_id': userId,
        'make': make,
        'model': model,
        if (year != null) 'year': year,
        if (carClass != null) 'class': carClass,
        if (colour != null) 'colour': colour,
        if (imageUrl != null) 'image_url': imageUrl,
        if (powerHp != null) 'power_hp': powerHp,
        if (weightKg != null) 'weight_kg': weightKg,
        if (drivetrain != null) 'drivetrain': drivetrain,
        if (engineCapacity != null) 'engine_capacity': engineCapacity,
        if (modifications != null) 'modifications': modifications,
        if (tyreSetup != null) 'tyre_setup': tyreSetup,
        'created_at': now.toIso8601String(),
      }),
    );

    return id;
  }

  /// Update an existing car.
  Future<void> updateCar({
    required String carId,
    String? make,
    String? model,
    int? year,
    String? carClass,
    String? colour,
    String? imageUrl,
    int? powerHp,
    int? weightKg,
    String? drivetrain,
    String? engineCapacity,
    String? modifications,
    String? tyreSetup,
  }) async {
    await (_db.update(_db.localCars)..where((t) => t.id.equals(carId))).write(
      LocalCarsCompanion(
        make: make != null ? Value(make) : const Value.absent(),
        model: model != null ? Value(model) : const Value.absent(),
        year: year != null ? Value(year) : const Value.absent(),
        carClass: carClass != null ? Value(carClass) : const Value.absent(),
        colour: colour != null ? Value(colour) : const Value.absent(),
        imageUrl: imageUrl != null ? Value(imageUrl) : const Value.absent(),
        powerHp: powerHp != null ? Value(powerHp) : const Value.absent(),
        weightKg: weightKg != null ? Value(weightKg) : const Value.absent(),
        drivetrain:
            drivetrain != null ? Value(drivetrain) : const Value.absent(),
        engineCapacity: engineCapacity != null
            ? Value(engineCapacity)
            : const Value.absent(),
        modifications:
            modifications != null ? Value(modifications) : const Value.absent(),
        tyreSetup: tyreSetup != null ? Value(tyreSetup) : const Value.absent(),
      ),
    );

    final payload = <String, dynamic>{'id': carId};
    if (make != null) payload['make'] = make;
    if (model != null) payload['model'] = model;
    if (year != null) payload['year'] = year;
    if (carClass != null) payload['class'] = carClass;
    if (colour != null) payload['colour'] = colour;
    if (imageUrl != null) payload['image_url'] = imageUrl;
    if (powerHp != null) payload['power_hp'] = powerHp;
    if (weightKg != null) payload['weight_kg'] = weightKg;
    if (drivetrain != null) payload['drivetrain'] = drivetrain;
    if (engineCapacity != null) payload['engine_capacity'] = engineCapacity;
    if (modifications != null) payload['modifications'] = modifications;
    if (tyreSetup != null) payload['tyre_setup'] = tyreSetup;

    await _db.enqueueSync(
      targetTable: 'cars',
      operation: 'update',
      recordId: carId,
      payloadJson: jsonEncode(payload),
    );
  }

  /// Delete a car.
  Future<void> deleteCar(String carId) async {
    await (_db.delete(_db.localCars)..where((t) => t.id.equals(carId))).go();

    await _db.enqueueSync(
      targetTable: 'cars',
      operation: 'delete',
      recordId: carId,
      payloadJson: '{"id":"$carId"}',
    );
  }
}

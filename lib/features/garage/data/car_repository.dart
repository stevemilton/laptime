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
  ///
  /// Uses insertOnConflictUpdate (upsert) to ensure all fields are explicitly
  /// written, matching the pattern used by ProfileRepository.updateProfile.
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
    // Fetch existing car to merge unchanged fields for a full upsert.
    final existing = await getCar(carId);
    if (existing == null) return;

    await _db.into(_db.localCars).insertOnConflictUpdate(
      LocalCarsCompanion.insert(
        id: carId,
        userId: existing.userId,
        make: make ?? existing.make,
        model: model ?? existing.model,
        year: Value(year ?? existing.year),
        carClass: Value(carClass ?? existing.carClass),
        colour: Value(colour ?? existing.colour),
        imageUrl: Value(imageUrl ?? existing.imageUrl),
        powerHp: Value(powerHp ?? existing.powerHp),
        weightKg: Value(weightKg ?? existing.weightKg),
        drivetrain: Value(drivetrain ?? existing.drivetrain),
        engineCapacity: Value(engineCapacity ?? existing.engineCapacity),
        modifications: Value(modifications ?? existing.modifications),
        tyreSetup: Value(tyreSetup ?? existing.tyreSetup),
        createdAt: Value(existing.createdAt),
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

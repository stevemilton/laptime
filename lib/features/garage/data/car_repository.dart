// ignore_for_file: use_null_aware_elements

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';

/// Groups optional car fields for create/update operations.
class CarFormData {
  const CarFormData({
    this.year,
    this.carClass,
    this.colour,
    this.imageUrl,
    this.powerHp,
    this.weightKg,
    this.drivetrain,
    this.engineCapacity,
    this.modifications,
    this.tyreSetup,
  });

  final int? year;
  final String? carClass;
  final String? colour;
  final String? imageUrl;
  final int? powerHp;
  final int? weightKg;
  final String? drivetrain;
  final String? engineCapacity;
  final String? modifications;
  final String? tyreSetup;

  /// Build the sync payload map (uses Supabase column names).
  Map<String, dynamic> toSyncPayload() => {
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
      };
}

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
    CarFormData data = const CarFormData(),
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.into(_db.localCars).insert(
      LocalCarsCompanion.insert(
        id: id,
        userId: userId,
        make: make,
        model: model,
        year: Value(data.year),
        carClass: Value(data.carClass),
        colour: Value(data.colour),
        imageUrl: Value(data.imageUrl),
        powerHp: Value(data.powerHp),
        weightKg: Value(data.weightKg),
        drivetrain: Value(data.drivetrain),
        engineCapacity: Value(data.engineCapacity),
        modifications: Value(data.modifications),
        tyreSetup: Value(data.tyreSetup),
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
        ...data.toSyncPayload(),
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
    CarFormData data = const CarFormData(),
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
        year: Value(data.year ?? existing.year),
        carClass: Value(data.carClass ?? existing.carClass),
        colour: Value(data.colour ?? existing.colour),
        imageUrl: Value(data.imageUrl ?? existing.imageUrl),
        powerHp: Value(data.powerHp ?? existing.powerHp),
        weightKg: Value(data.weightKg ?? existing.weightKg),
        drivetrain: Value(data.drivetrain ?? existing.drivetrain),
        engineCapacity: Value(data.engineCapacity ?? existing.engineCapacity),
        modifications: Value(data.modifications ?? existing.modifications),
        tyreSetup: Value(data.tyreSetup ?? existing.tyreSetup),
        createdAt: Value(existing.createdAt),
      ),
    );

    final payload = <String, dynamic>{'id': carId};
    if (make != null) payload['make'] = make;
    if (model != null) payload['model'] = model;
    payload.addAll(data.toSyncPayload());

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

/// Riverpod provider for CarRepository.
final carRepositoryProvider = Provider<CarRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CarRepository(db);
});

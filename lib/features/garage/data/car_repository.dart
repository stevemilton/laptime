import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/sync_payloads.dart';

/// Groups optional car fields for create/update operations.
///
/// Every field uses Drift's [Value] wrapper so callers can distinguish
/// "not provided, leave unchanged" ([Value.absent]) from "explicitly
/// cleared" (`Value(null)`) - this is what makes "Remove Photo" and
/// clearing other optional fields actually stick.
class CarFormData {
  const CarFormData({
    this.year = const Value.absent(),
    this.carClass = const Value.absent(),
    this.colour = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.powerHp = const Value.absent(),
    this.weightKg = const Value.absent(),
    this.drivetrain = const Value.absent(),
    this.engineCapacity = const Value.absent(),
    this.modifications = const Value.absent(),
    this.tyreSetup = const Value.absent(),
  });

  final Value<int?> year;
  final Value<String?> carClass;
  final Value<String?> colour;
  final Value<String?> imageUrl;
  final Value<int?> powerHp;
  final Value<int?> weightKg;
  final Value<String?> drivetrain;
  final Value<String?> engineCapacity;
  final Value<String?> modifications;
  final Value<String?> tyreSetup;
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
        year: data.year,
        carClass: data.carClass,
        colour: data.colour,
        imageUrl: data.imageUrl,
        powerHp: data.powerHp,
        weightKg: data.weightKg,
        drivetrain: data.drivetrain,
        engineCapacity: data.engineCapacity,
        modifications: data.modifications,
        tyreSetup: data.tyreSetup,
        createdAt: Value(now),
      ),
    );

    await _enqueueFullRow(id, 'insert');
    return id;
  }

  /// Update an existing car.
  ///
  /// Fields wrapped in [Value.absent] are left unchanged; fields set to
  /// `Value(null)` are cleared locally and remotely.
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
        year: data.year.present ? data.year : Value(existing.year),
        carClass:
            data.carClass.present ? data.carClass : Value(existing.carClass),
        colour: data.colour.present ? data.colour : Value(existing.colour),
        imageUrl:
            data.imageUrl.present ? data.imageUrl : Value(existing.imageUrl),
        powerHp:
            data.powerHp.present ? data.powerHp : Value(existing.powerHp),
        weightKg:
            data.weightKg.present ? data.weightKg : Value(existing.weightKg),
        drivetrain: data.drivetrain.present
            ? data.drivetrain
            : Value(existing.drivetrain),
        engineCapacity: data.engineCapacity.present
            ? data.engineCapacity
            : Value(existing.engineCapacity),
        modifications: data.modifications.present
            ? data.modifications
            : Value(existing.modifications),
        tyreSetup:
            data.tyreSetup.present ? data.tyreSetup : Value(existing.tyreSetup),
        createdAt: Value(existing.createdAt),
      ),
    );

    await _enqueueFullRow(carId, 'update');
  }

  /// Enqueue the FULL row (read back from Drift) for sync. The sync engine
  /// executes inserts/updates as upserts, so partial payloads would
  /// violate NOT NULL constraints or silently drop cleared fields.
  Future<void> _enqueueFullRow(String carId, String operation) async {
    final row = await getCar(carId);
    if (row == null) return;

    await _db.enqueueSync(
      targetTable: 'cars',
      operation: operation,
      recordId: carId,
      payloadJson: jsonEncode({
        ...SyncPayloads.car(row),
        'created_at': row.createdAt.toIso8601String(),
      }),
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

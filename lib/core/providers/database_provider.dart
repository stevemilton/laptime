import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';

/// Singleton provider for the local Drift database.
/// Used throughout the app for all offline-first data access.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

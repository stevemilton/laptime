import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import 'profile_repository.dart';

/// Provides a singleton ProfileRepository instance.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ProfileRepository(db);
});

/// Profile provider - watches the current user's profile.
final profileProvider = StreamProvider<LocalProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(db.localProfiles)
        ..where((t) => t.id.equals(user.id)))
      .watchSingleOrNull();
});

/// Stats provider
final profileStatsProvider = FutureProvider<ProfileStats>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return ProfileStats(
      sessionCount: 0,
      circuitCount: 0,
      lapCount: 0,
      p1Count: 0,
    );
  }
  final repo = ref.read(profileRepositoryProvider);
  return repo.getStats(user.id);
});

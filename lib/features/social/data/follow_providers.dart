import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import 'follow_repository.dart';

/// Provides a singleton FollowRepository instance.
final followRepositoryProvider = Provider<FollowRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(supabaseClientProvider);
  return FollowRepository(db, client);
});

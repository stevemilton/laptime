import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import 'feed_repository.dart';

/// Number of feed items fetched per page.
const feedPageSize = 20;

/// Provides a singleton FeedRepository instance.
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(supabaseClientProvider);
  return FeedRepository(db, client);
});

/// Teams feed - sessions from team members. One provider instance per
/// zero-based page index; the feed screen appends pages as the user scrolls.
final teamsFeedProvider =
    FutureProvider.family<List<FeedItem>, int>((ref, page) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.read(feedRepositoryProvider);
  return repo.getTeamsFeed(
    userId: user.id,
    limit: feedPageSize,
    offset: page * feedPageSize,
  );
});

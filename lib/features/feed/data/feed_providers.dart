import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/supabase_provider.dart';
import 'feed_repository.dart';

/// Provides a singleton FeedRepository instance.
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return FeedRepository(client);
});

/// Teams feed - sessions from team members.
final teamsFeedProvider = FutureProvider<List<FeedItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.read(feedRepositoryProvider);
  return repo.getTeamsFeed(userId: user.id);
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/p1_badge.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/utils/format_utils.dart';
import '../data/feed_repository.dart';
import '../../social/data/team_providers.dart';

/// Feed provider for the "Following" tab.
final followingFeedProvider = FutureProvider<List<FeedItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final client = ref.read(supabaseClientProvider);
  final repo = FeedRepository(client);
  return repo.getFollowingFeed(userId: user.id);
});

/// Feed provider for the "Nearby" tab.
final nearbyFeedProvider = FutureProvider<List<FeedItem>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  final repo = FeedRepository(client);
  return repo.getNearbyFeed();
});

/// Feed tab screen with Following/Nearby/Teams tabs.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Feed', style: AppTypography.headlineLarge),
                IconButton(
                  onPressed: () => context.push('/following'),
                  icon: const Icon(
                    LucideIcons.userPlus,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ),
          ),

          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: AppColors.purple,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.purple,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Following'),
              Tab(text: 'Nearby'),
              Tab(text: 'Teams'),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _FeedList(feedProvider: followingFeedProvider),
                _FeedList(feedProvider: nearbyFeedProvider),
                const _TeamsFeedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedList extends ConsumerWidget {
  const _FeedList({required this.feedProvider});

  final FutureProvider<List<FeedItem>> feedProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);

    return feedAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: LucideIcons.rss,
            title: 'No sessions yet',
            subtitle: 'Follow other drivers to see their sessions here.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _FeedCard(item: items[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error loading feed: $e'),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User row
          Row(
            children: [
              AppAvatar(
                imageUrl: item.avatarUrl,
                initials: item.displayName.isNotEmpty
                    ? item.displayName[0].toUpperCase()
                    : null,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.circuitName != null)
                      Text(
                        item.circuitName!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              if (item.isPersonalBest == true) const P1Badge(),
            ],
          ),

          const SizedBox(height: 12),

          // Lap time + stats
          Row(
            children: [
              if (item.bestLapMs != null)
                Text(
                  FormatUtils.formatLapTime(item.bestLapMs!),
                  style: AppTypography.lapTime.copyWith(fontSize: 28),
                ),
              const Spacer(),
              if (item.lapCount != null)
                _StatPill(label: '${item.lapCount} laps'),
              if (item.carMake != null) ...[
                const SizedBox(width: 6),
                _StatPill(label: '${item.carMake} ${item.carModel ?? ""}'),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Action pills
          Row(
            children: [
              AppPill.outlined(
                label: 'Sectors',
                icon: LucideIcons.flag,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              AppPill.outlined(
                label: 'Nice',
                icon: LucideIcons.thumbsUp,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              AppPill.outlined(
                label: 'Comment',
                icon: LucideIcons.messageCircle,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ghost,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.textTertiary,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TeamsFeedTab extends ConsumerWidget {
  const _TeamsFeedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const EmptyState(
        icon: LucideIcons.users,
        title: 'Sign in to see team sessions',
      );
    }

    final teamsAsync = ref.watch(userTeamsProvider);

    return teamsAsync.when(
      data: (teams) {
        if (teams.isEmpty) {
          return EmptyState(
            icon: LucideIcons.users,
            title: 'No teams yet',
            subtitle: 'Find or create a team to see shared sessions here.',
            actionLabel: 'Find a Team',
            onAction: () => context.push('/team-search'),
          );
        }

        // Has teams — show their feed
        final feedAsync = ref.watch(teamsFeedProvider);
        return feedAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.rss,
                title: 'No team sessions yet',
                subtitle:
                    'Sessions from your teammates will appear here.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _FeedCard(item: items[index]),
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

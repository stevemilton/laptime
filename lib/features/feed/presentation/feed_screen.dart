import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/p1_badge.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/feed_repository.dart';
import '../data/feed_providers.dart';
import '../data/like_repository.dart';
import '../../social/data/team_providers.dart';
import 'comment_sheet.dart';
import 'sector_sheet.dart';

/// Feed provider for the "Following" tab.
final followingFeedProvider = FutureProvider<List<FeedItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.read(feedRepositoryProvider);
  return repo.getFollowingFeed(userId: user.id);
});

/// Feed provider for the "Nearby" tab.
final nearbyFeedProvider = FutureProvider<List<FeedItem>>((ref) async {
  final repo = ref.read(feedRepositoryProvider);
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
            subtitle:
                'Record a session or follow other drivers to build your feed.',
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

class _FeedCard extends ConsumerWidget {
  const _FeedCard({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => context.push('/session/${item.sessionId}'),
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
                    Row(
                      children: [
                        if (item.circuitName != null) ...[
                          Flexible(
                            child: Text(
                              item.circuitName!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            ' \u00B7 ',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                        Text(
                          FormatUtils.formatRelativeDate(item.startedAt),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
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
                onTap: item.circuitId != null
                    ? () => showSectorSheet(context, ref, item)
                    : null,
              ),
              const SizedBox(width: 8),
              _LikePill(item: item),
              const SizedBox(width: 8),
              AppPill.outlined(
                label: item.commentCount > 0
                    ? 'Comment (${item.commentCount})'
                    : 'Comment',
                icon: LucideIcons.messageCircle,
                onTap: () => showCommentSheet(context, ref, item.sessionId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LikePill extends ConsumerStatefulWidget {
  const _LikePill({required this.item});

  final FeedItem item;

  @override
  ConsumerState<_LikePill> createState() => _LikePillState();
}

class _LikePillState extends ConsumerState<_LikePill> {
  late bool _isLiked;
  late int _likeCount;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.item.isLikedByMe;
    _likeCount = widget.item.likeCount;
  }

  @override
  void didUpdateWidget(covariant _LikePill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.sessionId != widget.item.sessionId) {
      _isLiked = widget.item.isLikedByMe;
      _likeCount = widget.item.likeCount;
    }
  }

  Future<void> _toggle() async {
    if (_toggling) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Optimistic update
    setState(() {
      _toggling = true;
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });

    try {
      final repo = LikeRepository(ref.read(databaseProvider));
      await repo.toggleLike(widget.item.sessionId, user.id);

      // Invalidate feed providers to refresh counts on next load
      ref.invalidate(followingFeedProvider);
      ref.invalidate(nearbyFeedProvider);
    } catch (_) {
      // Revert on error
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? 1 : -1;
        });
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _likeCount > 0 ? 'Nice ($_likeCount)' : 'Nice';

    return AppPill(
      label: label,
      icon: LucideIcons.thumbsUp,
      onTap: _toggle,
      backgroundColor: _isLiked ? AppColors.purplePale : AppColors.white,
      foregroundColor: _isLiked ? AppColors.purple : AppColors.textSecondary,
      borderColor: _isLiked ? AppColors.purpleBright : AppColors.border,
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
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _FeedCard(item: items[index]),
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (_, __) => const EmptyState(
            icon: LucideIcons.alertCircle,
            title: 'Something went wrong',
            subtitle: 'Could not load team feed. Pull to refresh.',
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: LucideIcons.alertCircle,
        title: 'Something went wrong',
        subtitle: 'Could not load teams. Pull to refresh.',
      ),
    );
  }
}

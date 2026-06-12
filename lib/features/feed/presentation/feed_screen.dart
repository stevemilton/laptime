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

/// Feed provider for the "Following" tab, one instance per page index.
final followingFeedProvider =
    FutureProvider.family<List<FeedItem>, int>((ref, page) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.read(feedRepositoryProvider);
  return repo.getFollowingFeed(
    userId: user.id,
    limit: feedPageSize,
    offset: page * feedPageSize,
  );
});

/// Feed provider for the "Nearby" tab, one instance per page index.
final nearbyFeedProvider =
    FutureProvider.family<List<FeedItem>, int>((ref, page) async {
  final repo = ref.read(feedRepositoryProvider);
  return repo.getNearbyFeed(
    limit: feedPageSize,
    offset: page * feedPageSize,
  );
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

/// Paginated, pull-to-refresh feed list. Watches one provider per page and
/// appends pages as the user scrolls near the bottom.
class _FeedList extends ConsumerStatefulWidget {
  const _FeedList({
    required this.feedProvider,
    this.emptyTitle = 'No sessions yet',
    this.emptySubtitle =
        'Record a session or follow other drivers to build your feed.',
  });

  final FutureProviderFamily<List<FeedItem>, int> feedProvider;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  ConsumerState<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends ConsumerState<_FeedList> {
  int _pageCount = 1;

  Future<void> _refresh() async {
    setState(() => _pageCount = 1);
    ref.invalidate(widget.feedProvider);
    // Surface refresh errors via the provider state, not the indicator.
    try {
      await ref.read(widget.feedProvider(0).future);
    } catch (_) {}
  }

  void _loadMore(int fromPageCount) {
    // Ignore duplicate notifications fired before the rebuild lands.
    if (_pageCount != fromPageCount) return;
    setState(() => _pageCount = fromPageCount + 1);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (var page = 0; page < _pageCount; page++)
        ref.watch(widget.feedProvider(page)),
    ];

    final first = pages.first;
    if (first.isLoading && !first.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (first.hasError && !first.hasValue) {
      return EmptyState(
        icon: LucideIcons.wifiOff,
        title: 'Could not load feed',
        subtitle: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: _refresh,
      );
    }

    final items = <FeedItem>[
      for (final page in pages) ...page.valueOrNull ?? const [],
    ];

    final lastPage = pages.last;
    final loadingMore = _pageCount > 1 && lastPage.isLoading;
    final hasMore = !lastPage.isLoading &&
        (lastPage.valueOrNull?.length ?? 0) >= feedPageSize;
    final builtPageCount = _pageCount;

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: LucideIcons.rss,
              title: widget.emptyTitle,
              subtitle: widget.emptySubtitle,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (hasMore &&
              !loadingMore &&
              notification.metrics.extentAfter < 400) {
            _loadMore(builtPageCount);
          }
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: items.length + (loadingMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              // Loading footer while the next page is fetched.
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _FeedCard(item: items[index]);
          },
        ),
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

/// Optimistic like state keyed by session id. Lives outside the widget so
/// it survives ListView recycling — the cached FeedItem keeps its
/// pre-toggle counts until the next refetch, and a recycled pill must not
/// visually revert a like the user already made.
final _likeOverridesProvider =
    StateProvider<Map<String, ({bool isLiked, int likeCount})>>((ref) => {});

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
    _syncFromSource();
  }

  @override
  void didUpdateWidget(covariant _LikePill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.sessionId != widget.item.sessionId) {
      _syncFromSource();
    }
  }

  void _syncFromSource() {
    final override =
        ref.read(_likeOverridesProvider)[widget.item.sessionId];
    _isLiked = override?.isLiked ?? widget.item.isLikedByMe;
    _likeCount = override?.likeCount ?? widget.item.likeCount;
  }

  void _storeOverride() {
    ref.read(_likeOverridesProvider.notifier).update((overrides) => {
          ...overrides,
          widget.item.sessionId: (isLiked: _isLiked, likeCount: _likeCount),
        });
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
    _storeOverride();

    try {
      final repo = LikeRepository(ref.read(databaseProvider));
      await repo.toggleLike(widget.item.sessionId, user.id);
      // No feed invalidation: the pill already updated optimistically and
      // a refetch would race the sync queue (and reset pagination).
    } catch (_) {
      // Revert on error
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? 1 : -1;
        });
        _storeOverride();
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

        // Has teams — show their paginated feed
        return _FeedList(
          feedProvider: teamsFeedProvider,
          emptyTitle: 'No team sessions yet',
          emptySubtitle: 'Sessions from your teammates will appear here.',
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

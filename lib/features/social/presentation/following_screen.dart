import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/follow_repository.dart';
import '../data/follow_providers.dart';

/// Screen for searching drivers and managing follows.
class FollowingScreen extends ConsumerStatefulWidget {
  const FollowingScreen({super.key});

  @override
  ConsumerState<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends ConsumerState<FollowingScreen> {
  final _searchController = TextEditingController();
  List<UserSearchResult> _searchResults = [];
  bool _isSearching = false;
  final Set<String> _followedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);

    final repo = ref.read(followRepositoryProvider);
    final results = await repo.searchUsers(query);

    // Check follow status for results
    final user = ref.read(currentUserProvider);
    if (user != null) {
      for (final result in results) {
        final isFollowing = await repo.isFollowing(
          followerId: user.id,
          followingId: result.id,
        );
        if (isFollowing) _followedIds.add(result.id);
      }
    }

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _toggleFollow(String targetId) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final repo = ref.read(followRepositoryProvider);

    final isCurrentlyFollowing = _followedIds.contains(targetId);

    try {
      if (isCurrentlyFollowing) {
        await repo.unfollow(followerId: user.id, followingId: targetId);
        setState(() => _followedIds.remove(targetId));
      } else {
        await repo.follow(followerId: user.id, followingId: targetId);
        setState(() => _followedIds.add(targetId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Find Drivers'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or handle...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.ghost,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _search,
            ),
          ),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? _searchController.text.isEmpty
                        ? const EmptyState(
                            icon: LucideIcons.search,
                            title: 'Search for drivers',
                            subtitle:
                                'Find other drivers by name or handle to follow their sessions.',
                          )
                        : const EmptyState(
                            icon: LucideIcons.userX,
                            title: 'No results',
                            subtitle: 'Try a different search term.',
                          )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final isFollowing =
                              _followedIds.contains(user.id);

                          return _UserTile(
                            user: user,
                            isFollowing: isFollowing,
                            onToggleFollow: () => _toggleFollow(user.id),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isFollowing,
    required this.onToggleFollow,
  });

  final UserSearchResult user;
  final bool isFollowing;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: AppAvatar(
        imageUrl: user.avatarUrl,
        initials: user.displayName.isNotEmpty
            ? user.displayName[0].toUpperCase()
            : null,
        size: 44,
      ),
      title: Text(
        user.displayName,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: user.handle != null
          ? Text(
              '@${user.handle}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            )
          : null,
      trailing: SizedBox(
        width: 100,
        height: 34,
        child: isFollowing
            ? OutlinedButton(
                onPressed: onToggleFollow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: EdgeInsets.zero,
                  textStyle: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Following'),
              )
            : FilledButton(
                onPressed: onToggleFollow,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  padding: EdgeInsets.zero,
                  textStyle: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
                child: const Text('Follow'),
              ),
      ),
    );
  }
}

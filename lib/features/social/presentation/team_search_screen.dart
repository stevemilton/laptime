import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/constants/role_constants.dart';
import '../data/team_providers.dart';
import '../data/team_repository.dart';

class TeamSearchScreen extends ConsumerStatefulWidget {
  const TeamSearchScreen({super.key});

  @override
  ConsumerState<TeamSearchScreen> createState() => _TeamSearchScreenState();
}

class _TeamSearchScreenState extends ConsumerState<TeamSearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  final _codeController = TextEditingController();
  String _searchQuery = '';
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinByCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isJoining = true);

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.joinTeamByCode(code: code, userId: user.id);

      ref.invalidate(userTeamsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined team successfully')),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('[TeamSearch] Failed to join by code: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not join team. Please check the code and try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showRequestDialog(TeamSearchResult team) {
    final messageController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Request to join ${team.name}',
                style: AppTypography.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'Introduce yourself to the team admins',
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final user = ref.read(currentUserProvider);
                if (user == null) return;

                try {
                  final repo = ref.read(teamRepositoryProvider);
                  await repo.submitJoinRequest(
                    teamId: team.id,
                    userId: user.id,
                    message: messageController.text.trim().isEmpty
                        ? null
                        : messageController.text.trim(),
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Join request sent to team admins')),
                    );
                    // Refresh search to show updated status
                    setState(() {
                      _searchQuery = _searchController.text.trim();
                    });
                  }
                } catch (e) {
                  debugPrint('[TeamSearch] Failed to send join request: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not send join request. Please try again.'),
                        backgroundColor: AppColors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Send Request'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Find Teams'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.purple,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.purple,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Search'),
              Tab(text: 'Join by Code'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSearchTab(),
                _buildCodeTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search teams by name or location',
              prefixIcon: const Icon(LucideIcons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              if (value.trim().length >= 2 || value.isEmpty) {
                setState(() => _searchQuery = value.trim());
              }
            },
          ),
        ),
        Expanded(
          child: _searchQuery.length < 2
              ? const EmptyState(
                  icon: LucideIcons.search,
                  title: 'Search for teams',
                  subtitle: 'Enter at least 2 characters to search.',
                )
              : _SearchResults(
                  query: _searchQuery,
                  onRequestJoin: _showRequestDialog,
                ),
        ),
      ],
    );
  }

  Widget _buildCodeTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.keyRound, size: 48, color: AppColors.purple),
          const SizedBox(height: 16),
          Text('Enter Team Code', style: AppTypography.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Ask a team admin for their 8-character invite code.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Invite Code',
              hintText: 'e.g. A1B2C3D4',
            ),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isJoining ? null : _joinByCode,
              icon: _isJoining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(LucideIcons.logIn),
              label: const Text('Join Team'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.onRequestJoin,
  });

  final String query;
  final void Function(TeamSearchResult) onRequestJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(teamSearchProvider(query));

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.searchX,
            title: 'No teams found',
            subtitle: 'Try a different search term.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final team = results[index];
            return AppCard(
              child: Row(
                children: [
                  AppAvatar(
                    imageUrl: team.logoUrl,
                    initials: team.name.isNotEmpty
                        ? team.name[0].toUpperCase()
                        : null,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                team.name,
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (team.verified) ...[
                              const SizedBox(width: 4),
                              const Icon(LucideIcons.badgeCheck,
                                  size: 16, color: AppColors.purple),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '${team.memberCount} members',
                            if (team.location != null) team.location,
                          ].join(' \u00B7 '),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildAction(team),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const EmptyState(
        icon: LucideIcons.alertCircle,
        title: 'Search failed',
        subtitle: 'Could not search teams. Please try again.',
      ),
    );
  }

  Widget _buildAction(TeamSearchResult team) {
    if (team.membershipStatus == MembershipStatus.member) {
      return AppPill.filled(
        label: 'Member',
        backgroundColor: AppColors.green,
      );
    }
    if (team.membershipStatus == MembershipStatus.pending) {
      return AppPill.ghost(label: 'Pending');
    }
    return AppPill.outlined(
      label: 'Request',
      icon: LucideIcons.userPlus,
      onTap: () => onRequestJoin(team),
    );
  }
}

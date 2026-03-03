import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/team_providers.dart';
import '../data/team_repository.dart';
import '../data/crew_repository.dart';

class TeamDetailScreen extends ConsumerStatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends ConsumerState<TeamDetailScreen> {
  bool get _isAdmin {
    final roleAsync = ref.watch(userRoleProvider(widget.teamId));
    return roleAsync.valueOrNull == 'admin';
  }

  void _invalidateAll() {
    ref.invalidate(teamDetailProvider(widget.teamId));
    ref.invalidate(teamMembersProvider(widget.teamId));
    ref.invalidate(teamCrewsProvider(widget.teamId));
    ref.invalidate(pendingRequestsProvider(widget.teamId));
    ref.invalidate(userTeamsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(teamDetailProvider(widget.teamId));
    final membersAsync = ref.watch(teamMembersProvider(widget.teamId));
    final crewsAsync = ref.watch(teamCrewsProvider(widget.teamId));

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: teamAsync.whenOrNull(data: (t) => Text(t?.name ?? 'Team')),
        actions: [
          if (_isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (value) => _handleMenuAction(value),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit Team'),
                ),
                const PopupMenuItem(
                  value: 'regenerate',
                  child: Text('Regenerate Invite Code'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Team'),
                ),
              ],
            ),
        ],
      ),
      body: teamAsync.when(
        data: (team) {
          if (team == null) {
            return const EmptyState(
              icon: LucideIcons.alertCircle,
              title: 'Team not found',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _invalidateAll(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(team),
                const SizedBox(height: 20),
                _buildInviteCodeSection(team),
                const SizedBox(height: 20),
                _buildRoleSection(team),
                if (_isAdmin) ...[
                  const SizedBox(height: 20),
                  _buildAdminActions(),
                ],
                const SizedBox(height: 24),
                _buildCrewsSection(crewsAsync),
                const SizedBox(height: 24),
                _buildMembersSection(membersAsync, team),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildHeader(TeamInfo team) {
    return Column(
      children: [
        AppAvatar.large(
          imageUrl: team.logoUrl,
          initials: team.name.isNotEmpty ? team.name[0].toUpperCase() : null,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                team.name,
                style: AppTypography.headlineMedium,
                textAlign: TextAlign.center,
              ),
            ),
            if (team.verified) ...[
              const SizedBox(width: 6),
              const Icon(LucideIcons.badgeCheck,
                  size: 20, color: AppColors.purple),
            ],
          ],
        ),
        if (team.location != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.mapPin,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                team.location!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${team.memberCount} member${team.memberCount == 1 ? '' : 's'}',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteCodeSection(TeamInfo team) {
    if (team.currentUserRole != 'admin') return const SizedBox.shrink();

    return AppCard(
      child: Row(
        children: [
          const Icon(LucideIcons.keyRound, size: 20, color: AppColors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite Code',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  team.code,
                  style: AppTypography.headlineSmall.copyWith(
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: team.code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSection(TeamInfo team) {
    return AppCard(
      child: Row(
        children: [
          const Icon(LucideIcons.shield, size: 20, color: AppColors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Role',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                AppPill.filled(
                  label: team.currentUserRole == 'admin' ? 'Admin' : 'Member',
                  backgroundColor: team.currentUserRole == 'admin'
                      ? AppColors.purple
                      : AppColors.textTertiary,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _leaveTeam(team),
            icon: const Icon(LucideIcons.logOut, size: 16),
            label: const Text('Leave'),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminActions() {
    final pendingAsync = ref.watch(pendingRequestsProvider(widget.teamId));
    final pendingCount = pendingAsync.valueOrNull?.length ?? 0;

    return AppCard(
      onTap: () => context.push('/team/${widget.teamId}/requests'),
      child: Row(
        children: [
          const Icon(LucideIcons.inbox, size: 20, color: AppColors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Join Requests',
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pendingCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '$pendingCount',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          const Icon(LucideIcons.chevronRight,
              size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildCrewsSection(AsyncValue<List<CrewInfo>> crewsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Crews', style: AppTypography.headlineSmall),
            if (_isAdmin)
              IconButton(
                icon: const Icon(LucideIcons.plus, size: 20),
                onPressed: _showCreateCrewDialog,
              ),
          ],
        ),
        const SizedBox(height: 8),
        crewsAsync.when(
          data: (crews) {
            if (crews.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _isAdmin
                      ? 'No crews yet. Tap + to create one.'
                      : 'No crews yet.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              );
            }

            return Column(
              children: crews
                  .map((crew) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CrewCard(
                          crew: crew,
                          teamId: widget.teamId,
                          onChanged: _invalidateAll,
                        ),
                      ))
                  .toList(),
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  Widget _buildMembersSection(
    AsyncValue<List<TeamMemberInfo>> membersAsync,
    TeamInfo team,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Members', style: AppTypography.headlineSmall),
        const SizedBox(height: 8),
        membersAsync.when(
          data: (members) {
            return Column(
              children: members
                  .map((m) => _MemberTile(
                        member: m,
                        isCurrentUserAdmin: _isAdmin,
                        currentUserId:
                            ref.read(currentUserProvider)?.id ?? '',
                        onChanged: _invalidateAll,
                        teamId: widget.teamId,
                      ))
                  .toList(),
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  // ── Actions ──

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'edit':
        _showEditTeamDialog();
      case 'regenerate':
        _regenerateCode();
      case 'delete':
        _deleteTeam();
    }
  }

  void _showEditTeamDialog() {
    final teamAsync = ref.read(teamDetailProvider(widget.teamId));
    final team = teamAsync.valueOrNull;
    if (team == null) return;

    final nameController = TextEditingController(text: team.name);
    final locationController = TextEditingController(text: team.location ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Team Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Location'),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final repo = ref.read(teamRepositoryProvider);
                await repo.updateTeam(
                  teamId: widget.teamId,
                  name: nameController.text.trim(),
                  location: locationController.text.trim().isEmpty
                      ? null
                      : locationController.text.trim(),
                );
                _invalidateAll();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('$e'), backgroundColor: AppColors.red),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _regenerateCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate Invite Code?'),
        content: const Text(
            'The old code will no longer work. Share the new code with your team.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      final newCode = await repo.regenerateInviteCode(widget.teamId);
      _invalidateAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New invite code: $newCode')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _deleteTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Team?'),
        content: const Text(
            'This will permanently delete the team, all crews, and all memberships. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.deleteTeam(widget.teamId);
      ref.invalidate(userTeamsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _leaveTeam(TeamInfo team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Team?'),
        content:
            Text('Are you sure you want to leave ${team.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.leaveTeam(teamId: widget.teamId, userId: user.id);
      ref.invalidate(userTeamsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _showCreateCrewDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Crew'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Crew Name',
            hintText: 'e.g. GT3 Class',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              try {
                final repo = ref.read(crewRepositoryProvider);
                await repo.createCrew(
                  teamId: widget.teamId,
                  name: name,
                );
                _invalidateAll();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Crew "$name" created')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('$e'), backgroundColor: AppColors.red),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ── Crew Card ──

class _CrewCard extends ConsumerWidget {
  const _CrewCard({
    required this.crew,
    required this.teamId,
    required this.onChanged,
  });

  final CrewInfo crew;
  final String teamId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => context.push('/crew/${crew.id}'),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.purplePale,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              LucideIcons.users,
              size: 20,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  crew.name,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (crew.isCurrentUserMember)
            AppPill.ghost(label: 'Joined')
          else
            AppPill.outlined(
              label: 'Join',
              icon: LucideIcons.plus,
              onTap: () async {
                final user = ref.read(currentUserProvider);
                if (user == null) return;
                try {
                  final repo = ref.read(crewRepositoryProvider);
                  await repo.joinCrew(
                      crewId: crew.id, userId: user.id);
                  onChanged();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('$e'),
                          backgroundColor: AppColors.red),
                    );
                  }
                }
              },
            ),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevronRight,
              size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

// ── Member Tile ──

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.isCurrentUserAdmin,
    required this.currentUserId,
    required this.onChanged,
    required this.teamId,
  });

  final TeamMemberInfo member;
  final bool isCurrentUserAdmin;
  final String currentUserId;
  final VoidCallback onChanged;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = member.userId == currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          AppAvatar(
            imageUrl: member.avatarUrl,
            initials: member.displayName.isNotEmpty
                ? member.displayName[0].toUpperCase()
                : null,
            size: 40,
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
                        member.displayName,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe)
                      Text(
                        ' (you)',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
                if (member.handle != null)
                  Text(
                    '@${member.handle}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          AppPill.filled(
            label: member.role == 'admin' ? 'Admin' : 'Member',
            backgroundColor: member.role == 'admin'
                ? AppColors.purple
                : AppColors.textTertiary,
          ),
          if (isCurrentUserAdmin && !isMe)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical,
                  size: 18, color: AppColors.textTertiary),
              onSelected: (action) =>
                  _handleMemberAction(context, ref, action),
              itemBuilder: (_) => [
                if (member.role == 'member')
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('Promote to Admin'),
                  ),
                if (member.role == 'admin')
                  const PopupMenuItem(
                    value: 'demote',
                    child: Text('Demote to Member'),
                  ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from Team'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _handleMemberAction(
      BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(teamRepositoryProvider);

    try {
      switch (action) {
        case 'promote':
          await repo.promoteToAdmin(
              teamId: teamId, userId: member.userId);
        case 'demote':
          await repo.demoteToMember(
              teamId: teamId, userId: member.userId);
        case 'remove':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Remove Member?'),
              content: Text(
                  'Remove ${member.displayName} from the team?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          await repo.removeMember(
            teamId: teamId,
            userId: member.userId,
            removedByUserId: currentUserId,
          );
      }
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/constants/role_constants.dart';
import '../data/team_providers.dart';
import '../data/crew_repository.dart';

class CrewDetailScreen extends ConsumerWidget {
  const CrewDetailScreen({super.key, required this.crewId});

  final String crewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crewAsync = ref.watch(crewDetailProvider(crewId));
    final membersAsync = ref.watch(crewMembersProvider(crewId));

    return crewAsync.when(
      loading: () => Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: const EmptyState(
          icon: LucideIcons.alertCircle,
          title: 'Something went wrong',
          subtitle: 'Could not load crew details.',
        ),
      ),
      data: (crew) => crew == null
          ? Scaffold(
              backgroundColor: AppColors.white,
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const EmptyState(
                icon: LucideIcons.alertCircle,
                title: 'Crew not found',
              ),
            )
          : _CrewDetailBody(
              crewId: crewId,
              crew: crew,
              membersAsync: membersAsync,
            ),
    );
  }
}

class _CrewDetailBody extends ConsumerWidget {
  const _CrewDetailBody({
    required this.crewId,
    required this.crew,
    required this.membersAsync,
  });

  final String crewId;
  final CrewInfo crew;
  final AsyncValue<List<CrewMemberInfo>> membersAsync;

  bool _isTeamAdmin(WidgetRef ref) {
    final roleAsync = ref.watch(userRoleProvider(crew.teamId));
    return roleAsync.valueOrNull == TeamRole.admin;
  }

  void _invalidateAll(WidgetRef ref) {
    ref.invalidate(crewDetailProvider(crewId));
    ref.invalidate(crewMembersProvider(crewId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = _isTeamAdmin(ref);
    final members = membersAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(crew.name),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (action) {
                if (action == 'delete') _deleteCrew(context, ref);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Crew'),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _invalidateAll(ref),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.purplePale,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    child: Icon(
                      LucideIcons.users,
                      size: 28,
                      color: AppColors.purple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(crew.name, style: AppTypography.headlineMedium),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => context.push('/team/${crew.teamId}'),
                    child: Text(
                      'View Team',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.purple,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Invite code
            AppCard(
              child: Row(
                children: [
                  const Icon(LucideIcons.keyRound,
                      size: 20, color: AppColors.purple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crew Invite Code',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          crew.inviteCode,
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
                      Clipboard.setData(ClipboardData(text: crew.inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Crew code copied')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Join/Leave button
            if (crew.isCurrentUserMember)
              OutlinedButton.icon(
                onPressed: () => _leaveCrew(context, ref),
                icon: const Icon(LucideIcons.logOut, size: 16),
                label: const Text('Leave Crew'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                ),
              )
            else
              FilledButton.icon(
                onPressed: () => _joinCrew(context, ref),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Join Crew'),
              ),

            const SizedBox(height: 24),

            // Members
            Text('Members', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),

            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No members yet.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              )
            else
              ...members.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        AppAvatar(
                          imageUrl: m.avatarUrl,
                          initials: m.displayName.isNotEmpty
                              ? m.displayName[0].toUpperCase()
                              : null,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.displayName,
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (m.handle != null)
                                Text(
                                  '@${m.handle}',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        AppPill.filled(
                          label:
                              m.role == CrewRole.captain ? 'Captain' : 'Member',
                          backgroundColor: m.role == CrewRole.captain
                              ? AppColors.purple
                              : AppColors.textTertiary,
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  void _joinCrew(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(crewRepositoryProvider);
      await repo.joinCrew(crewId: crewId, userId: user.id);
      _invalidateAll(ref);
    } catch (e) {
      debugPrint('[CrewDetail] Failed to join crew: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join crew. Please try again.'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _leaveCrew(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(crewRepositoryProvider);
      await repo.leaveCrew(crewId: crewId, userId: user.id);
      _invalidateAll(ref);
    } catch (e) {
      debugPrint('[CrewDetail] Failed to leave crew: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not leave crew. Please try again.'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _deleteCrew(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Crew?'),
        content: const Text(
            'This will permanently delete this crew and remove all members.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(crewRepositoryProvider);
      await repo.deleteCrew(crewId);
      if (context.mounted) context.pop();
    } catch (e) {
      debugPrint('[CrewDetail] Failed to delete crew: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete crew. Please try again.'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}

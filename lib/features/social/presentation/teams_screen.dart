import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/constants/role_constants.dart';
import '../data/team_providers.dart';
import '../data/team_repository.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(userTeamsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Teams'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.search),
            onPressed: () => context.push('/team-search'),
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => context.push('/team/create'),
          ),
        ],
      ),
      body: teamsAsync.when(
        data: (teams) {
          if (teams.isEmpty) {
            return EmptyState(
              icon: LucideIcons.users,
              title: 'No teams yet',
              subtitle: 'Find a team to join or create your own racing team.',
              actionLabel: 'Find Teams',
              onAction: () => context.push('/team-search'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(userTeamsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: teams.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == teams.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/team-search'),
                      icon: const Icon(LucideIcons.userPlus, size: 18),
                      label: const Text('Find Teams'),
                    ),
                  );
                }

                return _TeamCard(team: teams[index]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: LucideIcons.alertCircle,
          title: 'Something went wrong',
          subtitle: 'Could not load teams. Pull to refresh.',
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team});

  final TeamInfo team;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push('/team/${team.id}'),
      child: Row(
        children: [
          AppAvatar(
            imageUrl: team.logoUrl,
            initials: team.name.isNotEmpty ? team.name[0].toUpperCase() : null,
            size: 48,
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
                Row(
                  children: [
                    Text(
                      '${team.memberCount} member${team.memberCount == 1 ? '' : 's'}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (team.location != null)
                      Flexible(
                        child: Text(
                          ' \u00B7 ${team.location}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (team.currentUserRole == TeamRole.admin) ...[
            AppPill.filled(label: 'Admin'),
            const SizedBox(width: 8),
          ],
          if (team.currentUserRole == TeamRole.admin &&
              team.pendingRequestCount > 0) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${team.pendingRequestCount}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          const Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

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
import '../data/team_providers.dart';
import '../data/crew_repository.dart';

class CrewDetailScreen extends ConsumerStatefulWidget {
  const CrewDetailScreen({super.key, required this.crewId});

  final String crewId;

  @override
  ConsumerState<CrewDetailScreen> createState() => _CrewDetailScreenState();
}

class _CrewDetailScreenState extends ConsumerState<CrewDetailScreen> {
  CrewInfo? _crew;
  List<CrewMemberInfo> _members = [];
  bool _isLoading = true;
  bool _isTeamAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final crewRepo = ref.read(crewRepositoryProvider);
    final crew = await crewRepo.getCrew(widget.crewId, currentUserId: user.id);

    if (crew != null) {
      final members = await crewRepo.getCrewMembers(widget.crewId);

      // Check if user is team admin
      final teamRepo = ref.read(teamRepositoryProvider);
      final role = await teamRepo.getUserRoleInTeam(crew.teamId, user.id);

      if (mounted) {
        setState(() {
          _crew = crew;
          _members = members;
          _isTeamAdmin = role == 'admin';
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_crew == null) {
      return Scaffold(
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
      );
    }

    final crew = _crew!;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(crew.name),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_isTeamAdmin)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: _handleMenuAction,
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
        onRefresh: _loadData,
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
                onPressed: _leaveCrew,
                icon: const Icon(LucideIcons.logOut, size: 16),
                label: const Text('Leave Crew'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _joinCrew,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Join Crew'),
              ),

            const SizedBox(height: 24),

            // Members
            Text('Members', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),

            if (_members.isEmpty)
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
              ..._members.map((m) => Padding(
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
                              m.role == 'captain' ? 'Captain' : 'Member',
                          backgroundColor: m.role == 'captain'
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

  void _handleMenuAction(String action) {
    if (action == 'delete') _deleteCrew();
  }

  void _joinCrew() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(crewRepositoryProvider);
      await repo.joinCrew(crewId: widget.crewId, userId: user.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _leaveCrew() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(crewRepositoryProvider);
      await repo.leaveCrew(crewId: widget.crewId, userId: user.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _deleteCrew() async {
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
      await repo.deleteCrew(widget.crewId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.red),
        );
      }
    }
  }
}

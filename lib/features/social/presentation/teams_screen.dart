import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/team_repository.dart';

/// Screen for managing teams (view, join, create).
class TeamsScreen extends ConsumerStatefulWidget {
  const TeamsScreen({super.key});

  @override
  ConsumerState<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends ConsumerState<TeamsScreen> {
  List<TeamInfo> _teams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final db = ref.read(databaseProvider);
    final client = ref.read(supabaseClientProvider);
    final repo = TeamRepository(db, client);
    final teams = await repo.getUserTeams(user.id);

    if (mounted) {
      setState(() {
        _teams = teams;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(LucideIcons.plus),
            onPressed: _showCreateTeamDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _teams.isEmpty
              ? EmptyState(
                  icon: LucideIcons.users,
                  title: 'No teams yet',
                  subtitle: 'Join a team with a code or create your own.',
                  actionLabel: 'Join Team',
                  onAction: _showJoinTeamDialog,
                )
              : RefreshIndicator(
                  onRefresh: _loadTeams,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _teams.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == _teams.length) {
                        // Join team button at end
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            onPressed: _showJoinTeamDialog,
                            icon: const Icon(LucideIcons.userPlus, size: 18),
                            label: const Text('Join a Team'),
                          ),
                        );
                      }

                      final team = _teams[index];
                      return _TeamCard(team: team);
                    },
                  ),
                ),
    );
  }

  void _showJoinTeamDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Team'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: 'Team Code',
            hintText: 'Enter the team code',
          ),
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;

              Navigator.pop(ctx);

              final user = ref.read(currentUserProvider);
              if (user == null) return;

              final db = ref.read(databaseProvider);
              final client = ref.read(supabaseClientProvider);
              final repo = TeamRepository(db, client);

              try {
                await repo.joinTeam(code: code, userId: user.id);
                _loadTeams();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Joined team successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showCreateTeamDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Team'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Team Name',
            hintText: 'e.g. Track Day Buddies',
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

              final user = ref.read(currentUserProvider);
              if (user == null) return;

              final db = ref.read(databaseProvider);
              final client = ref.read(supabaseClientProvider);
              final repo = TeamRepository(db, client);

              try {
                final team = await repo.createTeam(
                  name: name,
                  createdBy: user.id,
                );
                _loadTeams();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Team created! Code: ${team.code}'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.red,
                    ),
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

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team});

  final TeamInfo team;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.purplePale,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              LucideIcons.users,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${team.memberCount} member${team.memberCount == 1 ? '' : 's'} \u00B7 Code: ${team.code}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/providers/supabase_provider.dart';
import '../data/team_providers.dart';

class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(teamRepositoryProvider);
      final team = await repo.createTeam(
        name: _nameController.text.trim(),
        createdBy: user.id,
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
      );

      ref.invalidate(userTeamsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Team created! Invite code: ${team.code}'),
            duration: const Duration(seconds: 5),
          ),
        );
        context.pop();
        context.push('/team/${team.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not create team. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Create Team'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Start your racing team',
                style: AppTypography.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a team to track sessions together, compare laps, and compete on leaderboards.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 32),

              // Team Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Team Name',
                  hintText: 'e.g. Apex Racing',
                  prefixIcon: Icon(LucideIcons.users),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.length < 2) return 'Name must be at least 2 characters';
                  if (v.length > 100) return 'Name must be at most 100 characters';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Location
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  hintText: 'e.g. Melbourne, Australia',
                  prefixIcon: Icon(LucideIcons.mapPin),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value != null && value.length > 200) {
                    return 'Location must be at most 200 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // Submit
              FilledButton.icon(
                onPressed: _isLoading ? null : _submit,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(LucideIcons.plus),
                label: const Text('Create Team'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

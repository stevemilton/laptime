import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/team_providers.dart';
import '../data/team_repository.dart';

class TeamJoinRequestsScreen extends ConsumerWidget {
  const TeamJoinRequestsScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guard: only team admins can view join requests
    final roleAsync = ref.watch(userRoleProvider(teamId));
    final isAdmin = roleAsync.valueOrNull == TeamRole.admin;

    if (roleAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: const Text('Join Requests'),
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          title: const Text('Join Requests'),
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: const EmptyState(
          icon: LucideIcons.shieldOff,
          title: 'Admin access required',
          subtitle: 'Only team admins can manage join requests.',
        ),
      );
    }

    final requestsAsync = ref.watch(pendingRequestsProvider(teamId));

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Join Requests'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: requestsAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.inbox,
              title: 'No pending requests',
              subtitle: 'New join requests from drivers will appear here.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(pendingRequestsProvider(teamId)),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _RequestCard(
                  request: requests[index],
                  teamId: teamId,
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: LucideIcons.alertCircle,
          title: 'Something went wrong',
          subtitle: 'Could not load join requests. Pull to refresh.',
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request, required this.teamId});

  final JoinRequestInfo request;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeSince = _formatTimeSince(request.requestedAt);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User row
          Row(
            children: [
              AppAvatar(
                imageUrl: request.avatarUrl,
                initials: request.displayName.isNotEmpty
                    ? request.displayName[0].toUpperCase()
                    : null,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.displayName,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (request.handle != null)
                      Text(
                        '@${request.handle}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                timeSince,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),

          // Message
          if (request.message != null && request.message!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ghost,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                request.message!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _reject(context, ref),
                  icon: const Icon(LucideIcons.x, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _approve(context, ref),
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _approve(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.approveJoinRequest(
        requestId: request.id,
        reviewerId: user.id,
      );
      ref.invalidate(pendingRequestsProvider(teamId));
      ref.invalidate(teamMembersProvider(teamId));
      ref.invalidate(teamDetailProvider(teamId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${request.displayName} approved')),
        );
      }
    } catch (e) {
      debugPrint('[JoinRequests] Failed to approve request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not approve request. Please try again.'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  void _reject(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject ${request.displayName}?'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Let them know why',
          ),
          maxLines: 2,
          maxLength: 500,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (reason == null) return; // Cancelled

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repo = ref.read(teamRepositoryProvider);
      await repo.rejectJoinRequest(
        requestId: request.id,
        reviewerId: user.id,
        reason: reason.isEmpty ? null : reason,
      );
      ref.invalidate(pendingRequestsProvider(teamId));
      ref.invalidate(teamDetailProvider(teamId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${request.displayName} rejected')),
        );
      }
    } catch (e) {
      debugPrint('[JoinRequests] Failed to reject request: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reject request. Please try again.'), backgroundColor: AppColors.red),
        );
      }
    }
  }

  String _formatTimeSince(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

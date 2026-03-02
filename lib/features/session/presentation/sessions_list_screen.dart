import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/empty_state.dart';

/// Provider that streams all sessions for the current user.
final _allSessionsProvider = StreamProvider<List<LocalSession>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value([]);
  final db = ref.watch(databaseProvider);
  return db.watchUserSessions(user.id);
});

/// Best lap for a session in the list.
final _listBestLapProvider =
    FutureProvider.family<int?, String>((ref, sessionId) async {
  final db = ref.read(databaseProvider);
  final laps = await db.getSessionLaps(sessionId);
  if (laps.isEmpty) return null;
  return laps.map((l) => l.durationMs).reduce((a, b) => a < b ? a : b);
});

/// Full-screen list of all user sessions.
class SessionsListScreen extends ConsumerWidget {
  const SessionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(_allSessionsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        title: Text('All Sessions', style: AppTypography.headlineSmall),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: LucideIcons.timer,
                title: 'No sessions yet',
                subtitle: 'Record your first track session to see it here.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _SessionListTile(session: sessions[index]),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.purple),
        ),
        error: (e, _) => Center(
          child: EmptyState(
            icon: LucideIcons.alertCircle,
            title: 'Error loading sessions',
            subtitle: '$e',
          ),
        ),
      ),
    );
  }
}

class _SessionListTile extends ConsumerWidget {
  const _SessionListTile({required this.session});

  final LocalSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bestLapAsync = ref.watch(_listBestLapProvider(session.id));
    final bestLapMs = bestLapAsync.value;

    return GestureDetector(
      onTap: () => context.push('/session/${session.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Left: best lap + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bestLapMs != null)
                    Text(
                      FormatUtils.formatLapTime(bestLapMs),
                      style: AppTypography.headlineSmall.copyWith(
                        color: AppColors.green,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(session.startedAt),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Right: condition + chevron
            if (session.trackCondition != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.purplePale,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  session.trackCondition!,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.purple,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(LucideIcons.chevronRight,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

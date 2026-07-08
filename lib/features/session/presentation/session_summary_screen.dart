import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../data/session_repository.dart';

/// One-time prompt flag: shown after saving a session while the profile
/// is still the "Driver" default (or the garage is empty).
const _kProfileNudgeShownKey = 'profile_nudge_shown';

/// Post-recording summary screen.
///
/// Shows session duration, lap count, best lap time, and lets the driver
/// choose to save (→ edit screen) or discard the session.
class SessionSummaryScreen extends ConsumerStatefulWidget {
  const SessionSummaryScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionSummaryScreen> createState() =>
      _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends ConsumerState<SessionSummaryScreen> {
  LocalSession? _session;
  List<LocalLap> _laps = [];
  bool _isLoading = true;
  bool _isDiscarding = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final repo = ref.read(sessionRepositoryProvider);
    final session = await repo.getSession(widget.sessionId);
    final laps = await repo.getSessionLaps(widget.sessionId);

    if (!mounted) return;
    setState(() {
      _session = session;
      _laps = laps;
      _isLoading = false;
    });
  }

  int get _totalDurationMs {
    final session = _session;
    if (session == null || session.endedAt == null) return 0;
    return session.endedAt!.difference(session.startedAt).inMilliseconds;
  }

  int? get _bestLapMs {
    if (_laps.isEmpty) return null;
    return _laps.map((l) => l.durationMs).reduce((a, b) => a < b ? a : b);
  }

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Future<void> _onSave() async {
    final nudged = await _maybeShowProfileNudge();
    if (nudged || !mounted) return;
    context.go('/session/${widget.sessionId}/edit');
  }

  /// After a session is saved with a default profile, prompt once to set
  /// a name and add a car — the moment a driver has data worth attributing.
  /// Returns true when the user chose to go set up their profile.
  Future<bool> _maybeShowProfileNudge() async {
    final prefs = ref.read(sharedPrefsProvider).value;
    if (prefs == null || prefs.getBool(_kProfileNudgeShownKey) == true) {
      return false;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return false;

    final db = ref.read(databaseProvider);
    final profile = await db.getProfile(user.id);
    final hasName = profile != null &&
        profile.displayName.trim().isNotEmpty &&
        profile.displayName != 'Driver';
    final cars = await (db.select(db.localCars)
          ..where((t) => t.userId.equals(user.id))
          ..limit(1))
        .get();
    if (hasName && cars.isNotEmpty) return false;

    await prefs.setBool(_kProfileNudgeShownKey, true);
    if (!mounted) return false;
    final goToProfile = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nice driving — who was that?'),
        content: Text(
          !hasName
              ? 'Set your driver name so your laps show up as you on '
                  'leaderboards and the feed. You can add your car too.'
              : 'Add your car to the garage so sessions and leaderboard '
                  'times show what you were driving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(!hasName ? 'Set Up Profile' : 'Add Car'),
          ),
        ],
      ),
    );
    if (goToProfile == true && mounted) {
      context.go(!hasName ? '/edit-profile' : '/garage');
      return true;
    }
    return false;
  }

  Future<void> _onDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Session?'),
        content: const Text(
          'This will permanently delete this recording. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDiscarding = true);

    try {
      final repo = ref.read(sessionRepositoryProvider);
      await repo.discardSession(widget.sessionId);

      if (mounted) {
        context.go('/record');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDiscarding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to discard: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.purple),
                )
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Checkmark icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green.withValues(alpha: 0.12),
            ),
            child: const Icon(
              LucideIcons.checkCircle,
              size: 36,
              color: AppColors.green,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Session Complete',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 40),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                icon: LucideIcons.clock,
                label: 'Duration',
                value: _formatDuration(_totalDurationMs),
              ),
              _StatItem(
                icon: LucideIcons.flag,
                label: 'Laps',
                value: _laps.length.toString(),
              ),
              if (_bestLapMs != null)
                _StatItem(
                  icon: LucideIcons.trophy,
                  label: 'Best Lap',
                  value: FormatUtils.formatLapTime(_bestLapMs!),
                  valueColor: AppColors.green,
                ),
            ],
          ),

          // Lap list (if laps exist)
          if (_laps.isNotEmpty) ...[
            const SizedBox(height: 32),
            Expanded(
              child: _buildLapList(),
            ),
          ] else
            const Spacer(flex: 3),

          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _onSave,
              icon: const Icon(LucideIcons.save, size: 18),
              label: Text(
                'Save & Add Details',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Discard button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _isDiscarding ? null : _onDiscard,
              icon: _isDiscarding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.trash2, size: 18),
              label: Text(
                'Discard',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLapList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LAPS',
          style: AppTypography.sectionLabel,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _laps.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final lap = _laps[index];
              final isBest = lap.durationMs == _bestLapMs;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        'L${lap.lapNumber}',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        FormatUtils.formatLapTime(lap.durationMs),
                        style: AppTypography.headlineSmall.copyWith(
                          color: isBest
                              ? AppColors.green
                              : AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (isBest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          'BEST',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.purple),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTypography.headlineSmall.copyWith(
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

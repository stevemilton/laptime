import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/gps_indicator.dart';
import '../data/recording_repository.dart';
import 'recording_controller.dart';

/// Active recording screen shown during a session.
///
/// Displays: elapsed time, lap counter, GPS indicator, manual lap button,
/// and a FINISH button.
class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingAsync = ref.watch(recordingStateProvider);

    return recordingAsync.when(
      data: (state) => _RecordingView(state: state),
      loading: () => const _RecordingView(
        state: null,
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.white,
        body: Center(
          child: Text('Recording error: $e'),
        ),
      ),
    );
  }
}

class _RecordingView extends ConsumerWidget {
  const _RecordingView({required this.state});

  final RecordingState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elapsed = state?.elapsedMs ?? 0;
    final lapCount = state?.lapCount ?? 0;
    final currentLap = state?.currentLapMs ?? 0;
    final lastLap = state?.lastLapMs;
    final bestLap = state?.bestLapMs;
    final accuracy = state?.gpsAccuracy;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Top bar: GPS + Session info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GpsIndicator(
                    accuracy: accuracy,
                    isActive: state?.isRecording ?? false,
                  ),
                  // Recording indicator
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'RECORDING',
                        style: AppTypography.sectionLabel.copyWith(
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // Main elapsed time
              Text(
                _formatElapsedFull(elapsed),
                style: AppTypography.displayLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 72,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),

              const SizedBox(height: 8),

              // Lap counter
              Text(
                lapCount > 0 ? 'LAP $lapCount' : 'WAITING FOR FIRST LAP',
                style: AppTypography.sectionLabel.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),

              const SizedBox(height: 20),

              // Live GPS speed
              Builder(builder: (context) {
                final units = ref.watch(unitsProvider);
                final speedMps = state?.speedMps;
                final value = speedMps != null
                    ? FormatUtils.speedValue(speedMps, units: units)
                        .round()
                        .toString()
                    : '--';
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: AppTypography.displayLarge.copyWith(
                        color: AppColors.purple,
                        fontSize: 44,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      FormatUtils.speedUnit(units),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                );
              }),

              const SizedBox(height: 24),

              // Current lap time
              if (lapCount > 0 || currentLap > 0) ...[
                Text(
                  'Current Lap',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  FormatUtils.formatLapTime(currentLap),
                  style: AppTypography.lapTime.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Last + Best lap times
              if (lastLap != null || bestLap != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (lastLap != null) ...[
                      _LapInfo(
                        label: 'Last',
                        time: FormatUtils.formatLapTime(lastLap),
                      ),
                      if (bestLap != null) const SizedBox(width: 32),
                    ],
                    if (bestLap != null)
                      _LapInfo(
                        label: 'Best',
                        time: FormatUtils.formatLapTime(bestLap),
                        color: AppColors.green,
                      ),
                  ],
                ),

              const Spacer(flex: 3),

              // Manual lap button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(recordingControllerProvider.notifier).manualLapSplit();
                  },
                  icon: const Icon(LucideIcons.flag, size: 18),
                  label: const Text('Manual Lap'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    side: const BorderSide(color: AppColors.purple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // FINISH button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () async {
                    final sessionId = await ref
                        .read(recordingControllerProvider.notifier)
                        .stopSession();
                    if (context.mounted && sessionId != null) {
                      context.go('/session/$sessionId/edit');
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  child: Text(
                    'FINISH',
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatElapsedFull(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final tenths = (ms % 1000) ~/ 100;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$tenths';
  }
}

class _LapInfo extends StatelessWidget {
  const _LapInfo({
    required this.label,
    required this.time,
    this.color,
  });

  final String label;
  final String time;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: AppTypography.headlineSmall.copyWith(
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

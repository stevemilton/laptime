import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/format_utils.dart';

/// Displays a formatted lap time with optional delta and personal best indicator.
class LapTimeText extends StatelessWidget {
  const LapTimeText({
    super.key,
    required this.durationMs,
    this.deltaMs,
    this.isPersonalBest = false,
    this.style,
    this.deltaStyle,
  });

  final int durationMs;
  final int? deltaMs;
  final bool isPersonalBest;
  final TextStyle? style;
  final TextStyle? deltaStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          FormatUtils.formatLapTime(durationMs),
          style: style ??
              AppTypography.lapTime.copyWith(
                color: isPersonalBest
                    ? AppColors.green
                    : AppColors.textPrimary,
              ),
        ),
        if (deltaMs != null) ...[
          const SizedBox(width: 6),
          Text(
            FormatUtils.formatDelta(deltaMs!),
            style: deltaStyle ??
                AppTypography.bodySmall.copyWith(
                  color: deltaMs! < 0 ? AppColors.green : AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }
}

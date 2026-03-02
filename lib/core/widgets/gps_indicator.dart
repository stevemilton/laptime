import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// GPS signal quality indicator dot + label.
///
/// Shows colored dot reflecting GPS accuracy:
/// - Green: excellent (< 5m)
/// - Gold: good (5-10m)
/// - Red: poor (> 10m)
/// - Grey: no signal
class GpsIndicator extends StatelessWidget {
  const GpsIndicator({
    super.key,
    this.accuracy,
    this.isActive = false,
  });

  /// GPS accuracy in meters. Null means no signal.
  final double? accuracy;
  final bool isActive;

  Color get _dotColor {
    if (!isActive || accuracy == null) return AppColors.textTertiary;
    if (accuracy! < 5) return AppColors.green;
    if (accuracy! <= 10) return AppColors.gold;
    return AppColors.red;
  }

  String get _label {
    if (!isActive || accuracy == null) return 'GPS';
    return '${accuracy!.toStringAsFixed(0)}m';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _dotColor,
            boxShadow: isActive && accuracy != null
                ? [
                    BoxShadow(
                      color: _dotColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A stat display cell used in the profile stats grid, session detail, etc.
///
/// Shows a large number + label, optionally colored for emphasis.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.statNumber.copyWith(
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

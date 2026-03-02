import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Track condition selector pill group.
///
/// Options: Dry, Damp, Wet, Mixed
class TrackConditionSelector extends StatelessWidget {
  const TrackConditionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String> onChanged;

  static const _conditions = [
    ('dry', 'Dry', LucideIcons.sun),
    ('damp', 'Damp', LucideIcons.cloudDrizzle),
    ('wet', 'Wet', LucideIcons.cloudRain),
    ('mixed', 'Mixed', LucideIcons.cloudSun),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _conditions.map((c) {
        final isSelected = selected == c.$1;
        return GestureDetector(
          onTap: () => onChanged(c.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.purpleLight : AppColors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isSelected ? AppColors.purple : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.$3,
                  size: 14,
                  color: isSelected
                      ? AppColors.purple
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  c.$2,
                  style: AppTypography.bodySmall.copyWith(
                    color: isSelected
                        ? AppColors.purple
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Readonly track condition display.
class TrackConditionLabel extends StatelessWidget {
  const TrackConditionLabel({
    super.key,
    required this.condition,
  });

  final String condition;

  IconData get _icon {
    switch (condition) {
      case 'dry':
        return LucideIcons.sun;
      case 'damp':
        return LucideIcons.cloudDrizzle;
      case 'wet':
        return LucideIcons.cloudRain;
      case 'mixed':
        return LucideIcons.cloudSun;
      default:
        return LucideIcons.helpCircle;
    }
  }

  String get _label {
    return condition[0].toUpperCase() + condition.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          _label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

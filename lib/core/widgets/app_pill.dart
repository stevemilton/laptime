import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A rounded pill widget used throughout the app for tags, actions, and filters.
///
/// Variants:
/// - [AppPill.filled] – solid background (e.g. "P1" badge, active filter)
/// - [AppPill.outlined] – border only (e.g. action pills like "Sectors", "Nice")
/// - [AppPill.ghost] – no border, light bg (e.g. filter pills)
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.padding,
    this.isSelected = false,
  });

  /// Solid filled pill – used for badges and primary actions.
  factory AppPill.filled({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    Color backgroundColor = AppColors.purple,
    Color foregroundColor = AppColors.white,
  }) {
    return AppPill(
      key: key,
      label: label,
      icon: icon,
      onTap: onTap,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }

  /// Outlined pill – used for action buttons (Sectors, Nice, Comment).
  factory AppPill.outlined({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    Color foregroundColor = AppColors.textSecondary,
    Color borderColor = AppColors.border,
  }) {
    return AppPill(
      key: key,
      label: label,
      icon: icon,
      onTap: onTap,
      backgroundColor: AppColors.white,
      foregroundColor: foregroundColor,
      borderColor: borderColor,
    );
  }

  /// Ghost pill – subtle background, used for filters.
  factory AppPill.ghost({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    return AppPill(
      key: key,
      label: label,
      icon: icon,
      onTap: onTap,
      backgroundColor: isSelected ? AppColors.purpleLight : AppColors.ghost,
      foregroundColor: isSelected ? AppColors.purple : AppColors.textSecondary,
      isSelected: isSelected,
    );
  }

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.ghost;
    final fg = foregroundColor ?? AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          border: borderColor != null
              ? Border.all(color: borderColor!)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

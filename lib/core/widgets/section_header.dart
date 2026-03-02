import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Section header with title and optional trailing action.
///
/// Used to separate content sections (e.g. "Recent Sessions", "Garage").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding,
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.sectionLabel,
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Tappable "See All" / "View All" action for section headers.
class SectionAction extends StatelessWidget {
  const SectionAction({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.purple,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

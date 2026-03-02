import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// "P1" badge used on leaderboards, feed items, and lap details.
///
/// Gold variant for #1 position, purple for general personal best.
class P1Badge extends StatelessWidget {
  const P1Badge({
    super.key,
    this.position,
    this.isGold = false,
    this.size = P1BadgeSize.medium,
  });

  /// Shows "P1", "P2", etc. based on position. Null defaults to "P1".
  final int? position;
  final bool isGold;
  final P1BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final isFirst = (position ?? 1) == 1;
    final bg = isFirst || isGold ? AppColors.gold : AppColors.purple;
    final bgLight = isFirst || isGold ? AppColors.goldLight : AppColors.purpleLight;

    final double iconSize;
    final double fontSize;
    final EdgeInsets padding;

    switch (size) {
      case P1BadgeSize.small:
        iconSize = 10;
        fontSize = 10;
        padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
      case P1BadgeSize.medium:
        iconSize = 12;
        fontSize = 12;
        padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3);
      case P1BadgeSize.large:
        iconSize = 14;
        fontSize = 14;
        padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4);
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgLight,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFirst || isGold)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(LucideIcons.trophy, size: iconSize, color: bg),
            ),
          Text(
            'P${position ?? 1}',
            style: AppTypography.bodySmall.copyWith(
              color: bg,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}

enum P1BadgeSize { small, medium, large }

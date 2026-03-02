import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';

/// Standard card used throughout the app.
///
/// Consistent styling: white background, rounded corners, subtle shadow.
/// Use [AppCard.elevated] for more prominent cards (e.g. P1 spotlight).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.shadow,
    this.borderColor,
    this.borderRadius,
    this.color,
  });

  /// Elevated card variant – stronger shadow for featured content.
  factory AppCard.elevated({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    Color? color,
  }) {
    return AppCard(
      key: key,
      padding: padding,
      margin: margin,
      onTap: onTap,
      shadow: AppShadows.md,
      color: color,
      child: child,
    );
  }

  /// Purple-accented card for featured/spotlight content.
  factory AppCard.spotlight({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
  }) {
    return AppCard(
      key: key,
      padding: padding,
      margin: margin,
      onTap: onTap,
      shadow: AppShadows.purple,
      borderColor: AppColors.purpleBright.withValues(alpha: 0.3),
      child: child,
    );
  }

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color ?? AppColors.white,
            borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.lg),
            border: borderColor != null
                ? Border.all(color: borderColor!)
                : Border.all(color: AppColors.borderLight),
            boxShadow: shadow ?? AppShadows.sm,
          ),
          child: child,
        ),
      ),
    );
  }
}

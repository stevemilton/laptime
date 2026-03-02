import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Circular user avatar with image, initials fallback, and optional badge.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.size = 40,
    this.badge,
    this.borderColor,
    this.borderWidth = 0,
  });

  /// Small avatar (28px) for inline use.
  factory AppAvatar.small({
    Key? key,
    String? imageUrl,
    String? initials,
  }) {
    return AppAvatar(
      key: key,
      imageUrl: imageUrl,
      initials: initials,
      size: 28,
    );
  }

  /// Large avatar (64px) for profile screens.
  factory AppAvatar.large({
    Key? key,
    String? imageUrl,
    String? initials,
  }) {
    return AppAvatar(
      key: key,
      imageUrl: imageUrl,
      initials: initials,
      size: 64,
    );
  }

  /// Extra-large avatar (80px) for profile header.
  factory AppAvatar.xl({
    Key? key,
    String? imageUrl,
    String? initials,
    Widget? badge,
  }) {
    return AppAvatar(
      key: key,
      imageUrl: imageUrl,
      initials: initials,
      size: 80,
      badge: badge,
    );
  }

  final String? imageUrl;
  final String? initials;
  final double size;
  final Widget? badge;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.purpleLight,
            border: borderWidth > 0
                ? Border.all(
                    color: borderColor ?? AppColors.purple,
                    width: borderWidth,
                  )
                : null,
            image: imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: imageUrl == null
              ? Center(
                  child: initials != null
                      ? Text(
                          initials!,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.purple,
                            fontWeight: FontWeight.w600,
                            fontSize: size * 0.35,
                          ),
                        )
                      : Icon(
                          LucideIcons.user,
                          size: size * 0.45,
                          color: AppColors.purple,
                        ),
                )
              : null,
        ),
        if (badge != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: badge!,
          ),
      ],
    );
  }
}

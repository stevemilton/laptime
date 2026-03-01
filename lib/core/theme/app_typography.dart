import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  // Display font: Rufner (falls back to system serif if not loaded)
  static const _displayFamily = 'Rufner';
  // Body font: Rethink Sans
  static const _bodyFamily = 'RethinkSans';

  // Display / Headings (Rufner)
  static TextStyle displayLarge = const TextStyle(
    fontFamily: _displayFamily,
    fontSize: 72,
    fontWeight: FontWeight.w200,
    letterSpacing: -2.5,
    height: 1.0,
    color: AppColors.textPrimary,
  );

  static TextStyle displayMedium = const TextStyle(
    fontFamily: _displayFamily,
    fontSize: 52,
    fontWeight: FontWeight.w200,
    letterSpacing: -2.5,
    height: 1.0,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineLarge = const TextStyle(
    fontFamily: _displayFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineMedium = const TextStyle(
    fontFamily: _displayFamily,
    fontSize: 26,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineSmall = const TextStyle(
    fontFamily: _displayFamily,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  // Body (Rethink Sans)
  static TextStyle bodyLarge = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyMedium = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle bodySmall = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Labels
  static TextStyle labelLarge = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static TextStyle labelMedium = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static TextStyle labelSmall = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: AppColors.textTertiary,
  );

  // Section label (uppercase)
  static TextStyle sectionLabel = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
    color: AppColors.textTertiary,
  );

  // Lap time (large monospace-style display)
  static TextStyle lapTime = const TextStyle(
    fontFamily: _displayFamily,
    fontSize: 36,
    fontWeight: FontWeight.w200,
    letterSpacing: -1.5,
    height: 1.0,
    color: AppColors.textPrimary,
  );

  // Stat number
  static TextStyle statNumber = const TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 22,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.0,
    color: AppColors.textPrimary,
  );
}

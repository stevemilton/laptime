import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_theme.dart';

/// Horizontal weather info strip shown on Record screen and session detail.
///
/// Displays temperature, track condition, wind speed, and pressure.
class WeatherStrip extends StatelessWidget {
  const WeatherStrip({
    super.key,
    this.temperature,
    this.trackCondition,
    this.windSpeed,
    this.pressure,
  });

  final String? temperature;
  final String? trackCondition;
  final String? windSpeed;
  final String? pressure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _WeatherItem(
            icon: LucideIcons.thermometer,
            value: temperature ?? '--',
          ),
          _divider(),
          _WeatherItem(
            icon: LucideIcons.droplets,
            value: trackCondition ?? '--',
          ),
          _divider(),
          _WeatherItem(
            icon: LucideIcons.wind,
            value: windSpeed ?? '--',
          ),
          _divider(),
          _WeatherItem(
            icon: LucideIcons.gauge,
            value: pressure ?? '--',
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      color: AppColors.borderLight,
    );
  }
}

class _WeatherItem extends StatelessWidget {
  const _WeatherItem({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Profile', style: AppTypography.headlineLarge),
                  _HeaderAction(icon: LucideIcons.settings, onTap: () {}),
                ],
              ),
            ),

            // Profile card
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.purpleLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        'YN',
                        style: AppTypography.headlineSmall.copyWith(
                          color: AppColors.purple,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Name',
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 20,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@yourhandle',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _ProfilePill(label: 'Edit Profile', outlined: true),
                            const SizedBox(width: 8),
                            _ProfilePill(label: 'Share', outlined: false),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Stats grid
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  _StatBox(value: '24', label: 'Sessions'),
                  const SizedBox(width: 8),
                  _StatBox(value: '8', label: 'Circuits'),
                  const SizedBox(width: 8),
                  _StatBox(value: '143', label: 'Laps'),
                  const SizedBox(width: 8),
                  _StatBox(value: '3', label: 'P1s'),
                ],
              ),
            ),

            // Garage section
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text('GARAGE', style: AppTypography.sectionLabel),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                children: [
                  _CarCard(
                    name: 'BMW M2 CS',
                    detail: '2023 \u00B7 Petrol Blue \u00B7 Road',
                  ),
                  const SizedBox(height: 8),
                  _AddButton(label: '+ Add Car'),
                ],
              ),
            ),

            // Recent sessions
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text('RECENT SESSIONS', style: AppTypography.sectionLabel),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                children: [
                  _SessionCard(
                    circuit: 'Silverstone GP',
                    time: '1:59.204',
                    date: 'Yesterday',
                    laps: 12,
                  ),
                  const SizedBox(height: 8),
                  _SessionCard(
                    circuit: 'Snetterton 300',
                    time: '2:04.881',
                    date: '2 weeks ago',
                    laps: 16,
                  ),
                  const SizedBox(height: 8),
                  _SessionCard(
                    circuit: 'Brands Hatch Indy',
                    time: '59.114',
                    date: '3 weeks ago',
                    laps: 10,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.ghost,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  final String label;
  final bool outlined;

  const _ProfilePill({required this.label, required this.outlined});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : AppColors.ghost,
        borderRadius: BorderRadius.circular(100),
        border: outlined ? Border.all(color: AppColors.purple, width: 1.5) : null,
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: outlined ? AppColors.purple : AppColors.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;

  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.ghost,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.statNumber),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: AppTypography.labelSmall.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  final String name;
  final String detail;

  const _CarCard({required this.name, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppTypography.labelLarge.copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text(detail, style: AppTypography.bodySmall),
            ],
          ),
          Icon(LucideIcons.car, size: 20, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;

  const _AddButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.purple, width: 1.5),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(color: AppColors.purple),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final String circuit;
  final String time;
  final String date;
  final int laps;

  const _SessionCard({
    required this.circuit,
    required this.time,
    required this.date,
    required this.laps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(circuit, style: AppTypography.labelLarge),
              const SizedBox(height: 2),
              Text(
                '$date \u00B7 $laps laps',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
          Text(
            time,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w200,
              letterSpacing: -0.8,
              fontSize: 18,
              fontFamily: 'Rufner',
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';

class SectorsScreen extends StatefulWidget {
  const SectorsScreen({super.key});

  @override
  State<SectorsScreen> createState() => _SectorsScreenState();
}

class _SectorsScreenState extends State<SectorsScreen> {
  int _selectedTab = 0;
  int _selectedSector = 0;
  final _tabs = ['Leaderboards', 'My Sectors'];
  final _sectors = ['Full Lap', 'S1 \u2013 Copse', 'S2 \u2013 Becketts', 'S3 \u2013 Club'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sectors', style: AppTypography.headlineLarge),
                _HeaderAction(icon: LucideIcons.plus, onTap: () {}),
              ],
            ),
          ),

          // Sub-tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final isActive = i == _selectedTab;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTab = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        _tabs[i],
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                          color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // Circuit picker
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Silverstone GP',
                  style: AppTypography.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Northamptonshire, UK',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),

          // Sector selector pills
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(_sectors.length, (i) {
                final isActive = i == _selectedSector;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSector = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.purple : AppColors.ghost,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      _sectors[i],
                      style: AppTypography.bodySmall.copyWith(
                        color: isActive ? AppColors.white : AppColors.textSecondary,
                        fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 16),

          // Leaderboard
          Expanded(
            child: _selectedTab == 0
                ? _LeaderboardView()
                : _MySectorsView(),
          ),
        ],
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

class _LeaderboardView extends StatelessWidget {
  static const _mockBoard = [
    {'rank': 1, 'name': 'James Fletcher', 'car': 'Porsche 992 GT3', 'time': '1:58.342', 'cond': 'Dry \u00B7 14\u00B0C'},
    {'rank': 2, 'name': 'Marcus Holt', 'car': 'Ferrari 488 Challenge', 'time': '1:58.917', 'cond': 'Dry \u00B7 16\u00B0C'},
    {'rank': 3, 'name': 'You', 'car': 'Porsche 718 Cayman GT4', 'time': '1:59.204', 'cond': 'Dry \u00B7 14\u00B0C', 'isYou': true},
    {'rank': 4, 'name': 'Priya Anand', 'car': 'Honda Civic FK8 Type R', 'time': '2:01.552', 'cond': 'Dry \u00B7 12\u00B0C'},
    {'rank': 5, 'name': 'David Osei', 'car': 'Renault Megane RS Trophy', 'time': '2:02.114', 'cond': 'Damp \u00B7 9\u00B0C'},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        // P1 spotlight
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.goldLight,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.crown, size: 14, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Text(
                        'P1 \u2013 Circuit Record',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.gold),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'James Fletcher',
                        style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Porsche 992 GT3',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '1:58.342',
                        style: AppTypography.lapTime.copyWith(fontSize: 24),
                      ),
                      Text(
                        'Dry \u00B7 14\u00B0C',
                        style: AppTypography.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Rest of leaderboard
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (final d in _mockBoard.skip(1))
                _LeaderboardRow(data: d),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final Map<String, Object> data;

  const _LeaderboardRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final isYou = data['isYou'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isYou ? AppColors.purplePale : null,
        border: const Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${data['rank']}',
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: data['rank'] == 1 ? AppColors.gold : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      data['name'] as String,
                      style: AppTypography.labelLarge.copyWith(
                        color: isYou ? AppColors.purple : null,
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(You)',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.purple),
                      ),
                    ],
                  ],
                ),
                Text(
                  data['car'] as String,
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data['time'] as String,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                  fontSize: 16,
                ),
              ),
              Text(
                data['cond'] as String,
                style: AppTypography.labelSmall.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MySectorsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No sectors created yet',
        style: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

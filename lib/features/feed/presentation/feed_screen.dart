import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _selectedTab = 0;
  final _tabs = ['Following', 'Nearby', 'Teams'];

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
                Text('Feed', style: AppTypography.headlineLarge),
                Row(
                  children: [
                    _HeaderAction(icon: LucideIcons.userPlus, onTap: () {}),
                    const SizedBox(width: 8),
                    _HeaderAction(icon: LucideIcons.bell, onTap: () {}),
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
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

          // Feed content
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: 3,
              itemBuilder: (context, index) {
                return _FeedItemPlaceholder(index: index);
              },
            ),
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
        decoration: BoxDecoration(
          color: AppColors.ghost,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}

class _FeedItemPlaceholder extends StatelessWidget {
  final int index;

  const _FeedItemPlaceholder({required this.index});

  static const _mockData = [
    {
      'name': 'James Fletcher',
      'handle': '@jfletcher',
      'circuit': 'Silverstone GP',
      'lapTime': '1:59.204',
      'laps': '12',
      'car': 'Porsche 992 GT3',
      'condition': 'Dry',
      'temp': '14\u00B0C',
      'isPb': true,
    },
    {
      'name': 'Sarah Okafor',
      'handle': '@sarahraces',
      'circuit': 'Brands Hatch Indy',
      'lapTime': '59.114',
      'laps': '8',
      'car': 'Clio Cup S5',
      'condition': 'Damp',
      'temp': '11\u00B0C',
      'isPb': false,
    },
    {
      'name': 'Tom Bridger',
      'handle': '@tbridger92',
      'circuit': 'Snetterton 300',
      'lapTime': '2:04.881',
      'laps': '16',
      'car': 'BMW M2 CS',
      'condition': 'Dry',
      'temp': '18\u00B0C',
      'isPb': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final data = _mockData[index];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.purpleLight,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (data['name'] as String).split(' ').map((n) => n[0]).join(),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          data['name'] as String,
                          style: AppTypography.labelLarge,
                        ),
                        if (data['isPb'] == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.goldLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.crown, size: 10, color: AppColors.gold),
                                const SizedBox(width: 3),
                                Text(
                                  'P1',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${data['handle']} \u00B7 2h ago',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Circuit + lap time
          Text(
            data['circuit'] as String,
            style: AppTypography.headlineSmall.copyWith(
              fontSize: 20,
              letterSpacing: -0.3,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                data['lapTime'] as String,
                style: AppTypography.lapTime.copyWith(fontSize: 32),
              ),
              const SizedBox(width: 4),
              Text(
                'lap',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (data['isPb'] == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.purpleLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'PB',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              _StatChip(label: '${data['laps']} laps'),
              const SizedBox(width: 8),
              _StatChip(label: data['car'] as String),
              const SizedBox(width: 8),
              _StatChip(label: '${data['condition']} \u00B7 ${data['temp']}'),
            ],
          ),

          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              _ActionPill(icon: LucideIcons.trophy, label: 'Sectors'),
              const SizedBox(width: 8),
              _ActionPill(icon: LucideIcons.thumbsUp, label: 'Nice'),
              const SizedBox(width: 8),
              _ActionPill(icon: LucideIcons.messageCircle, label: ''),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;

  const _StatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.textSecondary,
        fontSize: 12,
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ghost,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

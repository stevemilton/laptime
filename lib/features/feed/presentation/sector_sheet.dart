import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../sectors/data/sector_repository.dart';
import '../data/feed_repository.dart';

/// Opens a bottom sheet showing sector times for a feed item's circuit.
void showSectorSheet(BuildContext context, WidgetRef ref, FeedItem item) {
  if (item.circuitId == null) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _SectorSheet(
      circuitId: item.circuitId!,
      circuitName: item.circuitName,
    ),
  );
}

class _SectorSheet extends ConsumerStatefulWidget {
  const _SectorSheet({
    required this.circuitId,
    this.circuitName,
  });

  final String circuitId;
  final String? circuitName;

  @override
  ConsumerState<_SectorSheet> createState() => _SectorSheetState();
}

class _SectorSheetState extends ConsumerState<_SectorSheet> {
  List<LocalSector>? _sectors;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSectors();
  }

  Future<void> _loadSectors() async {
    final db = ref.read(databaseProvider);
    final repo = SectorRepository(db);
    // The session author's circuit is usually not in the local cache —
    // pull its sectors from Supabase first.
    await repo.refreshCircuitSectors(widget.circuitId);
    final sectors = await repo.getCircuitSectors(widget.circuitId);
    if (mounted) {
      setState(() {
        _sectors = sectors;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Title
          Text(
            widget.circuitName != null
                ? 'Sectors - ${widget.circuitName}'
                : 'Sectors',
            style: AppTypography.headlineSmall,
          ),

          const SizedBox(height: 16),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_sectors == null || _sectors!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.flag,
                      size: 40,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No sectors defined for this circuit',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...(_sectors!.map((sector) => _SectorRow(sector: sector))),
        ],
      ),
    );
  }
}

class _SectorRow extends StatelessWidget {
  const _SectorRow({required this.sector});

  final LocalSector sector;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        context.push('/sectors/${sector.id}/leaderboard');
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(
              LucideIcons.flag,
              size: 18,
              color: AppColors.purple,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                sector.name,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

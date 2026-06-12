import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/lap_time_text.dart';
import '../../../core/widgets/p1_badge.dart';
import '../../../core/widgets/section_header.dart';
import '../../recording/data/circuit_repository.dart';
import '../data/sector_repository.dart';

// ── Providers ──

final _allCircuitsProvider = FutureProvider<List<LocalCircuit>>((ref) async {
  final db = ref.watch(databaseProvider);
  // Pull the shared catalogue so circuits created elsewhere appear too.
  await ref.read(circuitRepositoryProvider).refreshFromRemote();
  return db.getAllCircuits();
});

final _circuitSectorsProvider =
    StreamProvider.family<List<LocalSector>, String>((ref, circuitId) {
  final db = ref.watch(databaseProvider);
  final repo = SectorRepository(db);
  // Fire-and-forget remote refresh; the local watch picks up new rows.
  repo.refreshCircuitSectors(circuitId);
  return repo.watchCircuitSectors(circuitId);
});

final _userSectorsProvider =
    StreamProvider.family<List<LocalSector>, String>((ref, userId) {
  final db = ref.watch(databaseProvider);
  final repo = SectorRepository(db);
  return repo.watchUserSectors(userId);
});

final _sectorLeaderboardProvider = FutureProvider.family<
    List<LeaderboardEntry>, ({String sectorId, String? carClass})>(
  (ref, params) {
    final db = ref.watch(databaseProvider);
    final repo = SectorRepository(db);
    return repo.getSectorLeaderboard(
      params.sectorId,
      carClass: params.carClass,
    );
  },
);

// ── Screen ──

class SectorsScreen extends ConsumerStatefulWidget {
  const SectorsScreen({super.key});

  @override
  ConsumerState<SectorsScreen> createState() => _SectorsScreenState();
}

class _SectorsScreenState extends ConsumerState<SectorsScreen> {
  int _selectedTab = 0;
  int _selectedSectorIndex = 0;
  String? _selectedCircuitId;
  String _selectedCarClass = 'All';

  static const _tabs = ['Leaderboards', 'My Sectors'];
  static const _carClasses = [
    'All',
    'Road',
    'GT',
    'Touring',
    'Single Seater',
    'Sports Prototype',
  ];

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
                _HeaderAction(
                  icon: LucideIcons.plus,
                  onTap: () => _showCreationMethodPicker(),
                ),
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isActive
                                ? AppColors.purple
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        _tabs[i],
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: _selectedTab == 0
                ? _buildLeaderboardsTab()
                : _buildMySectorsTab(),
          ),
        ],
      ),
    );
  }

  // ── Leaderboards Tab ──

  Widget _buildLeaderboardsTab() {
    final circuitsAsync = ref.watch(_allCircuitsProvider);

    return circuitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textTertiary)),
      ),
      data: (circuits) {
        if (circuits.isEmpty) {
          return EmptyState(
            icon: LucideIcons.flag,
            title: 'No Circuits',
            subtitle:
                'Record a session at a circuit to start tracking sectors.',
          );
        }

        // Default to first circuit if none selected (local fallback only;
        // not stored via setState because this runs during build).
        final selectedCircuitId = (_selectedCircuitId != null &&
                circuits.any((c) => c.id == _selectedCircuitId))
            ? _selectedCircuitId!
            : circuits.first.id;
        _selectedCircuitId = selectedCircuitId;

        final selectedCircuit =
            circuits.firstWhere((c) => c.id == selectedCircuitId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Circuit picker
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: _CircuitPicker(
                circuits: circuits,
                selectedId: _selectedCircuitId!,
                onChanged: (id) => setState(() {
                  _selectedCircuitId = id;
                  _selectedSectorIndex = 0;
                }),
              ),
            ),

            // Sector selector and leaderboard content
            Expanded(
              child: _buildSectorContent(selectedCircuit),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectorContent(LocalCircuit circuit) {
    final sectorsAsync =
        ref.watch(_circuitSectorsProvider(circuit.id));

    return sectorsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textTertiary)),
      ),
      data: (sectors) {
        if (sectors.isEmpty) {
          return EmptyState(
            icon: LucideIcons.flag,
            title: 'No Sectors Defined',
            subtitle:
                'Create sectors to start comparing times at this circuit.',
            actionLabel: 'Create Sector',
            onAction: () => _showCreationMethodPicker(),
          );
        }

        // Clamp selected index
        if (_selectedSectorIndex >= sectors.length) {
          _selectedSectorIndex = 0;
        }

        final selectedSector = sectors[_selectedSectorIndex];

        return Column(
          children: [
            // Sector selector pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(
                children: List.generate(sectors.length, (i) {
                  final isActive = i == _selectedSectorIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedSectorIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.purple
                              : AppColors.ghost,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          sectors[i].name,
                          style: AppTypography.bodySmall.copyWith(
                            color: isActive
                                ? AppColors.white
                                : AppColors.textSecondary,
                            fontWeight: isActive
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Car class filter pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Row(
                children: _carClasses.map((cls) {
                  final isActive = cls == _selectedCarClass;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCarClass = cls),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.purpleLight
                              : AppColors.ghost,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          cls,
                          style: AppTypography.bodySmall.copyWith(
                            color: isActive
                                ? AppColors.purple
                                : AppColors.textTertiary,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // Leaderboard
            Expanded(
              child: _buildLeaderboard(selectedSector.id),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeaderboard(String sectorId) {
    final carClassFilter =
        _selectedCarClass == 'All' ? null : _selectedCarClass;

    final leaderboardAsync = ref.watch(
      _sectorLeaderboardProvider(
        (sectorId: sectorId, carClass: carClassFilter),
      ),
    );

    return leaderboardAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textTertiary)),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return EmptyState(
            icon: LucideIcons.trophy,
            title: 'No Times Yet',
            subtitle:
                'Record laps at this circuit to populate the leaderboard.',
          );
        }

        final p1 = entries.first;
        final rest = entries.skip(1).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            // P1 Spotlight Card
            _P1SpotlightCard(entry: p1),

            const SizedBox(height: 12),

            // Rest of leaderboard
            if (rest.isNotEmpty)
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rest.length; i++)
                      _LeaderboardRow(
                        entry: rest[i],
                        p1DurationMs: p1.durationMs,
                        isLast: i == rest.length - 1,
                        currentUserId: ref.read(currentUserProvider)?.id,
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── My Sectors Tab ──

  Widget _buildMySectorsTab() {
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser == null) {
      return EmptyState(
        icon: LucideIcons.logIn,
        title: 'Sign In Required',
        subtitle: 'Sign in to view and create sectors.',
      );
    }

    final sectorsAsync =
        ref.watch(_userSectorsProvider(currentUser.id));

    return Stack(
      children: [
        sectorsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textTertiary)),
          ),
          data: (sectors) {
            if (sectors.isEmpty) {
              return EmptyState(
                icon: LucideIcons.flag,
                title: 'No Sectors Created',
                subtitle:
                    'Define sectors on circuits to compare times with other drivers.',
                actionLabel: 'Create Sector',
                onAction: () => _showCreationMethodPicker(),
              );
            }

            return _MySectorsListView(
              sectors: sectors,
              onSectorTap: (sector) => _navigateToSectorLeaderboard(sector),
              onDeleteSector: (sector) => _confirmDeleteSector(sector),
            );
          },
        ),

        // FAB
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton(
            onPressed: () => _showCreationMethodPicker(),
            backgroundColor: AppColors.purple,
            child: const Icon(
              LucideIcons.plus,
              color: AppColors.white,
            ),
          ),
        ),
      ],
    );
  }

  void _showCreationMethodPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Create Sector',
                style: AppTypography.headlineSmall,
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.spline, color: AppColors.purple),
              title: Text('From My Laps', style: AppTypography.labelLarge),
              subtitle: Text(
                'Pick a recorded lap and scrub to set boundaries',
                style: AppTypography.bodySmall,
              ),
              onTap: () {
                Navigator.pop(context);
                this.context.pushNamed(RouteNames.sectorFromLap);
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading:
                  const Icon(LucideIcons.mapPin, color: AppColors.purple),
              title:
                  Text('From GPS Coordinates', style: AppTypography.labelLarge),
              subtitle: Text(
                'Tap the map or enter coordinates manually',
                style: AppTypography.bodySmall,
              ),
              onTap: () {
                Navigator.pop(context);
                this.context.pushNamed(RouteNames.sectorCreation);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _navigateToSectorLeaderboard(LocalSector sector) {
    setState(() {
      _selectedTab = 0;
      _selectedCircuitId = sector.circuitId;
      _selectedSectorIndex = 0;
    });

    // Try to find the sector index after switching circuits
    final sectorsAsync =
        ref.read(_circuitSectorsProvider(sector.circuitId));
    sectorsAsync.whenData((sectors) {
      final index = sectors.indexWhere((s) => s.id == sector.id);
      if (index >= 0) {
        setState(() => _selectedSectorIndex = index);
      }
    });
  }

  Future<void> _confirmDeleteSector(LocalSector sector) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sector'),
        content: Text(
          'Are you sure you want to delete "${sector.name}"? '
          'All associated times will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      final db = ref.read(databaseProvider);
      final repo = SectorRepository(db);
      await repo.deleteSector(sector.id, requestedBy: user.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not delete sector. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }
}

// ── Supporting Widgets ──

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

class _CircuitPicker extends StatelessWidget {
  const _CircuitPicker({
    required this.circuits,
    required this.selectedId,
    required this.onChanged,
  });

  final List<LocalCircuit> circuits;
  final String selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = circuits.firstWhere((c) => c.id == selectedId);

    return GestureDetector(
      onTap: () => _showCircuitPicker(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected.name, style: AppTypography.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  selected.country,
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            LucideIcons.chevronDown,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  void _showCircuitPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Select Circuit',
                style: AppTypography.headlineSmall,
              ),
            ),
            ...circuits.map((circuit) => ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(
                    circuit.name,
                    style: AppTypography.labelLarge.copyWith(
                      color: circuit.id == selectedId
                          ? AppColors.purple
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    circuit.country,
                    style: AppTypography.bodySmall,
                  ),
                  trailing: circuit.id == selectedId
                      ? const Icon(LucideIcons.check,
                          size: 18, color: AppColors.purple)
                      : null,
                  onTap: () {
                    onChanged(circuit.id);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _P1SpotlightCard extends StatelessWidget {
  const _P1SpotlightCard({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final carLabel = [entry.carMake, entry.carModel]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');

    return Container(
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
            children: [
              const P1Badge(position: 1, isGold: true, size: P1BadgeSize.medium),
              const SizedBox(width: 8),
              Text(
                'Sector Record',
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              AppAvatar(
                imageUrl: entry.avatarUrl,
                initials: getInitials(entry.displayName),
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: AppTypography.labelLarge
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (carLabel.isNotEmpty)
                      Text(carLabel, style: AppTypography.bodySmall),
                  ],
                ),
              ),
              LapTimeText(
                durationMs: entry.durationMs,
                style: AppTypography.lapTime.copyWith(fontSize: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.p1DurationMs,
    required this.isLast,
    this.currentUserId,
  });

  final LeaderboardEntry entry;
  final int p1DurationMs;
  final bool isLast;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final isYou = currentUserId != null && entry.userId == currentUserId;
    final deltaMs = entry.durationMs - p1DurationMs;
    final carLabel = [entry.carMake, entry.carModel]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isYou ? AppColors.purplePale : null,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.borderLight),
              ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Avatar
          AppAvatar(
            imageUrl: entry.avatarUrl,
            initials: getInitials(entry.displayName),
            size: 32,
          ),
          const SizedBox(width: 10),

          // Name and car
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayName,
                        style: AppTypography.labelLarge.copyWith(
                          color: isYou ? AppColors.purple : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(You)',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.purple),
                      ),
                    ],
                  ],
                ),
                if (carLabel.isNotEmpty)
                  Text(
                    carLabel,
                    style: AppTypography.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Time and delta
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LapTimeText(
                durationMs: entry.durationMs,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.5,
                  fontSize: 16,
                ),
              ),
              if (deltaMs > 0)
                Text(
                  '+${_formatDelta(deltaMs)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.red,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDelta(int deltaMs) {
    final seconds = deltaMs ~/ 1000;
    final millis = deltaMs % 1000;
    return '$seconds.${millis.toString().padLeft(3, '0')}s';
  }
}

class _MySectorsListView extends StatelessWidget {
  const _MySectorsListView({
    required this.sectors,
    required this.onSectorTap,
    required this.onDeleteSector,
  });

  final List<LocalSector> sectors;
  final ValueChanged<LocalSector> onSectorTap;
  final ValueChanged<LocalSector> onDeleteSector;

  @override
  Widget build(BuildContext context) {
    // Group sectors by circuit ID
    final grouped = <String, List<LocalSector>>{};
    for (final sector in sectors) {
      grouped.putIfAbsent(sector.circuitId, () => []).add(sector);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      itemCount: grouped.length,
      itemBuilder: (context, groupIndex) {
        final circuitId = grouped.keys.elementAt(groupIndex);
        final circuitSectors = grouped[circuitId]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Circuit header (uses circuit ID as fallback label)
            _CircuitGroupHeader(circuitId: circuitId),
            const SizedBox(height: 8),

            // Sector cards
            ...circuitSectors.map((sector) => _SectorCard(
                  sector: sector,
                  onTap: () => onSectorTap(sector),
                  onDelete: () => onDeleteSector(sector),
                )),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _CircuitGroupHeader extends ConsumerWidget {
  const _CircuitGroupHeader({required this.circuitId});

  final String circuitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return FutureBuilder<LocalCircuit?>(
      future: (db.select(db.localCircuits)
            ..where((t) => t.id.equals(circuitId)))
          .getSingleOrNull(),
      builder: (context, snapshot) {
        final circuitName = snapshot.data?.name ?? 'Circuit';
        return SectionHeader(
          title: circuitName,
          padding: EdgeInsets.zero,
        );
      },
    );
  }
}

class _SectorCard extends StatelessWidget {
  const _SectorCard({
    required this.sector,
    required this.onTap,
    required this.onDelete,
  });

  final LocalSector sector;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.purplePale,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              LucideIcons.flag,
              size: 16,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sector.name,
                  style: AppTypography.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCoordinates(sector),
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: AppColors.textTertiary,
            ),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  String _formatCoordinates(LocalSector sector) {
    if (sector.startPointJson == null || sector.endPointJson == null) {
      return 'No coordinates set';
    }
    return 'Start and end points defined';
  }
}


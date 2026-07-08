import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/services/lap_maintenance_service.dart';
import '../../../core/services/weather_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/widgets.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../recording/presentation/circuit_create_screen.dart';
import '../../sectors/data/sector_repository.dart';
import '../data/session_repository.dart';

/// Session detail view.
///
/// Shows session header (circuit, date, car), weather strip, and a scrollable
/// lap list with times, deltas from best, and P1 badges.
class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  LocalSession? _session;
  LocalCircuit? _circuit;
  LocalCar? _car;
  List<LocalLap> _laps = [];
  bool _circuitHasSectors = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final repo = ref.read(sessionRepositoryProvider);

    final session = await repo.getSession(widget.sessionId);
    if (session == null || !mounted) return;

    LocalCircuit? circuit;
    var circuitHasSectors = true;
    if (session.circuitId != null) {
      circuit = await repo.getCircuit(session.circuitId!);
      final sectors = await ref
          .read(sectorRepositoryProvider)
          .getCircuitSectors(session.circuitId!);
      circuitHasSectors = sectors.isNotEmpty;
    }

    LocalCar? car;
    if (session.carId != null) {
      car = await repo.getCar(session.carId!);
    }

    final laps = await repo.getSessionLaps(widget.sessionId);

    if (!mounted) return;

    setState(() {
      _session = session;
      _circuit = circuit;
      _car = car;
      _laps = laps;
      _circuitHasSectors = circuitHasSectors;
      _isLoading = false;
    });
  }

  /// Open the circuit's start/finish line for editing; on save, all of the
  /// user's sessions at the circuit (including this one) are re-scored.
  Future<void> _editStartFinishLine() async {
    final circuit = _circuit;
    if (circuit == null) return;

    final updated = await Navigator.of(context).push<LocalCircuit>(
      MaterialPageRoute(
        builder: (_) => CircuitCreateScreen(
          initialLat: circuit.gpsLat,
          initialLng: circuit.gpsLng,
          editCircuit: circuit,
        ),
      ),
    );
    if (updated == null || !mounted) return;

    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start/finish line updated — laps re-scored'),
        ),
      );
    }
  }

  Future<void> _deleteLap(LocalLap lap) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Lap ${lap.lapNumber}?'),
        content: const Text(
          'This removes the lap, its telemetry, and its sector times. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(lapMaintenanceServiceProvider).deleteLap(lap.id);
    ref.read(syncServiceProvider).requestSync();
    await _loadData();
  }

  int? get _bestLapMs {
    if (_laps.isEmpty) return null;
    return _laps.map((l) => l.durationMs).reduce(
        (a, b) => a < b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Session Detail',
          style: AppTypography.headlineSmall,
        ),
        actions: [
          if (_circuit != null)
            IconButton(
              icon: const Icon(LucideIcons.flag, size: 20),
              tooltip: 'Fix start/finish line',
              onPressed: _editStartFinishLine,
            ),
          IconButton(
            icon: const Icon(LucideIcons.pencil, size: 20),
            onPressed: () {
              context.push('/session/${widget.sessionId}/edit');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.purple),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final session = _session;
    if (session == null) {
      return const EmptyState(
        icon: LucideIcons.alertCircle,
        title: 'Session not found',
        subtitle: 'This session may have been deleted.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Session header card
        _buildHeader(session),

        // Weather strip
        if (session.weatherJson != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: _buildWeatherStrip(session.weatherJson!),
          ),
        ],

        // Stats row
        _buildStatsRow(session),

        // Sector creation nudge: enough laps here, but the circuit has no
        // sectors yet — nobody finds retroactive leaderboards on their own.
        if (_circuit != null &&
            !_circuitHasSectors &&
            _laps.length >= AppConstants.minLapsForSectorCreation)
          _buildSectorNudge(),

        const SizedBox(height: 8),

        // Laps section
        const SectionHeader(title: 'Laps'),
        const SizedBox(height: 4),

        if (_laps.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(
              icon: LucideIcons.timer,
              title: 'No laps recorded',
              subtitle: 'Laps will appear here after recording.',
            ),
          )
        else
          ..._laps.map((lap) => _buildLapRow(lap)),
      ],
    );
  }

  Widget _buildHeader(LocalSession session) {
    final dateStr = DateFormat('EEE d MMM yyyy').format(session.startedAt);
    final timeStr = DateFormat('HH:mm').format(session.startedAt);

    String? carLabel;
    if (_car != null) {
      carLabel = _car!.year != null
          ? '${_car!.year} ${_car!.make} ${_car!.model}'
          : '${_car!.make} ${_car!.model}';
    }

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Circuit name (prefer circuitName field, then circuit table, then fallback)
          Text(
            session.circuitName ?? _circuit?.name ?? 'Unknown Circuit',
            style: AppTypography.headlineLarge,
          ),
          const SizedBox(height: 6),

          // Date and time
          Row(
            children: [
              Icon(LucideIcons.calendar, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                '$dateStr at $timeStr',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          if (carLabel != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(LucideIcons.car, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  carLabel,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],

          if (session.trackCondition != null) ...[
            const SizedBox(height: 8),
            TrackConditionLabel(condition: session.trackCondition!),
          ],
        ],
      ),
    );
  }

  Widget _buildWeatherStrip(String weatherJson) {
    try {
      final raw = jsonDecode(weatherJson) as Map<String, dynamic>;

      // WeatherData.fromJson auto-detects all formats (flat, One Call 3.0, Current 2.5)
      final weather = WeatherData.fromJson(raw);

      final units = ref.watch(unitsProvider);
      return WeatherStrip(
        temperature: FormatUtils.formatTemp(weather.tempCelsius, units: units),
        windSpeed: FormatUtils.formatWindSpeed(weather.windSpeed, units: units),
        pressure: FormatUtils.formatPressure(weather.pressure, units: units),
        trackCondition: '${weather.humidity}%',
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildStatsRow(LocalSession session) {
    final bestMs = _bestLapMs;
    final lapCount = _laps.length;

    String durationStr = '--';
    if (session.endedAt != null) {
      final duration = session.endedAt!.difference(session.startedAt);
      final mins = duration.inMinutes;
      final secs = duration.inSeconds % 60;
      durationStr = '${mins}m ${secs}s';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StatCell(
              value: lapCount.toString(),
              label: 'Laps',
            ),
            Container(width: 1, height: 32, color: AppColors.borderLight),
            StatCell(
              value: bestMs != null
                  ? FormatUtils.formatLapTime(bestMs)
                  : '--',
              label: 'Best Lap',
              valueColor: AppColors.green,
            ),
            Container(width: 1, height: 32, color: AppColors.borderLight),
            StatCell(
              value: durationStr,
              label: 'Duration',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectorNudge() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AppCard(
        onTap: () => context.push('/sector/from-lap'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.purplePale,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Icon(LucideIcons.splitSquareHorizontal,
                  size: 18, color: AppColors.purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create sectors for this circuit',
                      style: AppTypography.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Split the track to compare your pace corner by corner',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildLapRow(LocalLap lap) {
    final bestMs = _bestLapMs;
    final isBest = bestMs != null && lap.durationMs == bestMs;
    final deltaMs = bestMs != null && !isBest
        ? lap.durationMs - bestMs
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      child: Dismissible(
        key: ValueKey(lap.id),
        direction: DismissDirection.endToStart,
        // The dialog owns the decision; the row itself never auto-dismisses
        // (deletion reloads the list, which removes the row).
        confirmDismiss: (_) async {
          await _deleteLap(lap);
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(LucideIcons.trash2,
              size: 18, color: AppColors.white),
        ),
        child: AppCard(
        onTap: () {
          context.push('/session/${widget.sessionId}/lap/${lap.id}');
        },
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Lap number
            SizedBox(
              width: 36,
              child: Text(
                'L${lap.lapNumber}',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),

            // Lap time
            Expanded(
              child: LapTimeText(
                durationMs: lap.durationMs,
                deltaMs: deltaMs,
                isPersonalBest: isBest,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isBest ? AppColors.green : AppColors.textPrimary,
                ),
                deltaStyle: AppTypography.bodySmall.copyWith(
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // P1 badge for fastest lap
            if (isBest)
              const P1Badge(
                position: 1,
                isGold: true,
                size: P1BadgeSize.small,
              ),

            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
        ),
      ),
    );
  }
}

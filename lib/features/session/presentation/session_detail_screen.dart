import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/widgets.dart';
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
    if (session.circuitId != null) {
      circuit = await repo.getCircuit(session.circuitId!);
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
      _isLoading = false;
    });
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

      // Normalize: support flat format (new) and raw API formats (old)
      double? temp;
      double? wind;
      double? press;
      int? humid;

      if (raw.containsKey('temp') && raw['temp'] is num) {
        // Flat / normalized format
        temp = (raw['temp'] as num).toDouble();
        wind = (raw['wind_speed'] as num?)?.toDouble();
        press = (raw['pressure'] as num?)?.toDouble();
        humid = (raw['humidity'] as num?)?.toInt();
      } else if (raw.containsKey('current')) {
        // One Call 3.0 raw format
        final c = raw['current'] as Map<String, dynamic>? ?? {};
        temp = (c['temp'] as num?)?.toDouble();
        wind = (c['wind_speed'] as num?)?.toDouble();
        press = (c['pressure'] as num?)?.toDouble();
        humid = (c['humidity'] as num?)?.toInt();
      } else if (raw.containsKey('main')) {
        // Current Weather 2.5 raw format
        final m = raw['main'] as Map<String, dynamic>? ?? {};
        final w = raw['wind'] as Map<String, dynamic>? ?? {};
        temp = (m['temp'] as num?)?.toDouble();
        wind = (w['speed'] as num?)?.toDouble();
        press = (m['pressure'] as num?)?.toDouble();
        humid = (m['humidity'] as num?)?.toInt();
      }

      return WeatherStrip(
        temperature: temp != null ? FormatUtils.formatTemp(temp) : null,
        windSpeed: wind != null ? FormatUtils.formatWindSpeed(wind) : null,
        pressure: press != null ? '${press.round()} hPa' : null,
        trackCondition: humid != null ? '$humid%' : null,
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

  Widget _buildLapRow(LocalLap lap) {
    final bestMs = _bestLapMs;
    final isBest = bestMs != null && lap.durationMs == bestMs;
    final deltaMs = bestMs != null && !isBest
        ? lap.durationMs - bestMs
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
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
    );
  }
}

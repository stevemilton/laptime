import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/widgets.dart';
import '../data/session_repository.dart';

/// Single lap detail screen.
///
/// Shows a large lap time display, delta from session best, weather info
/// from the parent session, and placeholders for GPS trace map and
/// telemetry charts.
class LapDetailScreen extends ConsumerStatefulWidget {
  const LapDetailScreen({
    super.key,
    required this.sessionId,
    required this.lapId,
  });

  final String sessionId;
  final String lapId;

  @override
  ConsumerState<LapDetailScreen> createState() => _LapDetailScreenState();
}

class _LapDetailScreenState extends ConsumerState<LapDetailScreen> {
  LocalLap? _lap;
  LocalSession? _session;
  LocalCircuit? _circuit;
  List<LocalLap> _allLaps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final repo = ref.read(sessionRepositoryProvider);

    final lap = await repo.getLap(widget.lapId);
    final session = await repo.getSession(widget.sessionId);

    LocalCircuit? circuit;
    if (session?.circuitId != null) {
      circuit = await repo.getCircuit(session!.circuitId!);
    }

    final allLaps = await repo.getSessionLaps(widget.sessionId);

    if (!mounted) return;

    setState(() {
      _lap = lap;
      _session = session;
      _circuit = circuit;
      _allLaps = allLaps;
      _isLoading = false;
    });
  }

  int? get _bestLapMs {
    if (_allLaps.isEmpty) return null;
    return _allLaps.map((l) => l.durationMs).reduce(
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
          _lap != null ? 'Lap ${_lap!.lapNumber}' : 'Lap Detail',
          style: AppTypography.headlineSmall,
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.purple),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final lap = _lap;
    if (lap == null) {
      return const EmptyState(
        icon: LucideIcons.alertCircle,
        title: 'Lap not found',
        subtitle: 'This lap may have been deleted.',
      );
    }

    final bestMs = _bestLapMs;
    final isBest = bestMs != null && lap.durationMs == bestMs;
    final deltaMs = bestMs != null && !isBest
        ? lap.durationMs - bestMs
        : null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Big lap time hero section
        _buildLapTimeHero(lap, isBest, deltaMs),

        const SizedBox(height: 16),

        // Context info
        _buildContextCard(lap),

        const SizedBox(height: 16),

        // Weather strip from parent session
        if (_session?.weatherJson != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildWeatherStrip(_session!.weatherJson!),
          ),
          const SizedBox(height: 16),
        ],

        // GPS trace map placeholder
        const SectionHeader(title: 'GPS Trace'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildMapPlaceholder(),
        ),

        const SizedBox(height: 24),

        // Telemetry charts placeholder
        const SectionHeader(title: 'Telemetry'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildTelemetryPlaceholder(),
        ),
      ],
    );
  }

  Widget _buildLapTimeHero(LocalLap lap, bool isBest, int? deltaMs) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          // P1 badge if fastest
          if (isBest) ...[
            const P1Badge(
              position: 1,
              isGold: true,
              size: P1BadgeSize.large,
            ),
            const SizedBox(height: 12),
          ],

          // Big lap time
          Text(
            FormatUtils.formatLapTime(lap.durationMs),
            style: AppTypography.displayLarge.copyWith(
              color: isBest ? AppColors.green : AppColors.textPrimary,
            ),
          ),

          // Delta from best
          if (deltaMs != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.redLight,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                FormatUtils.formatDelta(deltaMs),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          if (isBest) ...[
            const SizedBox(height: 8),
            Text(
              'Session Best',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextCard(LocalLap lap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StatCell(
              value: 'L${lap.lapNumber}',
              label: 'Lap',
            ),
            Container(width: 1, height: 32, color: AppColors.borderLight),
            StatCell(
              value: _circuit?.name ?? '--',
              label: 'Circuit',
            ),
            Container(width: 1, height: 32, color: AppColors.borderLight),
            StatCell(
              value: '${_allLaps.length}',
              label: 'Total Laps',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherStrip(String weatherJson) {
    try {
      final data = jsonDecode(weatherJson) as Map<String, dynamic>;
      final temp = data['temp'] is num
          ? FormatUtils.formatTemp((data['temp'] as num).toDouble())
          : null;
      final windSpeed = data['wind_speed'] is num
          ? FormatUtils.formatWindSpeed(
              (data['wind_speed'] as num).toDouble())
          : null;
      final pressure = data['pressure'] is num
          ? '${(data['pressure'] as num).round()} hPa'
          : null;
      final humidity = data['humidity'] is num
          ? '${(data['humidity'] as num).round()}%'
          : null;

      return WeatherStrip(
        temperature: temp,
        windSpeed: windSpeed,
        pressure: pressure,
        trackCondition: humidity,
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildMapPlaceholder() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.ghost,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.map,
                size: 32,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                'GPS Trace Map',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Coming in a future update',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryPlaceholder() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.ghost,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.lineChart,
                size: 32,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                'Telemetry Charts',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Accelerometer, gyroscope, and speed data',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

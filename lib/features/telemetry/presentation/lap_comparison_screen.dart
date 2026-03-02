import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/sensor_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/widgets.dart';
import '../../session/data/session_repository.dart';
import '../data/telemetry_processor.dart';
import 'gg_diagram.dart';
import 'telemetry_chart.dart';

/// Screen for comparing two laps side-by-side with telemetry visualisations.
///
/// Displays:
/// - Lap selector pills at the top
/// - Delta summary card
/// - GPS overlay map placeholder
/// - Tabbed telemetry charts: Speed, G-Force, Braking, G-G Diagram
class LapComparisonScreen extends ConsumerStatefulWidget {
  const LapComparisonScreen({
    super.key,
    required this.sessionId,
    required this.lap1Id,
    required this.lap2Id,
  });

  final String sessionId;
  final String lap1Id;
  final String lap2Id;

  @override
  ConsumerState<LapComparisonScreen> createState() =>
      _LapComparisonScreenState();
}

class _LapComparisonScreenState extends ConsumerState<LapComparisonScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  LocalLap? _lap1;
  LocalLap? _lap2;

  ProcessedTelemetry? _telemetry1;
  ProcessedTelemetry? _telemetry2;
  List<GGPoint> _gg1 = [];
  List<GGPoint> _gg2 = [];

  static const _tabLabels = ['Speed', 'G-Force', 'Braking', 'G-G Diagram'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final repo = ref.read(sessionRepositoryProvider);

    final lap1 = await repo.getLap(widget.lap1Id);
    final lap2 = await repo.getLap(widget.lap2Id);

    // Load sensor data for both laps
    final sensor1 = await repo.getLapSensorData(widget.lap1Id);
    final sensor2 = await repo.getLapSensorData(widget.lap2Id);

    ProcessedTelemetry? t1;
    ProcessedTelemetry? t2;
    List<GGPoint> gg1 = [];
    List<GGPoint> gg2 = [];

    if (sensor1 != null) {
      final snapshot = _sensorDataToSnapshot(sensor1);
      t1 = TelemetryProcessor.processSensorData(snapshot);
      gg1 = TelemetryProcessor.computeGGData(t1, downsample: 3);
    }

    if (sensor2 != null) {
      final snapshot = _sensorDataToSnapshot(sensor2);
      t2 = TelemetryProcessor.processSensorData(snapshot);
      gg2 = TelemetryProcessor.computeGGData(t2, downsample: 3);
    }

    if (!mounted) return;

    setState(() {
      _lap1 = lap1;
      _lap2 = lap2;
      _telemetry1 = t1;
      _telemetry2 = t2;
      _gg1 = gg1;
      _gg2 = gg2;
      _isLoading = false;
    });
  }

  /// Convert database sensor row to an in-memory snapshot.
  LapSensorSnapshot _sensorDataToSnapshot(LocalLapSensorDataData data) {
    return LapSensorSnapshot(
      timestamps: _decodeJsonDoubleList(data.timestampsJson),
      accelX: _decodeJsonDoubleList(data.accelXJson),
      accelY: _decodeJsonDoubleList(data.accelYJson),
      accelZ: _decodeJsonDoubleList(data.accelZJson),
      gyroX: _decodeJsonDoubleList(data.gyroXJson),
      gyroY: _decodeJsonDoubleList(data.gyroYJson),
      gyroZ: _decodeJsonDoubleList(data.gyroZJson),
      magHeading: _decodeJsonDoubleList(data.magHeadingJson),
      baroPressure: _decodeJsonDoubleList(data.baroPressureJson),
    );
  }

  List<double> _decodeJsonDoubleList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return [];
    }
  }

  String _lapLabel(LocalLap? lap) {
    if (lap == null) return '--';
    return 'L${lap.lapNumber}';
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
          'Lap Comparison',
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
    if (_lap1 == null || _lap2 == null) {
      return const EmptyState(
        icon: LucideIcons.alertCircle,
        title: 'Laps not found',
        subtitle: 'One or both selected laps could not be loaded.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Lap selector row
        _buildLapSelectorRow(),

        const SizedBox(height: 12),

        // Delta summary card
        _buildDeltaSummary(),

        const SizedBox(height: 16),

        // GPS map placeholder
        const SectionHeader(title: 'Track Map'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildMapPlaceholder(),
        ),

        const SizedBox(height: 24),

        // Telemetry tabs
        const SectionHeader(title: 'Telemetry'),
        const SizedBox(height: 4),
        _buildTelemetryTabs(),
      ],
    );
  }

  Widget _buildLapSelectorRow() {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Lap 1 pill
          Expanded(
            child: _buildLapPill(
              lap: _lap1,
              color: AppColors.purple,
              label: _lapLabel(_lap1),
            ),
          ),
          const SizedBox(width: 12),
          // VS indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'vs',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Lap 2 pill
          Expanded(
            child: _buildLapPill(
              lap: _lap2,
              color: AppColors.green,
              label: _lapLabel(_lap2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapPill({
    required LocalLap? lap,
    required Color color,
    required String label,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lap != null
                  ? FormatUtils.formatLapTime(lap.durationMs)
                  : '--:--.---',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeltaSummary() {
    final lap1 = _lap1;
    final lap2 = _lap2;
    if (lap1 == null || lap2 == null) return const SizedBox.shrink();

    final deltaMs = lap2.durationMs - lap1.durationMs;
    final lap1Faster = deltaMs > 0;
    final deltaColor = lap1Faster ? AppColors.green : AppColors.red;
    final fasterLabel = lap1Faster
        ? 'Lap ${lap1.lapNumber} is faster'
        : deltaMs < 0
            ? 'Lap ${lap2.lapNumber} is faster'
            : 'Equal lap times';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.timer,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Delta',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Delta value
            Text(
              FormatUtils.formatDelta(deltaMs),
              style: AppTypography.headlineLarge.copyWith(
                color: deltaColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fasterLabel,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Container(
        height: 180,
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
                'GPS Overlay Coming Soon',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Lap traces will be overlaid on the circuit map',
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

  Widget _buildTelemetryTabs() {
    final hasData = _telemetry1 != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Tab bar
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderLight),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.purple,
                unselectedLabelColor: AppColors.textTertiary,
                labelStyle: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: AppTypography.labelMedium,
                indicatorColor: AppColors.purple,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: _tabLabels
                    .map((label) => Tab(text: label))
                    .toList(),
              ),
            ),

            // Tab content
            SizedBox(
              height: hasData ? 340 : 200,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSpeedTab(),
                  _buildGForceTab(),
                  _buildBrakingTab(),
                  _buildGGTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedTab() {
    if (_telemetry1 == null) return _buildNoDataPlaceholder('Speed');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: TelemetryChart(
        title: 'Speed (km/h)',
        data1: _telemetry1!.speed,
        data2: _telemetry2?.speed,
        label1: _lapLabel(_lap1),
        label2: _lapLabel(_lap2),
        yAxisLabel: 'km/h',
        height: 240,
      ),
    );
  }

  Widget _buildGForceTab() {
    if (_telemetry1 == null) return _buildNoDataPlaceholder('G-Force');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: TelemetryChart(
        title: 'Lateral G',
        data1: _telemetry1!.lateralG,
        data2: _telemetry2?.lateralG,
        label1: _lapLabel(_lap1),
        label2: _lapLabel(_lap2),
        yAxisLabel: 'g',
        height: 240,
      ),
    );
  }

  Widget _buildBrakingTab() {
    if (_telemetry1 == null) return _buildNoDataPlaceholder('Braking');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: TelemetryChart(
        title: 'Longitudinal G (Braking / Acceleration)',
        data1: _telemetry1!.longitudinalG,
        data2: _telemetry2?.longitudinalG,
        label1: _lapLabel(_lap1),
        label2: _lapLabel(_lap2),
        yAxisLabel: 'g',
        height: 240,
        color1: AppColors.red,
        color2: AppColors.green,
      ),
    );
  }

  Widget _buildGGTab() {
    if (_gg1.isEmpty) return _buildNoDataPlaceholder('G-G Diagram');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: GGDiagram(
          data: _gg1,
          compareData: _gg2.isNotEmpty ? _gg2 : null,
          size: 260,
          label1: _lapLabel(_lap1),
          label2: _lapLabel(_lap2),
        ),
      ),
    );
  }

  Widget _buildNoDataPlaceholder(String channelName) {
    return Center(
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
            '$channelName data',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No sensor data recorded for these laps',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

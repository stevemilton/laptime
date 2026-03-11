import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/trace_map.dart';
import '../data/sector_repository.dart';

/// Strava-style sector creation from a recorded lap trace.
///
/// Step 1: Pick a circuit → session → lap (with GPS trace)
/// Step 2: Scrub a RangeSlider along the trace to pick start/end
/// Step 3: Name and save
class SectorFromLapScreen extends ConsumerStatefulWidget {
  const SectorFromLapScreen({super.key});

  @override
  ConsumerState<SectorFromLapScreen> createState() =>
      _SectorFromLapScreenState();
}

class _SectorFromLapScreenState extends ConsumerState<SectorFromLapScreen> {
  // Step 1 state
  List<LocalCircuit> _circuits = [];
  String? _selectedCircuitId;
  List<LocalSession> _sessions = [];
  String? _selectedSessionId;
  List<LocalLap> _laps = [];
  String? _selectedLapId;
  bool _circuitsLoaded = false;

  // Step 2 state
  List<LatLng> _tracePoints = [];
  RangeValues _sliderRange = const RangeValues(0.1, 0.9);
  final MapController _mapController = MapController();

  // Step 3 state
  final _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCircuits();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadCircuits() async {
    final db = ref.read(databaseProvider);
    final circuits = await db.getAllCircuits();
    if (mounted) {
      setState(() {
        _circuits = circuits;
        _circuitsLoaded = true;
      });
    }
  }

  Future<void> _onCircuitSelected(String? circuitId) async {
    if (circuitId == null) return;
    setState(() {
      _selectedCircuitId = circuitId;
      _selectedSessionId = null;
      _selectedLapId = null;
      _sessions = [];
      _laps = [];
      _tracePoints = [];
    });

    final db = ref.read(databaseProvider);
    final sessions = await db.getCircuitSessions(circuitId);
    if (mounted) {
      setState(() => _sessions = sessions);
    }
  }

  Future<void> _onSessionSelected(String? sessionId) async {
    if (sessionId == null) return;
    setState(() {
      _selectedSessionId = sessionId;
      _selectedLapId = null;
      _laps = [];
      _tracePoints = [];
    });

    final db = ref.read(databaseProvider);
    final allLaps = await db.getSessionLaps(sessionId);
    // Only keep laps that have GPS trace data
    final lapsWithTrace =
        allLaps.where((l) => l.traceJson != null && l.traceJson!.isNotEmpty).toList();
    if (mounted) {
      setState(() => _laps = lapsWithTrace);
    }
  }

  void _onLapSelected(String? lapId) {
    if (lapId == null) return;
    final lap = _laps.firstWhere((l) => l.id == lapId);
    final points = parseTraceJson(lap.traceJson);

    setState(() {
      _selectedLapId = lapId;
      _tracePoints = points;
      _sliderRange = const RangeValues(0.1, 0.9);
    });
  }

  /// Interpolate a LatLng at fractional position [t] (0.0–1.0) along the trace.
  LatLng _pointAtFraction(double t) {
    if (_tracePoints.isEmpty) return const LatLng(0, 0);
    if (_tracePoints.length == 1) return _tracePoints.first;

    final totalSegments = _tracePoints.length - 1;
    final exactIndex = t * totalSegments;
    final i = exactIndex.floor().clamp(0, totalSegments - 1);
    final frac = exactIndex - i;

    final p1 = _tracePoints[i];
    final p2 = _tracePoints[(i + 1).clamp(0, _tracePoints.length - 1)];

    return LatLng(
      p1.latitude + (p2.latitude - p1.latitude) * frac,
      p1.longitude + (p2.longitude - p1.longitude) * frac,
    );
  }

  /// Extract the sub-list of trace points between slider start and end.
  List<LatLng> _segmentPoints() {
    if (_tracePoints.isEmpty) return [];
    final totalSegments = _tracePoints.length - 1;

    final startIdx = (_sliderRange.start * totalSegments).floor();
    final endIdx = (_sliderRange.end * totalSegments).ceil();

    return _tracePoints.sublist(
      startIdx.clamp(0, _tracePoints.length - 1),
      (endIdx + 1).clamp(0, _tracePoints.length),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a sector name.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    if (_selectedCircuitId == null || _tracePoints.isEmpty) return;

    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to create sectors.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final startPoint = _pointAtFraction(_sliderRange.start);
      final endPoint = _pointAtFraction(_sliderRange.end);

      final db = ref.read(databaseProvider);
      final repo = SectorRepository(db);

      final sectorId = await repo.createSector(
        circuitId: _selectedCircuitId!,
        createdBy: user.id,
        name: name,
        startLat: startPoint.latitude,
        startLng: startPoint.longitude,
        endLat: endPoint.latitude,
        endLng: endPoint.longitude,
      );

      // Retroactively score all existing laps
      await repo.persistSectorTimesForCircuit(sectorId);

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not create sector. Please try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Sector from Lap'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: !_circuitsLoaded
          ? const Center(child: CircularProgressIndicator())
          : _circuits.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.flag, size: 40,
                            color: AppColors.textTertiary),
                        const SizedBox(height: 16),
                        Text(
                          'No Circuits',
                          style: AppTypography.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Record a session at a circuit first.',
                          style: AppTypography.bodyMedium
                              .copyWith(color: AppColors.textTertiary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildStepHeader('1', 'Select a Lap'),
                    const SizedBox(height: 12),
                    _buildLapPickers(),
                    if (_tracePoints.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _buildStepHeader('2', 'Set Sector Boundaries'),
                      const SizedBox(height: 12),
                      _buildMapWithSlider(),
                      const SizedBox(height: 28),
                      _buildStepHeader('3', 'Name & Save'),
                      const SizedBox(height: 12),
                      _buildSaveSection(),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
    );
  }

  Widget _buildStepHeader(String number, String title) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: AppColors.purple,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: AppTypography.headlineSmall),
      ],
    );
  }

  Widget _buildLapPickers() {
    return Column(
      children: [
        // Circuit picker
        DropdownButtonFormField<String>(
          initialValue: _selectedCircuitId,
          decoration: const InputDecoration(labelText: 'Circuit'),
          items: _circuits
              .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name),
                  ))
              .toList(),
          onChanged: _onCircuitSelected,
        ),
        const SizedBox(height: 12),

        // Session picker
        if (_selectedCircuitId != null)
          DropdownButtonFormField<String>(
            initialValue: _selectedSessionId,
            decoration: const InputDecoration(labelText: 'Session'),
            items: _sessions
                .map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${FormatUtils.formatShortDate(s.startedAt)}'
                        '${s.circuitName != null ? ' — ${s.circuitName}' : ''}',
                      ),
                    ))
                .toList(),
            onChanged: _onSessionSelected,
            hint: Text(
              _sessions.isEmpty ? 'No sessions at this circuit' : 'Select session',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
        const SizedBox(height: 12),

        // Lap picker
        if (_selectedSessionId != null)
          DropdownButtonFormField<String>(
            initialValue: _selectedLapId,
            decoration: const InputDecoration(labelText: 'Lap'),
            items: _laps
                .map((l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(
                        'Lap ${l.lapNumber} — ${FormatUtils.formatLapTime(l.durationMs)}',
                      ),
                    ))
                .toList(),
            onChanged: _onLapSelected,
            hint: Text(
              _laps.isEmpty ? 'No laps with GPS trace' : 'Select lap',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _buildMapWithSlider() {
    final startPoint = _pointAtFraction(_sliderRange.start);
    final endPoint = _pointAtFraction(_sliderRange.end);
    final segmentPts = _segmentPoints();
    final bounds = boundsFromPoints(_tracePoints);

    return Column(
      children: [
        // Map
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: SizedBox(
            height: 280,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCameraFit: bounds != null
                    ? CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(24),
                      )
                    : null,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.laptime.laptime',
                  maxZoom: 19,
                ),

                // Full trace — faded grey
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _tracePoints,
                      color: AppColors.textTertiary.withValues(alpha: 0.35),
                      strokeWidth: 3,
                    ),
                  ],
                ),

                // Highlighted segment — thick purple
                if (segmentPts.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: segmentPts,
                        color: AppColors.purple,
                        strokeWidth: 4.5,
                      ),
                    ],
                  ),

                // Start (green) and end (red) markers
                MarkerLayer(
                  markers: [
                    Marker(
                      point: startPoint,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.white, width: 2.5),
                        ),
                      ),
                    ),
                    Marker(
                      point: endPoint,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.white, width: 2.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Slider labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('Start', style: AppTypography.labelMedium),
              ],
            ),
            Row(
              children: [
                Text('End', style: AppTypography.labelMedium),
                const SizedBox(width: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Range slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.purple,
            inactiveTrackColor: AppColors.ghost,
            thumbColor: AppColors.purple,
            overlayColor: AppColors.purple.withValues(alpha: 0.12),
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 10,
            ),
            trackHeight: 4,
          ),
          child: RangeSlider(
            values: _sliderRange,
            min: 0.0,
            max: 1.0,
            onChanged: (values) {
              // Enforce minimum gap so start < end
              if ((values.end - values.start) >= 0.02) {
                setState(() => _sliderRange = values);
              }
            },
          ),
        ),

        // Position percentages
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(_sliderRange.start * 100).round()}%',
                style: AppTypography.bodySmall,
              ),
              Text(
                '${(_sliderRange.end * 100).round()}%',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveSection() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Sector Name',
            hintText: 'e.g. S1 — Copse to Maggotts',
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Text('Save Sector'),
          ),
        ),
      ],
    );
  }

}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../data/circuit_repository.dart';

/// Screen for defining a new circuit: name it and drop the two endpoints
/// of the start/finish line on the map.
///
/// The line should span the track width at the start/finish point —
/// automatic lap detection triggers when the GPS trace crosses it.
/// Pops with the created [LocalCircuit] on save.
class CircuitCreateScreen extends ConsumerStatefulWidget {
  const CircuitCreateScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  /// Map starting position (the user's current location).
  final double initialLat;
  final double initialLng;

  @override
  ConsumerState<CircuitCreateScreen> createState() =>
      _CircuitCreateScreenState();
}

class _CircuitCreateScreenState extends ConsumerState<CircuitCreateScreen> {
  final _nameController = TextEditingController();
  LatLng? _lineStart;
  LatLng? _lineEnd;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      if (_lineStart == null || _lineEnd != null) {
        _lineStart = point;
        _lineEnd = null;
      } else {
        _lineEnd = point;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _lineStart == null || _lineEnd == null || _saving) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final start = _lineStart!;
      final end = _lineEnd!;
      final circuit = await ref.read(circuitRepositoryProvider).createCircuit(
        userId: user.id,
        name: name,
        gpsLat: (start.latitude + end.latitude) / 2,
        gpsLng: (start.longitude + end.longitude) / 2,
        startFinishLine: [
          [start.latitude, start.longitude],
          [end.latitude, end.longitude],
        ],
      );
      if (mounted) Navigator.of(context).pop(circuit);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save circuit: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty &&
        _lineStart != null &&
        _lineEnd != null;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('New Circuit'),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Circuit Name',
                  hintText: 'e.g. Brands Hatch Indy',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.flag,
                      size: 16, color: AppColors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lineStart == null
                          ? 'Tap the map on one side of the start/finish line'
                          : _lineEnd == null
                              ? 'Now tap the other side of the track'
                              : 'Start/finish line set — tap again to redo',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter:
                          LatLng(widget.initialLat, widget.initialLng),
                      initialZoom: 16,
                      onTap: _onMapTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.laptime.laptime',
                        maxZoom: 19,
                      ),
                      if (_lineStart != null && _lineEnd != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: [_lineStart!, _lineEnd!],
                              color: AppColors.red,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          for (final point in [_lineStart, _lineEnd])
                            if (point != null)
                              Marker(
                                point: point,
                                width: 16,
                                height: 16,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: canSave && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Save Circuit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

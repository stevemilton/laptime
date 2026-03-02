import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Parses a JSON trace string into a list of [LatLng] points.
///
/// Supports two formats:
/// - Array of objects: `[{"lat": 51.38, "lng": -0.53}, ...]`
/// - Array of arrays: `[[lng, lat], ...]` (GeoJSON order)
List<LatLng> parseTraceJson(String? traceJson) {
  if (traceJson == null || traceJson.isEmpty) return [];
  try {
    final decoded = jsonDecode(traceJson) as List<dynamic>;
    if (decoded.isEmpty) return [];

    // Detect format from first element
    final first = decoded.first;
    if (first is Map) {
      return decoded.map((e) {
        final m = e as Map<String, dynamic>;
        final lat = (m['lat'] ?? m['latitude']) as num;
        final lng = (m['lng'] ?? m['longitude']) as num;
        return LatLng(lat.toDouble(), lng.toDouble());
      }).toList();
    } else if (first is List) {
      // GeoJSON order: [lng, lat]
      return decoded.map((e) {
        final arr = e as List<dynamic>;
        return LatLng(
          (arr[1] as num).toDouble(),
          (arr[0] as num).toDouble(),
        );
      }).toList();
    }
  } catch (_) {
    // Silently fail — return empty
  }
  return [];
}

/// Computes the [LatLngBounds] that encloses all given points,
/// with a small padding factor.
LatLngBounds? boundsFromPoints(List<LatLng> points) {
  if (points.isEmpty) return null;

  double minLat = points.first.latitude;
  double maxLat = points.first.latitude;
  double minLng = points.first.longitude;
  double maxLng = points.first.longitude;

  for (final p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }

  // Add a small padding (approx 10% of the range)
  final latPad = (maxLat - minLat) * 0.12 + 0.0005;
  final lngPad = (maxLng - minLng) * 0.12 + 0.0005;

  return LatLngBounds(
    LatLng(minLat - latPad, minLng - lngPad),
    LatLng(maxLat + latPad, maxLng + lngPad),
  );
}

/// A reusable OpenStreetMap widget that displays one or two GPS trace
/// polylines. Used on lap detail, session detail, and lap comparison screens.
///
/// When [trace2] is provided, two overlaid polylines are shown (for
/// comparison). The map auto-fits to the combined bounds.
class TraceMap extends StatelessWidget {
  const TraceMap({
    super.key,
    required this.trace1,
    this.trace2,
    this.color1 = AppColors.purple,
    this.color2 = AppColors.green,
    this.height = 220,
    this.strokeWidth = 3.0,
    this.showStartFinish = true,
    this.interactive = true,
  });

  /// Primary GPS trace as [LatLng] points.
  final List<LatLng> trace1;

  /// Optional second trace for overlay comparison.
  final List<LatLng>? trace2;

  /// Colour of the primary trace line.
  final Color color1;

  /// Colour of the comparison trace line.
  final Color color2;

  /// Map container height.
  final double height;

  /// Polyline stroke width.
  final double strokeWidth;

  /// Whether to show start/finish markers.
  final bool showStartFinish;

  /// Whether the map supports pan/zoom gestures.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    // Combine all points to compute bounds
    final allPoints = [...trace1, ...?trace2];
    final bounds = boundsFromPoints(allPoints);

    if (bounds == null || trace1.isEmpty) {
      return _emptyState();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(16),
            ),
            interactionOptions: InteractionOptions(
              flags: interactive
                  ? InteractiveFlag.all
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            // OpenStreetMap tile layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.laptime.laptime',
              maxZoom: 19,
            ),

            // Polyline layer
            PolylineLayer(
              polylines: [
                // Second trace first (underneath)
                if (trace2 != null && trace2!.isNotEmpty)
                  Polyline(
                    points: trace2!,
                    color: color2.withValues(alpha: 0.7),
                    strokeWidth: strokeWidth,
                  ),
                // Primary trace on top
                Polyline(
                  points: trace1,
                  color: color1,
                  strokeWidth: strokeWidth,
                ),
              ],
            ),

            // Start / finish markers
            if (showStartFinish)
              MarkerLayer(
                markers: [
                  // Start marker (green circle)
                  if (trace1.isNotEmpty)
                    Marker(
                      point: trace1.first,
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  // Finish marker (red circle)
                  if (trace1.length > 1)
                    Marker(
                      point: trace1.last,
                      width: 14,
                      height: 14,
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
    );
  }

  Widget _emptyState() {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.ghost,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 32, color: AppColors.textTertiary),
            SizedBox(height: 8),
            Text(
              'No GPS trace data',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// A map widget for sector creation that supports tap-to-place markers.
///
/// Calls [onStartPointSet] and [onEndPointSet] when the user taps the map.
class SectorMap extends StatefulWidget {
  const SectorMap({
    super.key,
    this.circuitLat,
    this.circuitLng,
    this.startPoint,
    this.endPoint,
    this.onStartPointSet,
    this.onEndPointSet,
    this.height = 220,
  });

  final double? circuitLat;
  final double? circuitLng;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final ValueChanged<LatLng>? onStartPointSet;
  final ValueChanged<LatLng>? onEndPointSet;
  final double height;

  @override
  State<SectorMap> createState() => _SectorMapState();
}

class _SectorMapState extends State<SectorMap> {
  /// false = next tap sets start, true = next tap sets end
  bool _settingEnd = false;

  @override
  Widget build(BuildContext context) {
    final center = (widget.circuitLat != null && widget.circuitLng != null)
        ? LatLng(widget.circuitLat!, widget.circuitLng!)
        : const LatLng(52.07, -1.02); // Default: Silverstone area

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode indicator row
        Row(
          children: [
            _modeChip(
              'Set Start',
              AppColors.green,
              !_settingEnd,
              () => setState(() => _settingEnd = false),
            ),
            const SizedBox(width: 8),
            _modeChip(
              'Set End',
              AppColors.red,
              _settingEnd,
              () => setState(() => _settingEnd = true),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // The map
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: SizedBox(
            height: widget.height,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                onTap: _handleTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.laptime.laptime',
                  maxZoom: 19,
                ),
                // Markers for start/end
                MarkerLayer(
                  markers: [
                    if (widget.startPoint != null)
                      Marker(
                        point: widget.startPoint!,
                        width: 18,
                        height: 18,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    if (widget.endPoint != null)
                      Marker(
                        point: widget.endPoint!,
                        width: 18,
                        height: 18,
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
                // Line between start and end if both set
                if (widget.startPoint != null && widget.endPoint != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [widget.startPoint!, widget.endPoint!],
                        color: AppColors.purple,
                        strokeWidth: 2,
                        pattern: const StrokePattern.dotted(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(TapPosition tapPos, LatLng point) {
    if (_settingEnd) {
      widget.onEndPointSet?.call(point);
      // After setting end, cycle back to start
      setState(() => _settingEnd = false);
    } else {
      widget.onStartPointSet?.call(point);
      // After setting start, auto-switch to end
      setState(() => _settingEnd = true);
    }
  }

  Widget _modeChip(
      String label, Color color, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : AppColors.ghost,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active ? color : AppColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? color : AppColors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

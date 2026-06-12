import 'dart:convert';
import 'dart:math';

import '../services/location_service.dart';
import 'geo_utils.dart';

/// A decoded GPS trace point.
///
/// [tMs] is milliseconds since lap start (null for legacy v1 traces that
/// stored only coordinates). [speedMps] is the GPS Doppler speed in m/s
/// (null for legacy traces).
class TracePoint {
  const TracePoint({
    required this.lat,
    required this.lng,
    this.tMs,
    this.speedMps,
  });

  final double lat;
  final double lng;
  final double? tMs;
  final double? speedMps;
}

/// Encoder/decoder for lap GPS traces.
///
/// Trace format v2: a JSON array of `[lng, lat, tMs, speedMps]` entries,
/// where tMs is milliseconds since lap start. The decoder also accepts the
/// legacy v1 format (`[lng, lat]` pairs) and map-shaped points.
abstract final class TraceCodec {
  /// Build the JSON-encodable v2 representation of a lap trace.
  ///
  /// Coordinates are rounded to 6 decimal places (~0.11 m) and speed to
  /// 2 decimals to keep payloads compact.
  static List<List<num>> toJsonList(List<GpsPoint> points, DateTime lapStart) {
    return points
        .map((p) => <num>[
              _round(p.longitude, 6),
              _round(p.latitude, 6),
              max(0, p.timestamp.difference(lapStart).inMilliseconds),
              _round(p.speed < 0 ? 0 : p.speed, 2),
            ])
        .toList();
  }

  /// Encode a lap trace to its stored string form.
  static String encode(List<GpsPoint> points, DateTime lapStart) {
    return jsonEncode(toJsonList(points, lapStart));
  }

  /// Decode a stored trace (v1 or v2, array or map entries) into points.
  /// Returns an empty list for null/invalid input.
  static List<TracePoint> decode(String? traceJson) {
    if (traceJson == null || traceJson.isEmpty) return [];
    try {
      final decoded = jsonDecode(traceJson);
      if (decoded is! List) return [];
      final points = <TracePoint>[];
      for (final entry in decoded) {
        if (entry is List && entry.length >= 2) {
          points.add(TracePoint(
            lng: (entry[0] as num).toDouble(),
            lat: (entry[1] as num).toDouble(),
            tMs: entry.length > 2 ? (entry[2] as num?)?.toDouble() : null,
            speedMps: entry.length > 3 ? (entry[3] as num?)?.toDouble() : null,
          ));
        } else if (entry is Map) {
          final lat = entry['lat'] ?? entry['latitude'];
          final lng = entry['lng'] ?? entry['longitude'];
          if (lat is num && lng is num) {
            points.add(TracePoint(
              lat: lat.toDouble(),
              lng: lng.toDouble(),
              tMs: (entry['timestamp'] as num?)?.toDouble(),
              speedMps: (entry['speed'] as num?)?.toDouble(),
            ));
          }
        }
      }
      return points;
    } catch (_) {
      return [];
    }
  }

  /// Whether a decoded trace carries usable per-point timestamps.
  static bool hasTimestamps(List<TracePoint> trace) {
    if (trace.length < 2) return false;
    final first = trace.first.tMs;
    final last = trace.last.tMs;
    return first != null && last != null && last > first;
  }

  /// Ensure a trace has monotonic per-point timestamps.
  ///
  /// Legacy v1 traces have no timestamps; when [lapDurationMs] is known we
  /// synthesise them by allocating the lap time proportionally to distance
  /// travelled. This is what lets pre-v2 laps be scored against sectors.
  static List<TracePoint> withTimestamps(
    List<TracePoint> trace,
    int lapDurationMs,
  ) {
    if (trace.length < 2) return trace;
    if (hasTimestamps(trace)) return trace;

    final cumulative = List<double>.filled(trace.length, 0);
    for (var i = 1; i < trace.length; i++) {
      cumulative[i] = cumulative[i - 1] +
          GeoUtils.distanceMeters(
            trace[i - 1].lat,
            trace[i - 1].lng,
            trace[i].lat,
            trace[i].lng,
          );
    }
    final total = cumulative.last;
    if (total <= 0) return trace;

    return [
      for (var i = 0; i < trace.length; i++)
        TracePoint(
          lat: trace[i].lat,
          lng: trace[i].lng,
          tMs: lapDurationMs * cumulative[i] / total,
          speedMps: trace[i].speedMps,
        ),
    ];
  }

  /// Cumulative distance (meters) at each trace point.
  static List<double> cumulativeDistances(List<TracePoint> trace) {
    final out = List<double>.filled(trace.length, 0);
    for (var i = 1; i < trace.length; i++) {
      out[i] = out[i - 1] +
          GeoUtils.distanceMeters(
            trace[i - 1].lat,
            trace[i - 1].lng,
            trace[i].lat,
            trace[i].lng,
          );
    }
    return out;
  }

  static double _round(double value, int places) {
    final factor = pow(10, places);
    return (value * factor).roundToDouble() / factor;
  }
}

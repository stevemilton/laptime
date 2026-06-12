import '../services/location_service.dart';
import '../utils/geo_utils.dart';
import '../constants/app_constants.dart';

/// Result of a start/finish line crossing detection.
class LineCrossing {
  LineCrossing({
    required this.crossingTime,
    required this.crossingLat,
    required this.crossingLng,
  });

  final DateTime crossingTime;
  final double crossingLat;
  final double crossingLng;
}

/// Pure-geometry lap detection via start/finish line crossing.
///
/// The start/finish line is defined as a short line segment perpendicular
/// to the track at the start/finish point. When two consecutive GPS points
/// fall on opposite sides of this line, a lap crossing is detected.
///
/// Requirements:
/// - Minimum ±[AppConstants.startFinishToleranceM] from the line before
///   allowing another crossing (prevents double-counting).
/// - Ignores crossings when GPS accuracy exceeds threshold.
class LapDetectionService {
  /// Start/finish line endpoints (set from circuit data).
  double? _sfLat1, _sfLng1, _sfLat2, _sfLng2;

  /// Previous GPS point for segment crossing detection.
  GpsPoint? _previousPoint;

  /// Timestamp of last detected crossing (debounce).
  DateTime? _lastCrossingTime;

  /// Minimum time between crossings (prevents double-triggers).
  static const _minCrossingInterval = Duration(seconds: 10);

  /// Whether we've moved far enough from the line to allow another crossing.
  bool _hasMovedAway = true;

  /// Whether a start/finish line is configured (automatic detection active).
  bool get isArmed => _sfLat1 != null;

  /// Configure the start/finish line.
  ///
  /// [lat1, lng1] to [lat2, lng2] defines the line segment.
  void setStartFinishLine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    _sfLat1 = lat1;
    _sfLng1 = lng1;
    _sfLat2 = lat2;
    _sfLng2 = lng2;
    _previousPoint = null;
    _lastCrossingTime = null;
    _hasMovedAway = true;
  }

  /// Process a new GPS point and check for start/finish line crossing.
  ///
  /// Returns a [LineCrossing] if the car has crossed the line, null otherwise.
  LineCrossing? processPoint(GpsPoint point) {
    // No line configured
    if (_sfLat1 == null) return null;

    // Skip if GPS accuracy is too poor
    if (point.accuracy > AppConstants.gpsMinAccuracyMeters) {
      _previousPoint = point;
      return null;
    }

    final prev = _previousPoint;
    _previousPoint = point;

    if (prev == null) return null;

    // Check if we've moved away from the line (anti-bounce)
    final distToLine = GeoUtils.distanceToLineSegment(
      point.latitude,
      point.longitude,
      _sfLat1!,
      _sfLng1!,
      _sfLat2!,
      _sfLng2!,
    );

    if (distToLine > AppConstants.startFinishToleranceMeters) {
      _hasMovedAway = true;
    }

    if (!_hasMovedAway) return null;

    // Check for line segment intersection
    final crossing = GeoUtils.lineSegmentIntersection(
      prev.latitude,
      prev.longitude,
      point.latitude,
      point.longitude,
      _sfLat1!,
      _sfLng1!,
      _sfLat2!,
      _sfLng2!,
    );

    if (crossing == null) return null;

    // Debounce check
    final now = point.timestamp;
    if (_lastCrossingTime != null &&
        now.difference(_lastCrossingTime!) < _minCrossingInterval) {
      return null;
    }

    // Valid crossing detected
    _lastCrossingTime = now;
    _hasMovedAway = false;

    // Interpolate the exact crossing time
    final totalDist = GeoUtils.distanceMeters(
      prev.latitude,
      prev.longitude,
      point.latitude,
      point.longitude,
    );
    final crossDist = GeoUtils.distanceMeters(
      prev.latitude,
      prev.longitude,
      crossing.lat,
      crossing.lng,
    );
    final fraction = totalDist > 0 ? crossDist / totalDist : 0.5;
    final timeDelta = point.timestamp.difference(prev.timestamp);
    final crossingTime = prev.timestamp.add(
      Duration(microseconds: (timeDelta.inMicroseconds * fraction).round()),
    );

    return LineCrossing(
      crossingTime: crossingTime,
      crossingLat: crossing.lat,
      crossingLng: crossing.lng,
    );
  }

  /// Reset state for a new session.
  void reset() {
    _previousPoint = null;
    _lastCrossingTime = null;
    _hasMovedAway = true;
  }
}

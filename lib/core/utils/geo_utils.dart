import 'dart:math';
import '../services/location_service.dart';

/// Pure geometry utilities for GPS calculations.
///
/// All calculations use simple 2D geometry projected from lat/lng,
/// which is accurate enough for the small areas of a race circuit.
abstract final class GeoUtils {
  /// Haversine distance between two GPS coordinates in meters.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Check if a line segment (from p1 to p2) crosses another line segment
  /// (from p3 to p4). Used for start/finish line detection.
  ///
  /// Returns the intersection point if they cross, null otherwise.
  static ({double lat, double lng})? lineSegmentIntersection(
    double p1Lat,
    double p1Lng,
    double p2Lat,
    double p2Lng,
    double p3Lat,
    double p3Lng,
    double p4Lat,
    double p4Lng,
  ) {
    final d1x = p2Lng - p1Lng;
    final d1y = p2Lat - p1Lat;
    final d2x = p4Lng - p3Lng;
    final d2y = p4Lat - p3Lat;

    final cross = d1x * d2y - d1y * d2x;
    if (cross.abs() < 1e-12) return null; // parallel

    final t = ((p3Lng - p1Lng) * d2y - (p3Lat - p1Lat) * d2x) / cross;
    final u = ((p3Lng - p1Lng) * d1y - (p3Lat - p1Lat) * d1x) / cross;

    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
      return (
        lat: p1Lat + t * d1y,
        lng: p1Lng + t * d1x,
      );
    }

    return null;
  }

  /// Minimum distance from a point to a line segment, in meters.
  ///
  /// Used for proximity checks to start/finish lines.
  static double distanceToLineSegment(
    double pointLat,
    double pointLng,
    double lineLat1,
    double lineLng1,
    double lineLat2,
    double lineLng2,
  ) {
    final dx = lineLng2 - lineLng1;
    final dy = lineLat2 - lineLat1;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) {
      return distanceMeters(pointLat, pointLng, lineLat1, lineLng1);
    }

    var t = ((pointLng - lineLng1) * dx + (pointLat - lineLat1) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);

    final projLat = lineLat1 + t * dy;
    final projLng = lineLng1 + t * dx;

    return distanceMeters(pointLat, pointLng, projLat, projLng);
  }

  /// Convert a list of GpsPoints to a GeoJSON LineString coordinate array.
  static List<List<double>> toLineStringCoords(List<GpsPoint> points) {
    return points.map((p) => [p.longitude, p.latitude]).toList();
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}

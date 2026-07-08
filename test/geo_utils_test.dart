import 'package:flutter_test/flutter_test.dart';
import 'package:laptime/core/utils/geo_utils.dart';

void main() {
  group('distanceMeters', () {
    test('zero for identical points', () {
      expect(GeoUtils.distanceMeters(52, -1, 52, -1), 0);
    });

    test('one degree of longitude at the equator is ~111.32 km', () {
      expect(GeoUtils.distanceMeters(0, 0, 0, 1), closeTo(111320, 200));
    });

    test('longitude distance shrinks with latitude', () {
      final atEquator = GeoUtils.distanceMeters(0, 0, 0, 0.001);
      final at60North = GeoUtils.distanceMeters(60, 0, 60, 0.001);
      expect(at60North, closeTo(atEquator / 2, 1));
    });
  });

  group('lineSegmentIntersection', () {
    test('crossing segments intersect at the expected point', () {
      final p = GeoUtils.lineSegmentIntersection(
        -1, 0, 1, 0, // vertical through origin (lat varies)
        0, -1, 0, 1, // horizontal through origin (lng varies)
      );
      expect(p, isNotNull);
      expect(p!.lat, closeTo(0, 1e-12));
      expect(p.lng, closeTo(0, 1e-12));
    });

    test('non-crossing segments return null', () {
      final p = GeoUtils.lineSegmentIntersection(
        0, 0, 1, 0,
        2, 1, 3, 1,
      );
      expect(p, isNull);
    });

    test('parallel segments return null', () {
      final p = GeoUtils.lineSegmentIntersection(
        0, 0, 1, 0,
        0, 0.001, 1, 0.001,
      );
      expect(p, isNull);
    });

    test('segments that would intersect beyond their ends return null', () {
      final p = GeoUtils.lineSegmentIntersection(
        0, 0, 0.4, 0,
        0.5, -1, 0.5, 1,
      );
      expect(p, isNull);
    });
  });

  group('distanceToLineSegment', () {
    test('perpendicular distance to a segment', () {
      // Point 0.001 deg north of an east-west segment at the equator.
      final d = GeoUtils.distanceToLineSegment(0.001, 0.5, 0, 0, 0, 1);
      expect(d, closeTo(111, 5));
    });

    test('clamps to segment endpoints', () {
      final d = GeoUtils.distanceToLineSegment(0, 2, 0, 0, 0, 1);
      // Closest point is the (0,1) endpoint, one degree away.
      expect(d, closeTo(111320, 200));
    });
  });

  group('extendLineSegment', () {
    test('extends both endpoints along the line direction', () {
      // North-south segment at the equator: 0.0002 deg lat ≈ 22.26 m long.
      final g = GeoUtils.extendLineSegment(-0.0001, 0, 0.0001, 0, 10);
      // Each endpoint should move ~10 m (≈ 0.0000898 deg) outward.
      expect(g.lat1, closeTo(-0.0001 - 0.0000898, 5e-6));
      expect(g.lat2, closeTo(0.0001 + 0.0000898, 5e-6));
      expect(g.lng1, closeTo(0, 1e-9));
      expect(g.lng2, closeTo(0, 1e-9));
    });

    test('degenerate zero-length segment is returned unchanged', () {
      final g = GeoUtils.extendLineSegment(0.5, 0.5, 0.5, 0.5, 10);
      expect(g.lat1, 0.5);
      expect(g.lng1, 0.5);
      expect(g.lat2, 0.5);
      expect(g.lng2, 0.5);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:laptime/core/services/location_service.dart';
import 'package:laptime/core/utils/trace_codec.dart';

GpsPoint _point(double lat, double lng, int tMs, double speed) {
  final start = DateTime(2026, 1, 1, 12, 0, 0);
  return GpsPoint(
    latitude: lat,
    longitude: lng,
    altitude: 100,
    accuracy: 5,
    speed: speed,
    heading: 0,
    timestamp: start.add(Duration(milliseconds: tMs)),
  );
}

void main() {
  final lapStart = DateTime(2026, 1, 1, 12, 0, 0);

  group('TraceCodec.encode/decode', () {
    test('round-trips v2 traces with timestamps and speed', () {
      final points = [
        _point(52.0701, -1.0170, 0, 31.5),
        _point(52.0705, -1.0160, 1000, 42.25),
        _point(52.0710, -1.0150, 2000, 55.0),
      ];

      final encoded = TraceCodec.encode(points, lapStart);
      final decoded = TraceCodec.decode(encoded);

      expect(decoded.length, 3);
      expect(decoded[0].lat, closeTo(52.0701, 1e-6));
      expect(decoded[0].lng, closeTo(-1.0170, 1e-6));
      expect(decoded[0].tMs, 0);
      expect(decoded[0].speedMps, closeTo(31.5, 0.01));
      expect(decoded[1].tMs, 1000);
      expect(decoded[2].speedMps, closeTo(55.0, 0.01));
      expect(TraceCodec.hasTimestamps(decoded), isTrue);
    });

    test('clamps negative GPS speeds to zero', () {
      final encoded = TraceCodec.encode([_point(52, -1, 0, -1)], lapStart);
      final decoded = TraceCodec.decode(encoded);
      expect(decoded.single.speedMps, 0);
    });

    test('decodes legacy v1 [lng,lat] traces without timestamps', () {
      const legacy = '[[-1.017,52.0701],[-1.016,52.0705]]';
      final decoded = TraceCodec.decode(legacy);

      expect(decoded.length, 2);
      expect(decoded[0].lng, closeTo(-1.017, 1e-9));
      expect(decoded[0].lat, closeTo(52.0701, 1e-9));
      expect(decoded[0].tMs, isNull);
      expect(decoded[0].speedMps, isNull);
      expect(TraceCodec.hasTimestamps(decoded), isFalse);
    });

    test('decodes map-shaped points', () {
      const json =
          '[{"lat":52.1,"lng":-1.1,"timestamp":500},{"lat":52.2,"lng":-1.2}]';
      final decoded = TraceCodec.decode(json);
      expect(decoded.length, 2);
      expect(decoded[0].tMs, 500);
      expect(decoded[1].lat, 52.2);
    });

    test('returns empty list for null/garbage input', () {
      expect(TraceCodec.decode(null), isEmpty);
      expect(TraceCodec.decode(''), isEmpty);
      expect(TraceCodec.decode('not json'), isEmpty);
      expect(TraceCodec.decode('{"a":1}'), isEmpty);
    });
  });

  group('TraceCodec.withTimestamps', () {
    test('synthesises distance-proportional timestamps for legacy traces',
        () {
      // Three points in a straight line; second leg is twice the first.
      const legacy =
          '[[0.0,0.0],[0.001,0.0],[0.003,0.0]]'; // lng spacing 1:2
      final trace = TraceCodec.decode(legacy);
      final upgraded = TraceCodec.withTimestamps(trace, 90000);

      expect(TraceCodec.hasTimestamps(upgraded), isTrue);
      expect(upgraded.first.tMs, 0);
      expect(upgraded.last.tMs, closeTo(90000, 0.001));
      // 1/3 of the distance -> 1/3 of the lap time.
      expect(upgraded[1].tMs!, closeTo(30000, 1));
    });

    test('leaves traces that already have timestamps untouched', () {
      const v2 = '[[0.0,0.0,0,10],[0.001,0.0,5000,12]]';
      final trace = TraceCodec.decode(v2);
      final result = TraceCodec.withTimestamps(trace, 99999);
      expect(result[1].tMs, 5000);
    });
  });

  group('TraceCodec.cumulativeDistances', () {
    test('accumulates haversine distances', () {
      const json = '[[0.0,0.0],[0.001,0.0],[0.002,0.0]]';
      final trace = TraceCodec.decode(json);
      final dist = TraceCodec.cumulativeDistances(trace);

      expect(dist.first, 0);
      // 0.001 deg longitude at the equator is ~111.32 m.
      expect(dist[1], closeTo(111.3, 0.5));
      expect(dist[2], closeTo(222.6, 1.0));
    });
  });
}

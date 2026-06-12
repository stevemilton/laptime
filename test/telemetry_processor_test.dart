import 'package:flutter_test/flutter_test.dart';
import 'package:laptime/core/services/sensor_service.dart';
import 'package:laptime/core/utils/trace_codec.dart';
import 'package:laptime/features/telemetry/data/telemetry_processor.dart';

LapSensorSnapshot _snapshot({
  required List<double> timestamps,
  List<double>? accelX,
  List<double>? accelY,
}) {
  final n = timestamps.length;
  return LapSensorSnapshot(
    timestamps: timestamps,
    accelX: accelX ?? List.filled(n, 0),
    accelY: accelY ?? List.filled(n, 0),
    accelZ: List.filled(n, 0),
    gyroX: List.filled(n, 0),
    gyroY: List.filled(n, 0),
    gyroZ: List.filled(n, 0),
    magHeading: List.filled(n, 0),
    baroPressure: List.filled(n, 1013),
  );
}

void main() {
  group('processSensorData', () {
    test('converts acceleration to g', () {
      final t = TelemetryProcessor.processSensorData(_snapshot(
        timestamps: [0, 0.02, 0.04],
        accelX: [9.80665, 0, -9.80665],
      ));
      expect(t.lateralG[0], closeTo(1.0, 1e-6));
      expect(t.lateralG[1], 0);
      expect(t.lateralG[2], closeTo(-1.0, 1e-6));
    });

    test('speed channel interpolates GPS speed onto the sensor timeline',
        () {
      // Trace: 10 m/s at t=0, 20 m/s at t=2s.
      final trace = TraceCodec.decode('[[0,0,0,10],[0.001,0,2000,20]]');
      final t = TelemetryProcessor.processSensorData(
        _snapshot(timestamps: [0, 1, 2]),
        trace: trace,
      );

      expect(t.hasSpeed, isTrue);
      expect(t.speed[0], closeTo(10 * 3.6, 0.01));
      expect(t.speed[1], closeTo(15 * 3.6, 0.01)); // midpoint
      expect(t.speed[2], closeTo(20 * 3.6, 0.01));
    });

    test('no speed channel without trace speed data (legacy laps)', () {
      final trace = TraceCodec.decode('[[0,0],[0.001,0]]');
      final t = TelemetryProcessor.processSensorData(
        _snapshot(timestamps: [0, 1, 2]),
        trace: trace,
      );
      expect(t.hasSpeed, isFalse);
      expect(t.speed, isEmpty);
    });

    test('handles empty snapshots', () {
      final t = TelemetryProcessor.processSensorData(
          _snapshot(timestamps: []));
      expect(t.sampleCount, 0);
      expect(t.speed, isEmpty);
    });
  });

  group('computeTimeDelta', () {
    test('constant offset between two laps over the same path', () {
      // Same geometry; lap 2 is uniformly 10% slower.
      final lap1 = TraceCodec.decode(
          '[[0,0,0,20],[0.001,0,5000,20],[0.002,0,10000,20]]');
      final lap2 = TraceCodec.decode(
          '[[0,0,0,18],[0.001,0,5500,18],[0.002,0,11000,18]]');

      final delta = TelemetryProcessor.computeTimeDelta(lap1, lap2);
      expect(delta, isNotEmpty);
      expect(delta.first.deltaMs, 0);
      expect(delta.last.deltaMs, closeTo(1000, 1));
      // Halfway by distance: 500 ms behind.
      final mid = delta[delta.length ~/ 2];
      expect(mid.deltaMs, closeTo(500, 10));
    });

    test('returns empty without timestamps', () {
      final lap1 = TraceCodec.decode('[[0,0],[0.001,0]]');
      final lap2 = TraceCodec.decode('[[0,0,0,1],[0.001,0,1000,1]]');
      expect(TelemetryProcessor.computeTimeDelta(lap1, lap2), isEmpty);
    });
  });

  group('computeGGData', () {
    test('downsamples points', () {
      final t = TelemetryProcessor.processSensorData(_snapshot(
        timestamps: List.generate(100, (i) => i * 0.02),
      ));
      final gg = TelemetryProcessor.computeGGData(t, downsample: 10);
      expect(gg.length, 10);
    });
  });

  group('traceSpeedSeries', () {
    test('extracts km/h series from v2 traces', () {
      final trace = TraceCodec.decode('[[0,0,0,10],[0.001,0,1000,30]]');
      final (ts, speed) = TelemetryProcessor.traceSpeedSeries(trace);
      expect(ts, [0, 1]);
      expect(speed[0], closeTo(36, 0.01));
      expect(speed[1], closeTo(108, 0.01));
    });
  });
}

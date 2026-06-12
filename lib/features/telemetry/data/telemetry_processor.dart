import 'dart:math';

import '../../../core/services/sensor_service.dart';
import '../../../core/utils/trace_codec.dart';

/// Processed telemetry data derived from raw sensor readings for one lap.
///
/// Contains time-aligned channels ready for charting and comparison.
class ProcessedTelemetry {
  ProcessedTelemetry({
    required this.timestamps,
    required this.lateralG,
    required this.longitudinalG,
    required this.speed,
    required this.yawRate,
    required this.baroPressure,
  });

  /// Elapsed time in seconds from lap start for each sample.
  final List<double> timestamps;

  /// Lateral acceleration in g (positive = right turn).
  /// Derived from the gravity-removed user accelerometer X axis.
  final List<double> lateralG;

  /// Longitudinal acceleration in g (positive = braking, negative = accel).
  /// Derived from the gravity-removed user accelerometer Y axis.
  final List<double> longitudinalG;

  /// Speed in km/h from GPS Doppler readings, interpolated onto the sensor
  /// timeline. Empty when the lap's trace has no speed data (pre-v2 laps).
  final List<double> speed;

  /// Yaw rate in degrees/second from gyroscope Z axis.
  final List<double> yawRate;

  /// Barometric pressure in hPa.
  final List<double> baroPressure;

  /// Total elapsed time of the lap in seconds.
  double get totalTime =>
      timestamps.isNotEmpty ? timestamps.last - timestamps.first : 0;

  /// Number of data samples.
  int get sampleCount => timestamps.length;

  bool get hasSpeed => speed.isNotEmpty;
}

/// A single point on a G-G (friction circle) diagram.
class GGPoint {
  const GGPoint({
    required this.lateralG,
    required this.longitudinalG,
  });

  /// Lateral acceleration in g (x-axis on the diagram).
  final double lateralG;

  /// Longitudinal acceleration in g (y-axis on the diagram).
  final double longitudinalG;

  /// Combined G magnitude.
  double get magnitude => sqrt(lateralG * lateralG + longitudinalG * longitudinalG);
}

/// A single point in a time-delta trace between two laps.
class DeltaPoint {
  const DeltaPoint({
    required this.distance,
    required this.deltaMs,
  });

  /// Progress through the lap, normalised 0..1 by distance.
  final double distance;

  /// Time delta in milliseconds.
  /// Positive = lap2 is slower, negative = lap2 is faster.
  final int deltaMs;
}

/// Static utilities to transform raw [LapSensorSnapshot] data into
/// presentation-ready telemetry models.
abstract final class TelemetryProcessor {
  static const double _gravity = 9.80665; // m/s^2

  /// Convert raw sensor arrays into unified, time-aligned channels.
  ///
  /// Accelerometer values are gravity-removed linear acceleration in m/s²
  /// and are converted to g. Speed comes from the lap's GPS [trace]
  /// (Doppler speed per point), interpolated onto the sensor timeline —
  /// never integrated from acceleration, which drifts unusably within
  /// seconds.
  static ProcessedTelemetry processSensorData(
    LapSensorSnapshot snapshot, {
    List<TracePoint>? trace,
  }) {
    final n = snapshot.timestamps.length;
    if (n == 0) {
      return ProcessedTelemetry(
        timestamps: [],
        lateralG: [],
        longitudinalG: [],
        speed: [],
        yawRate: [],
        baroPressure: [],
      );
    }

    // Normalise timestamps so first sample is t=0
    final t0 = snapshot.timestamps.first;
    final timestamps = snapshot.timestamps.map((t) => t - t0).toList();

    // Convert accelerometer from m/s^2 to g.
    // X axis -> lateral, Y axis -> longitudinal (phone mounted landscape).
    final lateralG = List<double>.generate(
      min(n, snapshot.accelX.length),
      (i) => snapshot.accelX[i] / _gravity,
    );

    final longitudinalG = List<double>.generate(
      min(n, snapshot.accelY.length),
      (i) => snapshot.accelY[i] / _gravity,
    );

    final speed = trace != null
        ? gpsSpeedChannel(trace, timestamps)
        : <double>[];

    // Yaw rate from gyroscope Z axis (rad/s -> degrees/s)
    final yawRate = List<double>.generate(
      min(n, snapshot.gyroZ.length),
      (i) => snapshot.gyroZ[i] * (180 / pi),
    );

    // Baro pressure - may have fewer samples (sampled at 1Hz vs 50Hz)
    // Pad to match timestamp count by repeating the nearest value.
    final baroPressure = _resampleToLength(snapshot.baroPressure, n);

    // Ensure all lists are the same length as timestamps
    return ProcessedTelemetry(
      timestamps: timestamps,
      lateralG: _padToLength(lateralG, n),
      longitudinalG: _padToLength(longitudinalG, n),
      speed: speed,
      yawRate: _padToLength(yawRate, n),
      baroPressure: baroPressure,
    );
  }

  /// Build a speed channel (km/h) on the sensor timeline by linearly
  /// interpolating the trace's GPS Doppler speeds.
  ///
  /// [sensorTimestamps] are seconds from lap start; trace timestamps are
  /// milliseconds from lap start. Returns an empty list when the trace
  /// carries no usable speed/timestamp data.
  static List<double> gpsSpeedChannel(
    List<TracePoint> trace,
    List<double> sensorTimestamps,
  ) {
    final samples = trace
        .where((p) => p.tMs != null && p.speedMps != null)
        .toList(growable: false);
    if (samples.length < 2) return [];

    final out = List<double>.filled(sensorTimestamps.length, 0);
    var j = 0;
    for (var i = 0; i < sensorTimestamps.length; i++) {
      final tMs = sensorTimestamps[i] * 1000;
      while (j < samples.length - 2 && samples[j + 1].tMs! <= tMs) {
        j++;
      }
      final a = samples[j];
      final b = samples[min(j + 1, samples.length - 1)];
      final span = (b.tMs! - a.tMs!);
      final frac = span > 0 ? ((tMs - a.tMs!) / span).clamp(0.0, 1.0) : 0.0;
      final mps = a.speedMps! + (b.speedMps! - a.speedMps!) * frac;
      out[i] = mps * 3.6;
    }
    return out;
  }

  /// Speed series (km/h) directly from a trace, with trace-relative
  /// timestamps in seconds. For charting laps that have no sensor data.
  static (List<double> timestamps, List<double> speedKmh) traceSpeedSeries(
    List<TracePoint> trace,
  ) {
    final ts = <double>[];
    final speed = <double>[];
    for (final p in trace) {
      if (p.tMs == null || p.speedMps == null) continue;
      ts.add(p.tMs! / 1000);
      speed.add(p.speedMps! * 3.6);
    }
    return (ts, speed);
  }

  /// Compute G-G diagram data points from processed telemetry.
  ///
  /// Returns lateral vs longitudinal g pairs suitable for a scatter plot.
  /// Optionally [downsample] to reduce the number of points for rendering.
  static List<GGPoint> computeGGData(
    ProcessedTelemetry telemetry, {
    int downsample = 1,
  }) {
    final count = min(telemetry.lateralG.length, telemetry.longitudinalG.length);
    final step = max(1, downsample);
    final points = <GGPoint>[];

    for (var i = 0; i < count; i += step) {
      points.add(GGPoint(
        lateralG: telemetry.lateralG[i],
        longitudinalG: telemetry.longitudinalG[i],
      ));
    }

    return points;
  }

  /// Compute a time-delta trace between two laps from their GPS traces.
  ///
  /// For each normalised distance fraction 0..1 around the lap, the delta
  /// is the difference between the elapsed times at which each lap reached
  /// that fraction of its total distance.
  ///
  /// Positive deltaMs means lap2 is slower at that point.
  /// Traces must carry timestamps (v2 traces do; legacy traces can be
  /// upgraded with [TraceCodec.withTimestamps]).
  static List<DeltaPoint> computeTimeDelta(
    List<TracePoint> trace1,
    List<TracePoint> trace2, {
    int numPoints = 100,
  }) {
    if (!TraceCodec.hasTimestamps(trace1) ||
        !TraceCodec.hasTimestamps(trace2)) {
      return [];
    }

    final dist1 = TraceCodec.cumulativeDistances(trace1);
    final dist2 = TraceCodec.cumulativeDistances(trace2);
    if (dist1.last <= 0 || dist2.last <= 0) return [];

    final points = <DeltaPoint>[];
    for (var i = 0; i <= numPoints; i++) {
      final fraction = i / numPoints;
      final t1 = _timeAtDistance(trace1, dist1, fraction * dist1.last);
      final t2 = _timeAtDistance(trace2, dist2, fraction * dist2.last);
      points.add(DeltaPoint(
        distance: fraction,
        deltaMs: (t2 - t1).round(),
      ));
    }
    return points;
  }

  /// Elapsed time (ms) at which a lap reached [target] meters, by linear
  /// interpolation over the trace's cumulative-distance curve.
  static double _timeAtDistance(
    List<TracePoint> trace,
    List<double> cumulative,
    double target,
  ) {
    if (target <= 0) return trace.first.tMs ?? 0;
    for (var i = 1; i < cumulative.length; i++) {
      if (cumulative[i] >= target) {
        final span = cumulative[i] - cumulative[i - 1];
        final frac = span > 0 ? (target - cumulative[i - 1]) / span : 0.0;
        final tA = trace[i - 1].tMs ?? 0;
        final tB = trace[i].tMs ?? tA;
        return tA + (tB - tA) * frac;
      }
    }
    return trace.last.tMs ?? 0;
  }

  /// Pad or trim a list to exactly [targetLength], repeating the last value.
  static List<double> _padToLength(List<double> data, int targetLength) {
    if (data.isEmpty) return List.filled(targetLength, 0);
    if (data.length >= targetLength) return data.sublist(0, targetLength);
    final lastVal = data.last;
    return [...data, ...List.filled(targetLength - data.length, lastVal)];
  }

  /// Resample a sparse list (e.g. 1Hz baro) to match a dense timestamp count.
  static List<double> _resampleToLength(List<double> sparse, int targetLength) {
    if (sparse.isEmpty) return List.filled(targetLength, 0);
    if (sparse.length >= targetLength) return sparse.sublist(0, targetLength);

    final result = <double>[];
    for (var i = 0; i < targetLength; i++) {
      final fraction = sparse.length > 1
          ? i / (targetLength - 1) * (sparse.length - 1)
          : 0.0;
      final idx = fraction.floor().clamp(0, sparse.length - 1);
      result.add(sparse[idx]);
    }
    return result;
  }
}

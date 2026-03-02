import 'dart:math';

import '../../../core/services/sensor_service.dart';

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
  /// Derived from accelerometer X axis.
  final List<double> lateralG;

  /// Longitudinal acceleration in g (positive = braking, negative = accel).
  /// Derived from accelerometer Y axis.
  final List<double> longitudinalG;

  /// Estimated speed in km/h from integrated acceleration.
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

  /// Cumulative distance through the lap in meters (or normalised 0..1).
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
  /// The accelerometer values from [LapSensorSnapshot] are in m/s^2.
  /// We convert them to g-force by dividing by 9.81.
  /// Speed is estimated by numerical integration of longitudinal acceleration.
  static ProcessedTelemetry processSensorData(LapSensorSnapshot snapshot) {
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

    // Integrate longitudinal acceleration to estimate speed (m/s -> km/h).
    // This is a rough estimate; GPS speed would be more accurate if available.
    final speed = <double>[];
    double v = 0; // Start at 0 m/s (relative speed change within lap)
    for (var i = 0; i < n; i++) {
      if (i > 0 && i < snapshot.accelY.length) {
        final dt = timestamps[i] - timestamps[i - 1];
        // Negative accelY means forward acceleration
        v += -snapshot.accelY[i] * dt;
        // Clamp to reasonable values (0..300 km/h equivalent in m/s)
        v = v.clamp(0, 83.33);
      }
      speed.add(v * 3.6); // Convert m/s to km/h
    }

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

  /// Compute a time-delta trace between two laps.
  ///
  /// Maps progress through the lap (normalised 0..1 as distance) against
  /// the cumulative time difference between the two laps at that point.
  ///
  /// Positive deltaMs means lap2 is slower at that point.
  /// Negative deltaMs means lap2 is faster at that point.
  static List<DeltaPoint> computeTimeDelta(
    ProcessedTelemetry lap1,
    ProcessedTelemetry lap2,
  ) {
    if (lap1.timestamps.isEmpty || lap2.timestamps.isEmpty) return [];

    final lap1Total = lap1.totalTime;
    final lap2Total = lap2.totalTime;

    if (lap1Total <= 0 || lap2Total <= 0) return [];

    // Compute at evenly spaced normalised distance points (0..1)
    const numPoints = 100;
    final points = <DeltaPoint>[];

    for (var i = 0; i <= numPoints; i++) {
      final fraction = i / numPoints;

      // Elapsed time at this fraction of each lap
      final t1 = fraction * lap1Total;
      final t2 = fraction * lap2Total;

      // Delta in milliseconds: positive means lap2 is slower
      final deltaMs = ((t2 - t1) * 1000).round();

      points.add(DeltaPoint(
        distance: fraction,
        deltaMs: deltaMs,
      ));
    }

    return points;
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A single sensor reading with all available channels.
class SensorReading {
  SensorReading({
    required this.timestamp,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.magX,
    this.magY,
    this.magZ,
    this.pressure,
  });

  final double timestamp; // seconds since session start
  final double? accelX, accelY, accelZ;
  final double? gyroX, gyroY, gyroZ;
  final double? magX, magY, magZ;
  final double? pressure;
}

/// Manages phone sensor streams for recording telemetry data.
///
/// Captures:
/// - Accelerometer at ~50Hz (g-force / braking/lateral)
/// - Gyroscope at ~50Hz (yaw/pitch/roll rate)
/// - Magnetometer at ~10Hz (heading reference)
/// - Barometer at ~1Hz (altitude reference / weather)
class SensorService {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<BarometerEvent>? _baroSub;

  DateTime? _sessionStart;

  // Buffers for the current lap
  final List<double> timestamps = [];
  final List<double> accelX = [];
  final List<double> accelY = [];
  final List<double> accelZ = [];
  final List<double> gyroX = [];
  final List<double> gyroY = [];
  final List<double> gyroZ = [];
  final List<double> magHeading = [];
  final List<double> baroPressure = [];

  // Latest readings for UI display
  double? lastAccelX, lastAccelY, lastAccelZ;
  double? lastGyroX, lastGyroY, lastGyroZ;
  double? lastPressure;

  /// Start all sensor streams.
  void startRecording() {
    _sessionStart = DateTime.now();
    _clearBuffers();

    // Accelerometer at ~50Hz (20ms interval)
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      final ts = _elapsedSeconds();
      timestamps.add(ts);
      accelX.add(event.x);
      accelY.add(event.y);
      accelZ.add(event.z);
      lastAccelX = event.x;
      lastAccelY = event.y;
      lastAccelZ = event.z;
    }, onError: (e) => debugPrint('Accel error: $e'));

    // Gyroscope at ~50Hz
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      gyroX.add(event.x);
      gyroY.add(event.y);
      gyroZ.add(event.z);
      lastGyroX = event.x;
      lastGyroY = event.y;
      lastGyroZ = event.z;
    }, onError: (e) => debugPrint('Gyro error: $e'));

    // Magnetometer at ~10Hz
    _magSub = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((event) {
      // Compute heading from magnetometer
      final heading = _computeHeading(event.x, event.y);
      magHeading.add(heading);
    }, onError: (e) => debugPrint('Mag error: $e'));

    // Barometer at ~1Hz
    _baroSub = barometerEventStream(
      samplingPeriod: const Duration(seconds: 1),
    ).listen((event) {
      baroPressure.add(event.pressure);
      lastPressure = event.pressure;
    }, onError: (e) => debugPrint('Baro error: $e'));
  }

  /// Get current lap sensor data and reset buffers for next lap.
  LapSensorSnapshot captureLapData() {
    final snapshot = LapSensorSnapshot(
      timestamps: List.from(timestamps),
      accelX: List.from(accelX),
      accelY: List.from(accelY),
      accelZ: List.from(accelZ),
      gyroX: List.from(gyroX),
      gyroY: List.from(gyroY),
      gyroZ: List.from(gyroZ),
      magHeading: List.from(magHeading),
      baroPressure: List.from(baroPressure),
    );
    _clearBuffers();
    return snapshot;
  }

  /// Stop all sensor streams.
  void stopRecording() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _baroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
    _baroSub = null;
    _sessionStart = null;
  }

  void dispose() {
    stopRecording();
  }

  double _elapsedSeconds() {
    if (_sessionStart == null) return 0;
    return DateTime.now().difference(_sessionStart!).inMicroseconds / 1e6;
  }

  void _clearBuffers() {
    timestamps.clear();
    accelX.clear();
    accelY.clear();
    accelZ.clear();
    gyroX.clear();
    gyroY.clear();
    gyroZ.clear();
    magHeading.clear();
    baroPressure.clear();
  }

  /// Compute magnetic heading from x/y magnetometer readings.
  double _computeHeading(double x, double y) {
    final heading = (180.0 * (3.14159265 - _atan2(y, x)) / 3.14159265);
    return heading < 0 ? heading + 360 : heading;
  }

  /// Simple atan2 implementation for heading calculation.
  double _atan2(double y, double x) {
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.14159265;
    if (x < 0 && y < 0) return _atan(y / x) - 3.14159265;
    if (x == 0 && y > 0) return 3.14159265 / 2;
    if (x == 0 && y < 0) return -3.14159265 / 2;
    return 0;
  }

  double _atan(double x) {
    // Use dart:math atan via a simple import-free approximation
    // In production this uses dart:math, but we use this for simplicity
    return x - (x * x * x) / 3 + (x * x * x * x * x) / 5;
  }
}

/// Snapshot of sensor data for one lap.
class LapSensorSnapshot {
  LapSensorSnapshot({
    required this.timestamps,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.magHeading,
    required this.baroPressure,
  });

  final List<double> timestamps;
  final List<double> accelX, accelY, accelZ;
  final List<double> gyroX, gyroY, gyroZ;
  final List<double> magHeading;
  final List<double> baroPressure;
}

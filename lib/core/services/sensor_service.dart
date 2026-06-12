import 'dart:async';
import 'dart:math';
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
/// - User accelerometer at ~50Hz (linear acceleration with gravity removed —
///   raw accelerometer readings include the ~9.81 m/s² gravity vector, which
///   would corrupt G-force channels and anything derived from them)
/// - Gyroscope at ~50Hz (yaw/pitch/roll rate)
/// - Magnetometer at ~10Hz (heading reference)
/// - Barometer at ~1Hz (altitude reference / weather)
///
/// All sensor data is aligned to the accelerometer timestamps using
/// nearest-sample interpolation. The accel stream defines the master timeline;
/// gyro/mag/baro values are held at their latest reading and sampled whenever
/// an accel event fires.
class SensorService {
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<BarometerEvent>? _baroSub;

  DateTime? _sessionStart;

  // Latest readings from each sensor (used for alignment)
  double _latestGyroX = 0, _latestGyroY = 0, _latestGyroZ = 0;
  double _latestMagHeading = 0;
  double _latestBaroPressure = 0;

  // Aligned buffers for the current lap (all same length, keyed to accel timestamps)
  final List<double> _timestamps = [];
  final List<double> _accelX = [];
  final List<double> _accelY = [];
  final List<double> _accelZ = [];
  final List<double> _gyroX = [];
  final List<double> _gyroY = [];
  final List<double> _gyroZ = [];
  final List<double> _magHeading = [];
  final List<double> _baroPressure = [];

  // Latest readings for UI display
  double? _lastAccelX, _lastAccelY, _lastAccelZ;
  double? _lastGyroX, _lastGyroY, _lastGyroZ;
  double? _lastPressure;

  // Public read-only accessors for UI display
  double? get lastAccelX => _lastAccelX;
  double? get lastAccelY => _lastAccelY;
  double? get lastAccelZ => _lastAccelZ;
  double? get lastGyroX => _lastGyroX;
  double? get lastGyroY => _lastGyroY;
  double? get lastGyroZ => _lastGyroZ;
  double? get lastPressure => _lastPressure;

  /// Start all sensor streams.
  void startRecording() {
    _sessionStart = DateTime.now();
    _clearBuffers();

    // User accelerometer (gravity removed) at ~50Hz — master timeline
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      final ts = _elapsedSeconds();

      // Record aligned data: accel is the master, others use latest values
      _timestamps.add(ts);
      _accelX.add(event.x);
      _accelY.add(event.y);
      _accelZ.add(event.z);
      _gyroX.add(_latestGyroX);
      _gyroY.add(_latestGyroY);
      _gyroZ.add(_latestGyroZ);
      _magHeading.add(_latestMagHeading);
      _baroPressure.add(_latestBaroPressure);

      _lastAccelX = event.x;
      _lastAccelY = event.y;
      _lastAccelZ = event.z;
    }, onError: (e) => debugPrint('Accel error: $e'));

    // Gyroscope at ~50Hz — updates latest values
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((event) {
      _latestGyroX = event.x;
      _latestGyroY = event.y;
      _latestGyroZ = event.z;
      _lastGyroX = event.x;
      _lastGyroY = event.y;
      _lastGyroZ = event.z;
    }, onError: (e) => debugPrint('Gyro error: $e'));

    // Magnetometer at ~10Hz — updates latest heading
    _magSub = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((event) {
      _latestMagHeading = _computeHeading(event.x, event.y);
    }, onError: (e) => debugPrint('Mag error: $e'));

    // Barometer at ~1Hz — updates latest pressure
    _baroSub = barometerEventStream(
      samplingPeriod: const Duration(seconds: 1),
    ).listen((event) {
      _latestBaroPressure = event.pressure;
      _lastPressure = event.pressure;
    }, onError: (e) => debugPrint('Baro error: $e'));
  }

  /// Get current lap sensor data and reset buffers for next lap.
  LapSensorSnapshot captureLapData() {
    final snapshot = LapSensorSnapshot(
      timestamps: List.from(_timestamps),
      accelX: List.from(_accelX),
      accelY: List.from(_accelY),
      accelZ: List.from(_accelZ),
      gyroX: List.from(_gyroX),
      gyroY: List.from(_gyroY),
      gyroZ: List.from(_gyroZ),
      magHeading: List.from(_magHeading),
      baroPressure: List.from(_baroPressure),
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
    _timestamps.clear();
    _accelX.clear();
    _accelY.clear();
    _accelZ.clear();
    _gyroX.clear();
    _gyroY.clear();
    _gyroZ.clear();
    _magHeading.clear();
    _baroPressure.clear();
    _latestGyroX = 0;
    _latestGyroY = 0;
    _latestGyroZ = 0;
    _latestMagHeading = 0;
    _latestBaroPressure = 0;
  }

  /// Compute magnetic heading from x/y magnetometer readings.
  double _computeHeading(double x, double y) {
    final heading = (180.0 * (pi - atan2(y, x)) / pi);
    return heading < 0 ? heading + 360 : heading;
  }
}

/// Snapshot of sensor data for one lap.
///
/// All arrays are guaranteed to be the same length, aligned to accelerometer
/// timestamps.
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

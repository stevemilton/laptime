import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS position data point with timestamp.
class GpsPoint {
  GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double speed; // m/s
  final double heading; // degrees
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'alt': altitude,
        'acc': accuracy,
        'spd': speed,
        'hdg': heading,
        'ts': timestamp.millisecondsSinceEpoch,
      };
}

/// Manages GPS location stream for recording sessions.
///
/// Uses maximum accuracy with automotive navigation activity type
/// for best results on track. Background location updates enabled.
class LocationService {
  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<GpsPoint>.broadcast();

  /// Stream of GPS data points.
  Stream<GpsPoint> get positionStream => _controller.stream;

  /// Most recent position, or null.
  GpsPoint? _lastPoint;
  GpsPoint? get lastPoint => _lastPoint;

  /// Check if location services are available and permissions granted.
  Future<bool> checkPermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Request location permissions (shows system dialog).
  Future<LocationPermission> requestPermission() async {
    return Geolocator.requestPermission();
  }

  /// One-shot current position (used for circuit detection before a
  /// recording starts). Returns null on timeout or failure.
  Future<GpsPoint?> getCurrentPosition({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return GpsPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );
    } catch (_) {
      return _lastPoint;
    }
  }

  /// Start the GPS stream at high frequency for recording.
  Future<void> startRecording() async {
    await _subscription?.cancel();

    final locationSettings = AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0, // Get every update
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );

    _subscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        final point = GpsPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
          timestamp: position.timestamp,
        );
        _lastPoint = point;
        _controller.add(point);
      },
      onError: (error) {
        debugPrint('Location error: $error');
      },
    );
  }

  /// Stop the GPS stream.
  Future<void> stopRecording() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastPoint = null;
  }

  /// Clean up resources.
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

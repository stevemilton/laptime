abstract final class AppConstants {
  static const appName = 'Lap Time';
  static const disclaimerVersion = '1.0';

  // GPS
  static const gpsMinAccuracyMeters = 15.0;
  static const gpsPreferredAccuracyMeters = 8.0;
  static const startFinishToleranceMeters = 15.0;

  // Lap detection
  // Hand-drawn start/finish lines are rarely placed to metre precision, and
  // the driving line wanders lap to lap — extend the gate past each endpoint.
  static const startFinishGateExtensionMeters = 10.0;
  // Ignore crossings below this speed: kills phantom laps from GPS jitter
  // while parked on the line and walking-pace "laps".
  static const minCrossingSpeedMps = 5.0; // 18 km/h
  static const minCrossingIntervalSeconds = 5;

  // Sensors
  static const accelerometerHz = 50;
  static const gyroscopeHz = 50;
  static const barometerHz = 1;
  static const magnetometerHz = 10;

  // Sync
  static const syncIntervalSeconds = 60;
  static const maxSyncRetries = 5;

  // Text limits
  static const setupNotesMaxLength = 500;
  static const sessionNotesMaxLength = 500;

  // Sectors
  static const minLapsForSectorCreation = 3;
}

abstract final class AppConstants {
  static const appName = 'Lap Time';
  static const disclaimerVersion = '1.0';

  // GPS
  static const gpsMinAccuracyMeters = 15.0;
  static const gpsPreferredAccuracyMeters = 8.0;
  static const startFinishToleranceMeters = 15.0;

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

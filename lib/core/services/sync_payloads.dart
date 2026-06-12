import 'dart:convert';

import '../database/app_database.dart';

/// Builders that turn local Drift rows into Supabase sync payloads.
///
/// These are the single source of truth for the client -> server column
/// mapping. Every key here must exist as a column on the remote table
/// (see supabase/migrations/). Keep payloads full-row: the sync engine
/// executes updates as upserts, so partial payloads would violate
/// NOT NULL constraints on the insert path.
abstract final class SyncPayloads {
  static Map<String, dynamic> session(LocalSession s) => {
        'id': s.id,
        'user_id': s.userId,
        'car_id': s.carId,
        'circuit_id': s.circuitId,
        'circuit_name': s.circuitName,
        'started_at': s.startedAt.toUtc().toIso8601String(),
        'ended_at': s.endedAt?.toUtc().toIso8601String(),
        'track_condition': s.trackCondition,
        'tyre_brand': s.tyreBrand,
        'tyre_compound': s.tyreCompound,
        'tyre_age_laps': s.tyreAgeLaps,
        'setup_notes': s.setupNotes,
        'session_notes': s.sessionNotes,
        'weather_json': tryDecode(s.weatherJson),
        'is_public': s.isPublic,
      };

  static Map<String, dynamic> lap(LocalLap lap) => {
        'id': lap.id,
        'session_id': lap.sessionId,
        'lap_number': lap.lapNumber,
        'duration_ms': lap.durationMs,
        'is_personal_best': lap.isPersonalBest,
        'trace_json': tryDecode(lap.traceJson),
      };

  static Map<String, dynamic> lapSensorData(LocalLapSensorDataData row) => {
        'id': row.id,
        'lap_id': row.lapId,
        'timestamps': tryDecode(row.timestampsJson) ?? <double>[],
        'accel_x': tryDecode(row.accelXJson),
        'accel_y': tryDecode(row.accelYJson),
        'accel_z': tryDecode(row.accelZJson),
        'gyro_x': tryDecode(row.gyroXJson),
        'gyro_y': tryDecode(row.gyroYJson),
        'gyro_z': tryDecode(row.gyroZJson),
        'baro_pressure': tryDecode(row.baroPressureJson),
        'mag_heading': tryDecode(row.magHeadingJson),
      };

  static Map<String, dynamic> sector(LocalSector s) => {
        'id': s.id,
        'circuit_id': s.circuitId,
        'created_by': s.createdBy,
        'name': s.name,
        'start_point_json': tryDecode(s.startPointJson),
        'end_point_json': tryDecode(s.endPointJson),
        'line_json': tryDecode(s.lineJson),
      };

  static Map<String, dynamic> sectorTime(LocalSectorTime t) => {
        'id': t.id,
        'sector_id': t.sectorId,
        'lap_id': t.lapId,
        'session_id': t.sessionId,
        'user_id': t.userId,
        'duration_ms': t.durationMs,
      };

  static Map<String, dynamic> car(LocalCar c) => {
        'id': c.id,
        'user_id': c.userId,
        'make': c.make,
        'model': c.model,
        'year': c.year,
        'class': c.carClass,
        'colour': c.colour,
        'image_url': c.imageUrl,
        'power_hp': c.powerHp,
        'weight_kg': c.weightKg,
        'drivetrain': c.drivetrain,
        'engine_capacity': c.engineCapacity,
        'modifications': c.modifications,
        'tyre_setup': c.tyreSetup,
      };

  static Map<String, dynamic> profile(LocalProfile p) => {
        'id': p.id,
        'display_name': p.displayName,
        'handle': p.handle,
        'avatar_url': p.avatarUrl,
      };

  static Map<String, dynamic> circuit(LocalCircuit c, {String? createdBy}) => {
        'id': c.id,
        'name': c.name,
        'country': c.country,
        'gps_lat': c.gpsLat,
        'gps_lng': c.gpsLng,
        'start_finish_line_json': tryDecode(c.startFinishLineJson),
        'length_m': c.lengthM,
        if (createdBy != null) 'created_by': createdBy,
      };

  /// Decode a locally stored JSON string into an object for a JSONB/array
  /// column. Returns null for null/empty/invalid input.
  static dynamic tryDecode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }
}

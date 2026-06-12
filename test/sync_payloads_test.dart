import 'package:flutter_test/flutter_test.dart';
import 'package:laptime/core/database/app_database.dart';
import 'package:laptime/core/services/sync_payloads.dart';

/// Schema-parity tests: every payload key must be a real column on the
/// remote table (see supabase/migrations/). The v1 sync engine failed
/// catastrophically because payload keys drifted from the SQL schema —
/// if you add a column to a payload builder, add it to a migration AND
/// to the expected set here.
void main() {
  final now = DateTime(2026, 6, 12);

  test('session payload matches public.sessions columns', () {
    final payload = SyncPayloads.session(LocalSession(
      id: 's1',
      userId: 'u1',
      startedAt: now,
      isPublic: true,
      createdAt: now,
      weatherJson: '{"temp": 18.5}',
    ));

    expect(payload.keys.toSet(), {
      'id',
      'user_id',
      'car_id',
      'circuit_id',
      'circuit_name',
      'started_at',
      'ended_at',
      'track_condition',
      'tyre_brand',
      'tyre_compound',
      'tyre_age_laps',
      'setup_notes',
      'session_notes',
      'weather_json',
      'is_public',
    });
    // weather_json must be an object, not a double-encoded string.
    expect(payload['weather_json'], isA<Map<String, dynamic>>());
  });

  test('lap payload matches public.laps columns', () {
    final payload = SyncPayloads.lap(LocalLap(
      id: 'l1',
      sessionId: 's1',
      lapNumber: 1,
      durationMs: 92000,
      isPersonalBest: false,
      createdAt: now,
      traceJson: '[[-1.0,52.0,0,30.5]]',
    ));

    expect(payload.keys.toSet(), {
      'id',
      'session_id',
      'lap_number',
      'duration_ms',
      'is_personal_best',
      'trace_json',
    });
    expect(payload['trace_json'], isA<List<dynamic>>());
  });

  test('sensor payload matches public.lap_sensor_data columns', () {
    final payload = SyncPayloads.lapSensorData(LocalLapSensorDataData(
      id: 'sd1',
      lapId: 'l1',
      timestampsJson: '[0.0,0.02]',
      accelXJson: '[0.1,0.2]',
    ));

    expect(payload.keys.toSet(), {
      'id',
      'lap_id',
      'timestamps',
      'accel_x',
      'accel_y',
      'accel_z',
      'gyro_x',
      'gyro_y',
      'gyro_z',
      'baro_pressure',
      'mag_heading',
    });
    // Arrays go to REAL[]/DOUBLE PRECISION[] columns: raw lists, not
    // JSON-encoded strings.
    expect(payload['timestamps'], isA<List<dynamic>>());
    expect(payload['accel_x'], isA<List<dynamic>>());
  });

  test('sector payload matches public.sectors columns', () {
    final payload = SyncPayloads.sector(LocalSector(
      id: 'sec1',
      circuitId: 'c1',
      createdBy: 'u1',
      name: 'Sector 1',
      createdAt: now,
      startPointJson: '{"lat":52.0,"lng":-1.0}',
      endPointJson: '{"lat":52.1,"lng":-1.1}',
    ));

    expect(payload.keys.toSet(), {
      'id',
      'circuit_id',
      'created_by',
      'name',
      'start_point_json',
      'end_point_json',
      'line_json',
    });
    expect(payload['start_point_json'], isA<Map<String, dynamic>>());
  });

  test('sector time payload matches public.sector_times columns', () {
    final payload = SyncPayloads.sectorTime(LocalSectorTime(
      id: 'st1',
      sectorId: 'sec1',
      lapId: 'l1',
      sessionId: 's1',
      userId: 'u1',
      durationMs: 31000,
      computedAt: now,
    ));

    expect(payload.keys.toSet(), {
      'id',
      'sector_id',
      'lap_id',
      'session_id',
      'user_id',
      'duration_ms',
    });
  });

  test('car payload matches public.cars columns', () {
    final payload = SyncPayloads.car(LocalCar(
      id: 'car1',
      userId: 'u1',
      make: 'Mazda',
      model: 'MX-5',
      createdAt: now,
    ));

    expect(payload.keys.toSet(), {
      'id',
      'user_id',
      'make',
      'model',
      'year',
      'class',
      'colour',
      'image_url',
      'power_hp',
      'weight_kg',
      'drivetrain',
      'engine_capacity',
      'modifications',
      'tyre_setup',
    });
  });

  test('profile payload matches public.profiles columns', () {
    final payload = SyncPayloads.profile(LocalProfile(
      id: 'u1',
      displayName: 'Driver',
      createdAt: now,
    ));

    expect(payload.keys.toSet(), {
      'id',
      'display_name',
      'handle',
      'avatar_url',
    });
  });

  test('circuit payload matches public.circuits columns', () {
    final payload = SyncPayloads.circuit(
      LocalCircuit(
        id: 'c1',
        name: 'Silverstone',
        country: 'GB',
        gpsLat: 52.07,
        gpsLng: -1.01,
        createdAt: now,
        startFinishLineJson: '[[52.0,-1.0],[52.001,-1.0]]',
      ),
      createdBy: 'u1',
    );

    expect(payload.keys.toSet(), {
      'id',
      'name',
      'country',
      'gps_lat',
      'gps_lng',
      'start_finish_line_json',
      'length_m',
      'created_by',
    });
    expect(payload['start_finish_line_json'], isA<List<dynamic>>());
  });

  test('tryDecode handles nulls and invalid JSON', () {
    expect(SyncPayloads.tryDecode(null), isNull);
    expect(SyncPayloads.tryDecode(''), isNull);
    expect(SyncPayloads.tryDecode('garbage'), isNull);
    expect(SyncPayloads.tryDecode('{"a":1}'), {'a': 1});
  });
}

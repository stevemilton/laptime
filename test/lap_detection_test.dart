import 'package:flutter_test/flutter_test.dart';
import 'package:laptime/core/services/lap_detection_service.dart';
import 'package:laptime/core/services/location_service.dart';

GpsPoint _point(
  double lat,
  double lng,
  int tMs, {
  double accuracy = 5,
  double speed = 40,
}) {
  final start = DateTime(2026, 1, 1, 12, 0, 0);
  return GpsPoint(
    latitude: lat,
    longitude: lng,
    altitude: 100,
    accuracy: accuracy,
    speed: speed,
    heading: 0,
    timestamp: start.add(Duration(milliseconds: tMs)),
  );
}

void main() {
  // Start/finish line: a short north-south segment crossing the x axis.
  const sfLat1 = -0.0002;
  const sfLng1 = 0.0;
  const sfLat2 = 0.0002;
  const sfLng2 = 0.0;

  LapDetectionService arm() {
    final service = LapDetectionService();
    service.setStartFinishLine(sfLat1, sfLng1, sfLat2, sfLng2);
    return service;
  }

  test('no crossing without a configured line', () {
    final service = LapDetectionService();
    expect(service.processPoint(_point(0, -0.001, 0)), isNull);
    expect(service.processPoint(_point(0, 0.001, 1000)), isNull);
  });

  test('detects a west-to-east crossing and interpolates the time', () {
    final service = arm();
    expect(service.processPoint(_point(0, -0.001, 0)), isNull);
    final crossing = service.processPoint(_point(0, 0.001, 2000));

    expect(crossing, isNotNull);
    // Line is exactly halfway between the two points.
    final elapsed = crossing!.crossingTime
        .difference(DateTime(2026, 1, 1, 12, 0, 0))
        .inMilliseconds;
    expect(elapsed, closeTo(1000, 50));
    expect(crossing.crossingLat, closeTo(0, 1e-9));
    expect(crossing.crossingLng, closeTo(0, 1e-9));
  });

  test('ignores points with poor GPS accuracy', () {
    final service = arm();
    expect(
      service.processPoint(_point(0, -0.001, 0, accuracy: 50)),
      isNull,
    );
    expect(
      service.processPoint(_point(0, 0.001, 2000, accuracy: 50)),
      isNull,
    );
  });

  test('debounces crossings inside the minimum interval', () {
    final service = arm();
    service.processPoint(_point(0, -0.001, 0));
    final first = service.processPoint(_point(0, 0.001, 2000));
    expect(first, isNotNull);

    // Move away beyond tolerance, then cross again 3 seconds later —
    // inside the 5 s debounce window, so it must not trigger.
    service.processPoint(_point(0, 0.002, 3000)); // >15 m from line
    service.processPoint(_point(0, -0.001, 4000));
    final second = service.processPoint(_point(0, 0.001, 5000));
    expect(second, isNull);
  });

  test('allows the next crossing after debounce and move-away', () {
    final service = arm();
    service.processPoint(_point(0, -0.001, 0));
    expect(service.processPoint(_point(0, 0.001, 2000)), isNotNull);

    // Drive away on the same side and approach the line again without
    // crossing it (0.005 -> 0.001 stays east of the line), then cross
    // 88 seconds after the first crossing.
    service.processPoint(_point(0, 0.005, 30000));
    service.processPoint(_point(0, 0.001, 88000));
    final next = service.processPoint(_point(0, -0.001, 90000));
    expect(next, isNotNull);
  });

  test('a full lap that re-crosses during the return leg is detected once',
      () {
    final service = arm();
    service.processPoint(_point(0, -0.001, 0));
    expect(service.processPoint(_point(0, 0.001, 2000)), isNotNull);

    // The return path itself crosses the line (0.005 -> -0.001): that IS
    // a lap crossing and must fire...
    service.processPoint(_point(0, 0.005, 30000));
    expect(service.processPoint(_point(0, -0.001, 88000)), isNotNull);

    // ...and a re-cross 2 seconds later is a double-trigger: debounced.
    expect(service.processPoint(_point(0, 0.001, 90000)), isNull);
  });

  // The Skegness failure: the driving line passed a few metres beyond the
  // drawn endpoint every lap, so 9 of 10 crossings were missed.
  test('detects a crossing just beyond the drawn line endpoint', () {
    final service = arm();
    // Drawn line ends at lat 0.0002 (~22 m); this path crosses at ~28 m,
    // inside the 10 m gate extension.
    service.processPoint(_point(0.00025, -0.001, 0));
    expect(service.processPoint(_point(0.00025, 0.001, 2000)), isNotNull);
  });

  test('does not detect a crossing far beyond the gate extension', () {
    final service = arm();
    // ~39 m from the line centre: ~17 m past the endpoint, outside the
    // 10 m extension.
    service.processPoint(_point(0.00035, -0.001, 0));
    expect(service.processPoint(_point(0.00035, 0.001, 2000)), isNull);
  });

  // The other Skegness failure: the recorded lap started while the car sat
  // parked next to the line (GPS jitter), and a walking-pace loop set a
  // 39 s "personal best".
  test('ignores crossings below the minimum speed', () {
    final service = arm();
    service.processPoint(_point(0, -0.001, 0, speed: 1.5));
    expect(
      service.processPoint(_point(0, 0.001, 2000, speed: 1.5)),
      isNull,
    );

    // Same geometry at driving speed fires.
    final driving = arm();
    driving.processPoint(_point(0, -0.001, 0));
    expect(driving.processPoint(_point(0, 0.001, 2000)), isNotNull);
  });

  test('laps shorter than 10 s are no longer swallowed by the debounce', () {
    final service = arm();
    service.processPoint(_point(0, -0.001, 0));
    expect(service.processPoint(_point(0, 0.001, 1000)), isNotNull);

    // A ~6-second kart lap: drive away east, then cross back west —
    // inside the old 10 s debounce, outside the new 5 s one.
    service.processPoint(_point(0, 0.002, 3000));
    expect(service.processPoint(_point(0, -0.001, 7000)), isNotNull);
  });
}

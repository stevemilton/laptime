import 'package:flutter_test/flutter_test.dart';
import 'package:laptime/core/utils/format_utils.dart';

void main() {
  group('formatLapTime', () {
    test('formats minutes, seconds, millis', () {
      expect(FormatUtils.formatLapTime(119204), '1:59.204');
      expect(FormatUtils.formatLapTime(60000), '1:00.000');
    });

    test('sub-minute laps omit minutes', () {
      expect(FormatUtils.formatLapTime(59999), '59.999');
      expect(FormatUtils.formatLapTime(204), '0.204');
    });

    test('clamps negative input', () {
      expect(FormatUtils.formatLapTime(-5), '0.000');
    });
  });

  group('formatDelta', () {
    test('signs deltas', () {
      expect(FormatUtils.formatDelta(-891), '-0.891s');
      expect(FormatUtils.formatDelta(1203), '+1.203s');
      expect(FormatUtils.formatDelta(0), '+0.000s');
    });
  });

  group('speed formatting', () {
    test('metric km/h', () {
      expect(FormatUtils.formatSpeed(27.78), '100 km/h');
      expect(FormatUtils.speedUnit(UnitSystem.metric), 'km/h');
    });

    test('imperial mph', () {
      expect(
        FormatUtils.formatSpeed(27.78, units: UnitSystem.imperial),
        '62 mph',
      );
      expect(FormatUtils.speedUnit(UnitSystem.imperial), 'mph');
    });

    test('speedValue conversion factors', () {
      expect(FormatUtils.speedValue(10), closeTo(36, 0.001));
      expect(
        FormatUtils.speedValue(10, units: UnitSystem.imperial),
        closeTo(22.369, 0.001),
      );
    });
  });

  group('formatTemp / formatWindSpeed / formatPressure', () {
    test('respects unit system', () {
      expect(FormatUtils.formatTemp(20), '20°C');
      expect(
          FormatUtils.formatTemp(20, units: UnitSystem.imperial), '68°F');
      expect(FormatUtils.formatWindSpeed(10), '36 km/h');
      expect(FormatUtils.formatWindSpeed(10, units: UnitSystem.imperial),
          '22 mph');
      expect(FormatUtils.formatPressure(1013), '1013 hPa');
      expect(FormatUtils.formatPressure(1013, units: UnitSystem.imperial),
          '29.91 inHg');
    });
  });
}

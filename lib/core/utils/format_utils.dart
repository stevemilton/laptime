/// Unit system for weather and measurement formatting.
enum UnitSystem {
  metric,
  imperial;

  /// Legacy string representation for backward compatibility.
  String get label => switch (this) {
        UnitSystem.metric => 'Metric',
        UnitSystem.imperial => 'Imperial',
      };
}

/// Formatting utilities for lap times, durations, weather data, etc.
abstract final class FormatUtils {
  /// Formats duration in milliseconds to lap time string.
  /// e.g. 119204 -> "1:59.204"
  static String formatLapTime(int durationMs) {
    if (durationMs < 0) durationMs = 0;
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    final millis = durationMs % 1000;

    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
    }
    return '$seconds.${millis.toString().padLeft(3, '0')}';
  }

  /// Formats elapsed seconds to "M:SS" string.
  /// e.g. 124 -> "2:04"
  static String formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Formats delta time string with sign.
  /// e.g. -891 -> "-0.891s", 1203 -> "+1.203s"
  static String formatDelta(int deltaMs) {
    final sign = deltaMs < 0 ? '-' : '+';
    final abs = deltaMs.abs();
    final seconds = abs ~/ 1000;
    final millis = abs % 1000;
    return '$sign$seconds.${millis.toString().padLeft(3, '0')}s';
  }

  /// Formats temperature with degree symbol, respecting unit preference.
  static String formatTemp(double tempCelsius, {UnitSystem units = UnitSystem.metric}) {
    if (units == UnitSystem.imperial) {
      final tempF = (tempCelsius * 9 / 5) + 32;
      return '${tempF.round()}\u00B0F';
    }
    return '${tempCelsius.round()}\u00B0C';
  }

  /// Formats wind speed, respecting unit preference.
  /// Input is always m/s.
  static String formatWindSpeed(double speedMs, {UnitSystem units = UnitSystem.metric}) {
    if (units == UnitSystem.imperial) {
      final mph = (speedMs * 2.237).round();
      return '$mph mph';
    }
    final kmh = (speedMs * 3.6).round();
    return '$kmh km/h';
  }

  /// Converts a speed in m/s to the display unit (km/h or mph).
  static double speedValue(double speedMps, {UnitSystem units = UnitSystem.metric}) {
    return units == UnitSystem.imperial ? speedMps * 2.236936 : speedMps * 3.6;
  }

  /// Converts a km/h value to the display unit (used by telemetry charts,
  /// whose channels are stored in km/h).
  static double kmhToDisplay(double kmh, {UnitSystem units = UnitSystem.metric}) {
    return units == UnitSystem.imperial ? kmh / 1.609344 : kmh;
  }

  /// Unit label for speeds ("km/h" or "mph").
  static String speedUnit(UnitSystem units) {
    return units == UnitSystem.imperial ? 'mph' : 'km/h';
  }

  /// Formats a vehicle speed (input m/s) as a whole number with unit.
  /// e.g. 33.4 m/s -> "120 km/h" / "75 mph"
  static String formatSpeed(double speedMps, {UnitSystem units = UnitSystem.metric}) {
    return '${speedValue(speedMps, units: units).round()} ${speedUnit(units)}';
  }

  /// Formats pressure, respecting unit preference.
  /// Input is always hPa.
  static String formatPressure(double hPa, {UnitSystem units = UnitSystem.metric}) {
    if (units == UnitSystem.imperial) {
      final inHg = (hPa * 0.02953).toStringAsFixed(2);
      return '$inHg inHg';
    }
    return '${hPa.round()} hPa';
  }

  /// Formats a DateTime as a relative date string.
  /// e.g. "Just now", "5m ago", "3h ago", "Yesterday", "4 days ago", "02/03/2026"
  static String formatRelativeDate(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    final d = dateTime.day.toString().padLeft(2, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    return '$d/$m/${dateTime.year}';
  }

  /// Formats a DateTime as a short readable date.
  /// e.g. "5 Mar 2026"
  static String formatShortDate(DateTime dateTime) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
  }
}

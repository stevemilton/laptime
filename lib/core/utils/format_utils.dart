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
  /// [units] should be 'Metric' or 'Imperial'.
  static String formatTemp(double tempCelsius, {String units = 'Metric'}) {
    if (units == 'Imperial') {
      final tempF = (tempCelsius * 9 / 5) + 32;
      return '${tempF.round()}\u00B0F';
    }
    return '${tempCelsius.round()}\u00B0C';
  }

  /// Formats wind speed, respecting unit preference.
  /// Input is always m/s. [units] should be 'Metric' or 'Imperial'.
  static String formatWindSpeed(double speedMs, {String units = 'Metric'}) {
    if (units == 'Imperial') {
      final mph = (speedMs * 2.237).round();
      return '$mph mph';
    }
    final kmh = (speedMs * 3.6).round();
    return '$kmh km/h';
  }

  /// Formats pressure, respecting unit preference.
  /// Input is always hPa. [units] should be 'Metric' or 'Imperial'.
  static String formatPressure(double hPa, {String units = 'Metric'}) {
    if (units == 'Imperial') {
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
}

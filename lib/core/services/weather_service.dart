import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/env.dart';

/// Weather data captured at session start.
class WeatherData {
  WeatherData({
    required this.tempCelsius,
    required this.feelsLike,
    required this.humidity,
    required this.pressure,
    required this.windSpeed,
    required this.windDeg,
    required this.description,
    required this.icon,
    this.rain1h,
    required this.rawJson,
  });

  final double tempCelsius;
  final double feelsLike;
  final int humidity;
  final double pressure; // hPa
  final double windSpeed; // m/s
  final int windDeg;
  final String description;
  final String icon;
  final double? rain1h; // mm
  final Map<String, dynamic> rawJson;

  /// Quick track condition estimate based on weather.
  String get suggestedTrackCondition {
    if (rain1h != null && rain1h! > 0.5) return 'wet';
    if (rain1h != null && rain1h! > 0) return 'damp';
    if (humidity > 90) return 'damp';
    return 'dry';
  }

  Map<String, dynamic> toJson() => rawJson;

  /// Parse from One Call API 3.0 response.
  factory WeatherData.fromOneCallJson(Map<String, dynamic> json) {
    final current = json['current'] ?? json;
    final weather =
        (current['weather'] as List?)?.first as Map<String, dynamic>? ?? {};

    return WeatherData(
      tempCelsius: (current['temp'] as num?)?.toDouble() ?? 0,
      feelsLike: (current['feels_like'] as num?)?.toDouble() ?? 0,
      humidity: (current['humidity'] as num?)?.toInt() ?? 0,
      pressure: (current['pressure'] as num?)?.toDouble() ?? 0,
      windSpeed: (current['wind_speed'] as num?)?.toDouble() ?? 0,
      windDeg: (current['wind_deg'] as num?)?.toInt() ?? 0,
      description: weather['description'] as String? ?? '',
      icon: weather['icon'] as String? ?? '',
      rain1h: (current['rain']?['1h'] as num?)?.toDouble(),
      rawJson: json,
    );
  }

  /// Parse from Current Weather API 2.5 response.
  factory WeatherData.fromCurrentJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>? ?? {};
    final wind = json['wind'] as Map<String, dynamic>? ?? {};
    final rain = json['rain'] as Map<String, dynamic>?;
    final weatherList = json['weather'] as List?;
    final weather = weatherList?.isNotEmpty == true
        ? weatherList!.first as Map<String, dynamic>
        : <String, dynamic>{};

    return WeatherData(
      tempCelsius: (main['temp'] as num?)?.toDouble() ?? 0,
      feelsLike: (main['feels_like'] as num?)?.toDouble() ?? 0,
      humidity: (main['humidity'] as num?)?.toInt() ?? 0,
      pressure: (main['pressure'] as num?)?.toDouble() ?? 0,
      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0,
      windDeg: (wind['deg'] as num?)?.toInt() ?? 0,
      description: weather['description'] as String? ?? '',
      icon: weather['icon'] as String? ?? '',
      rain1h: (rain?['1h'] as num?)?.toDouble(),
      rawJson: json,
    );
  }

  /// Auto-detect format: One Call has 'current' key, Current API doesn't.
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('current')) {
      return WeatherData.fromOneCallJson(json);
    }
    return WeatherData.fromCurrentJson(json);
  }
}

/// Result from weather fetch including any error info.
class WeatherResult {
  WeatherResult({this.data, this.error});

  final WeatherData? data;
  final String? error;

  bool get hasData => data != null;
  bool get hasError => error != null;
}

/// Service for fetching weather data from OpenWeatherMap.
///
/// Tries One Call API 3.0 first. If that fails (e.g. free key without
/// subscription), falls back to the free Current Weather API 2.5.
/// Called once at session start (fire-and-forget). Never blocks recording.
class WeatherService {
  WeatherService() : _dio = Dio();

  final Dio _dio;

  static const _oneCallUrl = 'https://api.openweathermap.org/data/3.0/onecall';
  static const _currentUrl = 'https://api.openweathermap.org/data/2.5/weather';

  /// Fetch current weather with detailed result (data + error).
  Future<WeatherResult> fetchWeatherWithResult({
    required double latitude,
    required double longitude,
  }) async {
    final apiKey = Env.openWeatherMapApiKey;
    if (apiKey.isEmpty) {
      return WeatherResult(error: 'No weather API key configured');
    }

    // Try One Call 3.0 first
    try {
      final response = await _dio.get(
        _oneCallUrl,
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'appid': apiKey,
          'units': 'metric',
          'exclude': 'minutely,hourly,daily,alerts',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = WeatherData.fromOneCallJson(
            response.data as Map<String, dynamic>);
        return WeatherResult(data: data);
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      debugPrint(
          'WeatherService: One Call 3.0 failed ($statusCode), trying 2.5');

      // 401/403 = subscription required, 429 = rate limited → fallback
      if (statusCode == 401 || statusCode == 403 || statusCode == 429) {
        return _fetchFromCurrentApi(latitude, longitude, apiKey);
      }

      return WeatherResult(error: 'Weather error ($statusCode)');
    } catch (e) {
      debugPrint('WeatherService One Call error: $e');
    }

    // Fallback to 2.5 if One Call didn't return data
    return _fetchFromCurrentApi(latitude, longitude, apiKey);
  }

  /// Fallback: free Current Weather API 2.5
  Future<WeatherResult> _fetchFromCurrentApi(
    double latitude,
    double longitude,
    String apiKey,
  ) async {
    try {
      final response = await _dio.get(
        _currentUrl,
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'appid': apiKey,
          'units': 'metric',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = WeatherData.fromCurrentJson(
            response.data as Map<String, dynamic>);
        return WeatherResult(data: data);
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      debugPrint('WeatherService: Current API 2.5 also failed ($statusCode)');

      if (statusCode == 401) {
        return WeatherResult(error: 'Invalid API key');
      }
      return WeatherResult(error: 'Weather unavailable');
    } catch (e) {
      debugPrint('WeatherService 2.5 error: $e');
    }

    return WeatherResult(error: 'Weather unavailable');
  }

  /// Simple fetch - returns null on failure (used by recording repository).
  Future<WeatherData?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    final result = await fetchWeatherWithResult(
      latitude: latitude,
      longitude: longitude,
    );
    return result.data;
  }

  void dispose() {
    _dio.close();
  }
}

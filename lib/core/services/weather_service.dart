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

  factory WeatherData.fromJson(Map<String, dynamic> json) {
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
}

/// Service for fetching weather data from OpenWeatherMap One Call API 3.0.
///
/// Called once at session start (fire-and-forget). Never blocks recording.
class WeatherService {
  WeatherService() : _dio = Dio();

  final Dio _dio;

  static const _baseUrl = 'https://api.openweathermap.org/data/3.0/onecall';

  /// Fetch current weather for a GPS coordinate.
  ///
  /// Returns null if the API key is not configured or the request fails.
  Future<WeatherData?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    final apiKey = Env.openWeatherMapApiKey;
    if (apiKey.isEmpty) {
      debugPrint('WeatherService: No API key configured');
      return null;
    }

    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'appid': apiKey,
          'units': 'metric',
          'exclude': 'minutely,hourly,daily,alerts',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        return WeatherData.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('WeatherService error: $e');
    }

    return null;
  }

  void dispose() {
    _dio.close();
  }
}

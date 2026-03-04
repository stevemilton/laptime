import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../../../core/database/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/weather_service.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/weather_strip.dart';
import '../../../core/widgets/gps_indicator.dart';
import '../../../features/settings/presentation/settings_screen.dart';
import 'recording_controller.dart';

/// Provider for the most recent session.
final _lastSessionProvider = StreamProvider<LocalSession?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(db.localSessions)
        ..where((t) => t.userId.equals(user.id))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
        ..limit(1))
      .watchSingleOrNull();
});

/// Provider for best lap of a session.
final _sessionBestLapProvider =
    FutureProvider.family<int?, String>((ref, sessionId) async {
  final db = ref.read(databaseProvider);
  final laps = await db.getSessionLaps(sessionId);
  if (laps.isEmpty) return null;
  return laps.map((l) => l.durationMs).reduce((a, b) => a < b ? a : b);
});

/// Home tab screen – big START button, weather info, last session card.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final _locationService = LocationService();
  bool _gpsReady = false;
  double? _gpsAccuracy; // Real GPS accuracy in meters
  StreamSubscription<Position>? _liveGpsSub; // Continuous GPS for live accuracy

  // Live weather
  WeatherData? _weather;
  bool _weatherLoading = true;
  String? _weatherError; // User-visible weather error

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkGps();
    _fetchWeather();
  }

  Future<void> _checkGps() async {
    final ready = await _locationService.checkPermissions();
    if (mounted) setState(() => _gpsReady = ready);

    // Start continuous GPS stream to show live accuracy
    if (ready) {
      _liveGpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen(
        (position) {
          if (mounted) {
            setState(() => _gpsAccuracy = position.accuracy);
          }
        },
        onError: (_) {
          // Silently fail - accuracy will stay at last known value
        },
      );
    }
  }

  Future<void> _fetchWeather() async {
    try {
      final hasPerms = await _locationService.checkPermissions();
      if (!hasPerms) {
        if (mounted) {
          setState(() {
            _weatherLoading = false;
            _weatherError = 'Location permission needed';
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final result = await WeatherService().fetchWeatherWithResult(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (mounted) {
        setState(() {
          _weather = result.data;
          _weatherError = result.error;
          _weatherLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
          _weatherError = 'Could not fetch weather';
        });
      }
    }
  }

  @override
  void dispose() {
    _liveGpsSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(recordingControllerProvider);
    final isLoading = controllerState.isLoading;
    final lastSessionAsync = ref.watch(_lastSessionProvider);

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Record',
                      style: AppTypography.headlineLarge,
                    ),
                    const SizedBox(height: 2),
                    GpsIndicator(
                      isActive: _gpsReady,
                      accuracy: _gpsAccuracy,
                    ),
                  ],
                ),
                // Settings button
                IconButton(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(
                    LucideIcons.settings,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Weather strip
          Padding(
            padding: const EdgeInsets.all(24),
            child: _buildWeatherStrip(),
          ),

          const Spacer(),

          // Big START button with pulse animation
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.purple, AppColors.purpleBright],
                    ),
                    boxShadow: AppShadows.purple,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: isLoading ? null : _onStartRecording,
                      child: Center(
                        child: isLoading
                            ? const CircularProgressIndicator(
                                color: AppColors.white,
                                strokeWidth: 3,
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    LucideIcons.play,
                                    size: 48,
                                    color: AppColors.white,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'START',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.white,
                                      fontWeight: FontWeight.w300,
                                      fontSize: 13,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          const Spacer(),

          // Last session card
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: lastSessionAsync.when(
              data: (session) => _buildLastSessionCard(session),
              loading: () => _buildLastSessionCard(null),
              error: (_, _) => _buildLastSessionCard(null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherStrip() {
    if (_weatherLoading) {
      return const WeatherStrip(
        temperature: '--',
        trackCondition: '--',
        windSpeed: '--',
        pressure: '--',
      );
    }

    final w = _weather;
    if (w == null) {
      // Show error hint if available
      return WeatherStrip(
        temperature: '--',
        trackCondition: _weatherError ?? '--',
        windSpeed: '--',
        pressure: '--',
      );
    }

    final units = ref.watch(unitsProvider);
    return WeatherStrip(
      temperature: FormatUtils.formatTemp(w.tempCelsius, units: units),
      trackCondition: w.suggestedTrackCondition.substring(0, 1).toUpperCase() +
          w.suggestedTrackCondition.substring(1),
      windSpeed: FormatUtils.formatWindSpeed(w.windSpeed, units: units),
      pressure: FormatUtils.formatPressure(w.pressure, units: units),
    );
  }

  Widget _buildLastSessionCard(LocalSession? session) {
    if (session == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LAST SESSION', style: AppTypography.sectionLabel),
            const SizedBox(height: 8),
            Text(
              'No sessions yet. Hit START to record your first session.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    // Fetch best lap for this session
    final bestLapAsync = ref.watch(_sessionBestLapProvider(session.id));
    final bestLapMs = bestLapAsync.value;

    return GestureDetector(
      onTap: () => context.push('/session/${session.id}'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('LAST SESSION', style: AppTypography.sectionLabel),
                Icon(LucideIcons.chevronRight,
                    size: 16, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Best lap time
                if (bestLapMs != null) ...[
                  Text(
                    FormatUtils.formatLapTime(bestLapMs),
                    style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // Date
                Expanded(
                  child: Text(
                    _formatSessionDate(session.startedAt),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                // Track condition pill
                if (session.trackCondition != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.purplePale,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      session.trackCondition!,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.purple,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSessionDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _onStartRecording() async {
    // Check GPS permissions first
    if (!_gpsReady) {
      final permission = await _locationService.requestPermission();
      if (mounted) {
        setState(() => _gpsReady = permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever);
      }
      if (!_gpsReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS permission is required to record sessions'),
              backgroundColor: AppColors.red,
            ),
          );
        }
        return;
      }
    }

    // Stop the pre-recording GPS stream before starting recording
    await _liveGpsSub?.cancel();
    _liveGpsSub = null;

    // Start recording
    final sessionId = await ref
        .read(recordingControllerProvider.notifier)
        .startSession();

    if (sessionId != null && mounted) {
      // Navigate to active recording screen
      context.push('/recording');
    }
  }
}

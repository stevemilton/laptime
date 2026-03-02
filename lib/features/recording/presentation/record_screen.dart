import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/weather_strip.dart';
import '../../../core/widgets/gps_indicator.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/location_service.dart';
import 'recording_controller.dart';

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
  }

  Future<void> _checkGps() async {
    final ready = await _locationService.checkPermissions();
    if (mounted) setState(() => _gpsReady = ready);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(recordingControllerProvider);
    final isLoading = controllerState.isLoading;

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
                      accuracy: _gpsReady ? 5.0 : null,
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
          const Padding(
            padding: EdgeInsets.all(24),
            child: WeatherStrip(
              temperature: '14\u00B0C',
              trackCondition: 'Dry',
              windSpeed: '8 km/h',
              pressure: '1013 hPa',
            ),
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

          // Last session card placeholder
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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
                  Text(
                    'LAST SESSION',
                    style: AppTypography.sectionLabel,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No sessions yet. Hit START to record your first session.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

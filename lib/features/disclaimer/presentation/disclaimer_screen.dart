import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../profile/data/profile_repository.dart';
import '../data/disclaimer_repository.dart';

/// Provider for disclaimer acceptance state.
final hasAcceptedDisclaimerProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final db = ref.read(databaseProvider);
  final client = ref.read(supabaseClientProvider);
  final repo = DisclaimerRepository(db, client);
  return repo.hasAcceptedLatest(user.id);
});

/// Full-screen legal disclaimer that must be accepted before using the app.
///
/// Shown once after first login. Re-shown if disclaimer version is bumped.
class DisclaimerScreen extends ConsumerStatefulWidget {
  const DisclaimerScreen({super.key});

  @override
  ConsumerState<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends ConsumerState<DisclaimerScreen> {
  bool _accepted = false;
  bool _isSubmitting = false;
  String _disclaimerText = '';

  @override
  void initState() {
    super.initState();
    _loadDisclaimer();
  }

  Future<void> _loadDisclaimer() async {
    try {
      final text = await rootBundle.loadString('assets/legal/disclaimer.md');
      if (mounted) setState(() => _disclaimerText = text);
    } catch (_) {
      if (mounted) {
        setState(() => _disclaimerText =
            'Unable to load disclaimer. Please check your connection and restart the app.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Safety Disclaimer'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Warning header
              Container(
                margin: const EdgeInsets.only(top: 16, bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.goldLight,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.alertTriangle,
                        color: AppColors.gold, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please read this carefully before using LapTime.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable disclaimer text
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _disclaimerText,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Acceptance checkbox
              GestureDetector(
                onTap: () => setState(() => _accepted = !_accepted),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color:
                            _accepted ? AppColors.purple : AppColors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _accepted
                              ? AppColors.purple
                              : AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: _accepted
                          ? const Icon(LucideIcons.check,
                              size: 16, color: AppColors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'I have read and understand this disclaimer. I accept full responsibility for my actions while using LapTime.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Accept button
              FilledButton(
                onPressed: _accepted && !_isSubmitting ? _onAccept : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('Accept and Continue'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAccept() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not signed in. Please restart the app.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final db = ref.read(databaseProvider);
      final client = ref.read(supabaseClientProvider);

      // Ensure local profile exists (safety net for existing users)
      final profileRepo = ProfileRepository(db, client);
      final meta = user.userMetadata;
      final name = meta?['full_name'] as String? ??
          meta?['name'] as String? ??
          user.email?.split('@').first ??
          'Driver';
      await profileRepo.ensureLocalProfile(userId: user.id, displayName: name);

      final repo = DisclaimerRepository(db, client);

      final packageInfo = await PackageInfo.fromPlatform();

      await repo.accept(
        userId: user.id,
        appVersion: packageInfo.version,
      );

      // Invalidate the provider so router re-evaluates
      ref.invalidate(hasAcceptedDisclaimerProvider);

      // Navigate directly as a fallback in case the redirect doesn't fire
      if (mounted) {
        GoRouter.of(context).go('/record');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

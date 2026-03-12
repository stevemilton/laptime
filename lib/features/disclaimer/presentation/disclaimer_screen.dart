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
import '../../auth/presentation/auth_controller.dart';
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
  bool _isSubmitting = false;
  bool _hasScrolledToBottom = false;
  String _disclaimerText = '';
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDisclaimer();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasScrolledToBottom) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 20) {
      setState(() => _hasScrolledToBottom = true);
    }
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
        title: const Text('Disclaimer'),
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
                        'Please read this carefully before using TestTrack.',
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
                    controller: _scrollController,
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

              // I Agree button
              FilledButton(
                onPressed: _hasScrolledToBottom && !_isSubmitting ? _onAgree : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('I Agree'),
              ),

              const SizedBox(height: 12),

              // I Disagree button
              OutlinedButton(
                onPressed: _isSubmitting ? null : _onDisagree,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const Text('I Disagree'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAgree() async {
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

  Future<void> _onDisagree() async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) {
      GoRouter.of(context).go('/login');
    }
  }
}

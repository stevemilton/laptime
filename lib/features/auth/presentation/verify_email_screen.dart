import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';

/// OTP verification screen shown after email sign-up.
///
/// The user enters the 6-digit code sent to their email via Resend.
/// On success, Supabase creates a session and the router redirects.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isVerifying = false;
  bool _isResending = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    final code = _code;
    if (code.length != 6) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.signup,
      );
      // Session is now active — router will redirect automatically.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verification code resent to ${widget.email}',
              style: const TextStyle(color: AppColors.white),
            ),
            backgroundColor: AppColors.purple,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    // Auto-submit when all 6 digits entered
    if (_code.length == 6) {
      _verify();
    }
  }

  void _onKeyPress(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.purpleLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: const Icon(
                  LucideIcons.mail,
                  size: 32,
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Check your email',
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.purpleDeep,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a 6-digit code to',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              Text(
                widget.email,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),

              // OTP input
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  return Container(
                    width: 48,
                    height: 56,
                    margin: EdgeInsets.only(
                      left: i == 0 ? 0 : (i == 3 ? 16 : 8),
                    ),
                    child: RawKeyboardListener(
                      focusNode: FocusNode(),
                      onKey: (event) => _onKeyPress(i, event),
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: AppTypography.headlineSmall.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.sm),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.sm),
                            borderSide: const BorderSide(
                                color: AppColors.purple, width: 2),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (v) => _onDigitChanged(i, v),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              // Error
              if (_error != null) ...[
                Text(
                  _error!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],

              // Verify button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isVerifying || _code.length != 6
                      ? null
                      : _verify,
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Verify'),
                ),
              ),
              const SizedBox(height: 16),

              // Resend
              GestureDetector(
                onTap: _isResending ? null : _resend,
                child: _isResending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.purple,
                        ),
                      )
                    : Text(
                        'Resend code',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const Spacer(flex: 3),

              // Back to login
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () => context.go('/login'),
                  child: Text(
                    'Back to sign in',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

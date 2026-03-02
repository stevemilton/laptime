import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import 'auth_controller.dart';

/// Full-screen login page with Apple, Google, and email sign-in options.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _showEmailForm = false;
  bool _isSignUp = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    // Listen for errors
    ref.listen(authControllerProvider, (prev, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _formatError(next.error),
              style: const TextStyle(color: AppColors.white),
            ),
            backgroundColor: AppColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo / App Name
              Text(
                'LapTime',
                style: AppTypography.displayMedium.copyWith(
                  color: AppColors.purpleDeep,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Track your track days',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),

              const Spacer(flex: 3),

              // Auth buttons
              if (!_showEmailForm) ...[
                // Apple Sign In
                _SocialButton(
                  label: 'Continue with Apple',
                  icon: LucideIcons.apple,
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.white,
                  isLoading: isLoading,
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).signInWithApple(),
                ),
                const SizedBox(height: 12),

                // Google Sign In
                _SocialButton(
                  label: 'Continue with Google',
                  icon: LucideIcons.chrome,
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.textPrimary,
                  borderColor: AppColors.border,
                  isLoading: isLoading,
                  onTap: () => ref
                      .read(authControllerProvider.notifier)
                      .signInWithGoogle(),
                ),
                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const SizedBox(height: 24),

                // Email option
                _SocialButton(
                  label: 'Continue with email',
                  icon: LucideIcons.mail,
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.textPrimary,
                  borderColor: AppColors.border,
                  isLoading: false,
                  onTap: () => setState(() => _showEmailForm = true),
                ),
              ] else ...[
                // Email form
                _buildEmailForm(isLoading),
              ],

              const Spacer(flex: 2),

              // Footer
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm(bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => setState(() {
                _showEmailForm = false;
                _isSignUp = false;
              }),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.arrowLeft,
                      size: 16, color: AppColors.purple),
                  const SizedBox(width: 4),
                  Text(
                    'Back',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name field (sign up only)
          if (_isSignUp) ...[
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                prefixIcon: Icon(LucideIcons.user, size: 18),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
          ],

          // Email field
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(LucideIcons.mail, size: 18),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || !v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Password field
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(LucideIcons.lock, size: 18),
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            validator: (v) {
              if (v == null || v.length < 6) return 'At least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Submit button
          FilledButton(
            onPressed: isLoading ? null : _submitEmail,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : Text(_isSignUp ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: 12),

          // Toggle sign in / sign up
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _isSignUp = !_isSignUp),
              child: Text(
                _isSignUp
                    ? 'Already have an account? Sign in'
                    : "Don't have an account? Sign up",
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.purple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submitEmail() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final controller = ref.read(authControllerProvider.notifier);
    if (_isSignUp) {
      controller.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );
    } else {
      controller.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    }
  }

  String _formatError(Object? error) {
    if (error is AuthException) return error.message;
    return error?.toString() ?? 'An error occurred';
  }
}

/// Reusable social auth button.
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.isLoading,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: borderColor != null
                  ? Border.all(color: borderColor!)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foregroundColor),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: AppTypography.bodyLarge.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

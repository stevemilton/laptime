import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../profile/data/profile_providers.dart';
import '../../profile/data/ensure_local_profile.dart';
import '../data/auth_repository.dart';

/// Provides the AuthRepository instance.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});

/// Whether the user is currently signed in.
///
/// Watches [authStateProvider] from supabase_provider.dart (single source of truth).
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session != null,
    loading: () => false,
    error: (_, _) => false,
  );
});

/// Controller for auth actions (sign in, sign up, sign out).
///
/// Exposes an [AsyncValue<void>] to reflect loading/error state in the UI.
final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  /// Ensures a local profile row exists in Drift after sign-in.
  Future<void> _ensureLocalProfile() async {
    final repo = _ref.read(profileRepositoryProvider);
    await ensureLocalProfile(repo);
  }

  /// Sign in with Apple.
  Future<void> signInWithApple() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final AuthResponse response = await _repo.signInWithApple();
      if (response.user == null) {
        throw AuthException('Apple Sign-In completed but no user returned');
      }
      await _ensureLocalProfile();
    });
  }

  /// Sign in with Google.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final AuthResponse response = await _repo.signInWithGoogle();
      if (response.user == null) {
        throw AuthException('Google Sign-In completed but no user returned');
      }
      await _ensureLocalProfile();
    });
  }

  /// Sign in with email/password.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final AuthResponse response = await _repo.signInWithEmail(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw AuthException('Sign-in completed but no user returned');
      }
      await _ensureLocalProfile();
    });
  }

  /// Sign up with email/password.
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final AuthResponse response = await _repo.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (response.user == null) {
        throw AuthException('Sign-up completed but no user returned');
      }
      await _ensureLocalProfile();
    });
  }

  /// Send password reset email.
  Future<void> resetPassword(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.resetPassword(email));
  }

  /// Sign out.
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.signOut());
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../profile/data/profile_repository.dart';
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
    // While the stream is loading, check the synchronous persisted session
    // so returning users aren't briefly flashed to the login screen.
    loading: () => Supabase.instance.client.auth.currentSession != null,
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
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final db = _ref.read(databaseProvider);
      final client = _ref.read(supabaseClientProvider);
      final repo = ProfileRepository(db, client);

      // Derive a display name from user metadata or email
      final meta = user.userMetadata;
      final name = meta?['full_name'] as String? ??
          meta?['name'] as String? ??
          user.email?.split('@').first ??
          'Driver';

      await repo.ensureLocalProfile(userId: user.id, displayName: name);
    } catch (e) {
      debugPrint('Failed to ensure local profile: $e');
    }
  }

  /// Sign in with Apple.
  Future<void> signInWithApple() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.signInWithApple();
      await _ensureLocalProfile();
    });
  }

  /// Sign in with Google.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.signInWithGoogle();
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
      await _repo.signInWithEmail(email: email, password: password);
      await _ensureLocalProfile();
    });
  }

  /// Sign up with email/password.
  ///
  /// Returns the email address if verification is needed (no session),
  /// or null if a session was created immediately.
  Future<String?> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncLoading();
    String? pendingEmail;
    state = await AsyncValue.guard(() async {
      final response = await _repo.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      // If Supabase requires email confirmation, signUp returns a user
      // but no session. Signal the caller to show verification screen.
      if (response.session == null && response.user != null) {
        pendingEmail = email;
        return;
      }
      await _ensureLocalProfile();
    });
    return pendingEmail;
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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Repository handling all authentication operations via Supabase Auth.
///
/// Supports Apple Sign-In, Google Sign-In, and email/password.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Current user, or null if not authenticated.
  User? get currentUser => _client.auth.currentUser;

  /// Stream of auth state changes.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  // ── Apple Sign-In ──

  Future<AuthResponse> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw AuthException('Apple Sign-In failed: no identity token');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: '', // Supabase handles nonce verification internally
    );
  }

  // ── Google Sign-In ──

  Future<AuthResponse> signInWithGoogle() async {
    // iOS client ID from GoogleService-Info.plist
    const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    // Web client ID for Supabase OAuth
    const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

    final googleSignIn = GoogleSignIn(
      clientId: iosClientId.isNotEmpty ? iosClientId : null,
      serverClientId: webClientId.isNotEmpty ? webClientId : null,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw AuthException('Google Sign-In was cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw AuthException('Google Sign-In failed: no ID token');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  // ── Email/Password ──

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: displayName != null ? {'full_name': displayName} : null,
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> resetPassword(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

  // ── Sign Out ──

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      // Force local sign out even if remote fails
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }
}

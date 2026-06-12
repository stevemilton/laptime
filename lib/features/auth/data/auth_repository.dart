import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/env.dart';

/// Generate a cryptographically secure random nonce.
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = math.Random.secure();
  return List.generate(length, (_) => charset[random.nextInt(charset.length)])
      .join();
}

/// SHA-256 hash a string.
String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

/// Result of a social (Apple/Google) sign-in attempt.
///
/// [response] is null when the user cancelled the flow - cancellation is
/// a no-op, not an error.
class SocialSignInResult {
  const SocialSignInResult({this.response, this.fullName});

  final AuthResponse? response;

  /// Full name supplied by the identity provider, if any. Apple only
  /// provides this on the very first authorization.
  final String? fullName;

  bool get cancelled => response == null;
}

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

  Future<SocialSignInResult> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256ofString(rawNonce);

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User backed out of the Apple sheet - not an error.
        return const SocialSignInResult();
      }
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw AuthException('Apple Sign-In failed: no identity token');
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple only supplies the name on the very first authorization -
    // persist it to user metadata immediately or it is lost forever.
    String? fullName;
    final givenName = credential.givenName;
    if (givenName != null && givenName.isNotEmpty) {
      final familyName = credential.familyName;
      fullName = (familyName == null || familyName.isEmpty)
          ? givenName
          : '$givenName $familyName';
      try {
        await _client.auth.updateUser(
          UserAttributes(data: {'full_name': fullName}),
        );
      } catch (e) {
        debugPrint('Failed to persist Apple full name: $e');
      }
    }

    return SocialSignInResult(response: response, fullName: fullName);
  }

  // ── Google Sign-In ──

  Future<SocialSignInResult> signInWithGoogle() async {
    final iosClientId = Env.googleIosClientId;
    final webClientId = Env.googleWebClientId;

    final googleSignIn = GoogleSignIn(
      clientId: iosClientId.isNotEmpty ? iosClientId : null,
      serverClientId: webClientId.isNotEmpty ? webClientId : null,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      // User dismissed the account picker - not an error.
      return const SocialSignInResult();
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) {
      throw AuthException('Google Sign-In failed: no ID token');
    }

    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    return SocialSignInResult(response: response);
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

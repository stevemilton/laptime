import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides the Supabase client instance.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Streams the current auth state (signed in, signed out, etc.).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// The currently signed-in user's id, or null.
///
/// Selects only the user id from the auth stream so that token refreshes
/// (same user, new token) do not invalidate dependents.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authStateProvider.select((state) => state.valueOrNull?.session?.user.id),
  );
});

/// Provides the currently signed-in user, or null.
///
/// Watches [currentUserIdProvider] so that it re-evaluates only when the
/// user actually signs in or out - hourly tokenRefreshed events do not
/// cascade into dependent providers.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(currentUserIdProvider);
  return Supabase.instance.client.auth.currentUser;
});

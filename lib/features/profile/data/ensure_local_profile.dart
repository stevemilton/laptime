import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_repository.dart';

/// Ensures a local profile row exists in Drift for the current Supabase user.
///
/// Used after sign-in and on cold start when a session is restored.
Future<void> ensureLocalProfile(ProfileRepository repo) async {
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

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

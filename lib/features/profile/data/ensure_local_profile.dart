import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_repository.dart';

/// Ensures a local profile row exists in Drift for the current Supabase user.
///
/// Used after sign-in and on cold start when a session is restored.
/// [fullName] overrides the metadata lookup - used on first Apple sign-in,
/// where the provider-supplied name may not be in metadata yet.
Future<void> ensureLocalProfile(ProfileRepository repo,
    {String? fullName}) async {
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata;
    final name = (fullName != null && fullName.isNotEmpty ? fullName : null) ??
        meta?['full_name'] as String? ??
        meta?['name'] as String? ??
        user.email?.split('@').first ??
        'Driver';

    await repo.ensureLocalProfile(userId: user.id, displayName: name);
  } catch (e) {
    debugPrint('Failed to ensure local profile: $e');
  }
}

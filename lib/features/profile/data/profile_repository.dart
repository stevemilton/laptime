import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';

/// Repository for user profile operations.
///
/// Reads from local Drift DB (offline-first), writes enqueue sync to Supabase.
class ProfileRepository {
  ProfileRepository(this._db, this._client);

  final AppDatabase _db;
  // ignore: unused_field
  final SupabaseClient _client; // Used for future avatar upload

  /// Get the current user's profile from local DB.
  Future<LocalProfile?> getProfile(String userId) {
    return _db.getProfile(userId);
  }

  /// Watch the user's profile for reactive UI updates.
  Stream<LocalProfile?> watchProfile(String userId) {
    return (_db.select(_db.localProfiles)
          ..where((t) => t.id.equals(userId)))
        .watchSingleOrNull();
  }

  /// Update display name and handle.
  Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? handle,
    String? avatarUrl,
  }) async {
    await (_db.update(_db.localProfiles)
          ..where((t) => t.id.equals(userId)))
        .write(LocalProfilesCompanion(
      displayName: displayName != null ? Value(displayName) : const Value.absent(),
      handle: handle != null ? Value(handle) : const Value.absent(),
      avatarUrl: avatarUrl != null ? Value(avatarUrl) : const Value.absent(),
    ));

    // Enqueue sync
    final payload = <String, dynamic>{'id': userId};
    if (displayName != null) payload['display_name'] = displayName;
    if (handle != null) payload['handle'] = handle;
    if (avatarUrl != null) payload['avatar_url'] = avatarUrl;

    await _db.enqueueSync(
      targetTable: 'profiles',
      operation: 'update',
      recordId: userId,
      payloadJson: jsonEncode(payload),
    );
  }

  /// Ensure a local profile exists (create if missing after auth).
  Future<void> ensureLocalProfile({
    required String userId,
    required String displayName,
  }) async {
    final existing = await getProfile(userId);
    if (existing != null) return;

    await _db.into(_db.localProfiles).insert(
      LocalProfilesCompanion.insert(
        id: userId,
        displayName: Value(displayName),
      ),
    );
  }

  /// Get user stats (total sessions, circuits, laps, P1s).
  Future<ProfileStats> getStats(String userId) async {
    final sessions = await (_db.select(_db.localSessions)
          ..where((t) => t.userId.equals(userId)))
        .get();

    // Session IDs for future use
    final _ = sessions.map((s) => s.id).toSet();

    // Count distinct circuits
    final circuits = sessions
        .where((s) => s.circuitId != null)
        .map((s) => s.circuitId!)
        .toSet()
        .length;

    // Count laps
    int totalLaps = 0;
    int p1Count = 0;
    for (final session in sessions) {
      final laps = await _db.getSessionLaps(session.id);
      totalLaps += laps.length;
      p1Count += laps.where((l) => l.isPersonalBest == true).length;
    }

    return ProfileStats(
      sessionCount: sessions.length,
      circuitCount: circuits,
      lapCount: totalLaps,
      p1Count: p1Count,
    );
  }
}

/// Aggregate stats for the profile screen.
class ProfileStats {
  ProfileStats({
    required this.sessionCount,
    required this.circuitCount,
    required this.lapCount,
    required this.p1Count,
  });

  final int sessionCount;
  final int circuitCount;
  final int lapCount;
  final int p1Count;
}

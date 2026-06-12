import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/sync_payloads.dart';

/// Repository for user profile operations.
///
/// Reads from local Drift DB (offline-first), writes enqueue sync to Supabase.
class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

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

  /// Update display name, handle, and avatar.
  ///
  /// Fields use Drift's [Value] wrapper so callers can distinguish
  /// "leave unchanged" ([Value.absent]) from "clear" (`Value(null)`),
  /// which makes "Remove Photo" actually work.
  ///
  /// Uses upsert: if the profile row doesn't exist yet it will be created,
  /// preventing silent UPDATE-on-zero-rows failures. After the local write
  /// the FULL row is enqueued - the sync engine executes updates as
  /// upserts, so partial payloads are unsafe.
  Future<void> updateProfile({
    required String userId,
    Value<String> displayName = const Value.absent(),
    Value<String?> handle = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
  }) async {
    final existing = await getProfile(userId);

    await _db.into(_db.localProfiles).insertOnConflictUpdate(
      LocalProfilesCompanion.insert(
        id: userId,
        displayName: Value(displayName.present
            ? displayName.value
            : existing?.displayName ?? 'Driver'),
        handle: handle.present ? handle : Value(existing?.handle),
        avatarUrl: avatarUrl.present ? avatarUrl : Value(existing?.avatarUrl),
      ),
    );

    // Enqueue the full row, read back from Drift.
    final row = await getProfile(userId);
    if (row == null) return;
    await _db.enqueueSync(
      targetTable: 'profiles',
      operation: 'update',
      recordId: userId,
      payloadJson: jsonEncode(SyncPayloads.profile(row)),
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

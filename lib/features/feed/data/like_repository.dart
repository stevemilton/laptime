import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Repository for session likes with offline-first sync.
class LikeRepository {
  LikeRepository(this._db);

  final AppDatabase _db;

  /// Toggle a like: if already liked, remove it; otherwise, add it.
  /// Returns `true` if the session is now liked, `false` if unliked.
  Future<bool> toggleLike(String sessionId, String userId) async {
    final existing = await (_db.select(_db.localSessionLikes)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.userId.equals(userId)))
        .getSingleOrNull();

    if (existing != null) {
      // Unlike — delete locally + enqueue sync
      await (_db.delete(_db.localSessionLikes)
            ..where((t) =>
                t.sessionId.equals(sessionId) & t.userId.equals(userId)))
          .go();

      await _db.enqueueSync(
        targetTable: 'session_likes',
        operation: 'delete',
        recordId: '${sessionId}_$userId',
        payloadJson: jsonEncode({
          'session_id': sessionId,
          'user_id': userId,
        }),
      );

      return false;
    } else {
      // Like — insert locally + enqueue sync. insertOnConflictUpdate guards
      // against a double-tap racing the existence check above.
      await _db.into(_db.localSessionLikes).insertOnConflictUpdate(
        LocalSessionLikesCompanion.insert(
          sessionId: sessionId,
          userId: userId,
        ),
      );

      await _db.enqueueSync(
        targetTable: 'session_likes',
        operation: 'insert',
        recordId: '${sessionId}_$userId',
        payloadJson: jsonEncode({
          'session_id': sessionId,
          'user_id': userId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      return true;
    }
  }
}

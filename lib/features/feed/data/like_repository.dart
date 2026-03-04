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

    final payload = jsonEncode({
      'session_id': sessionId,
      'user_id': userId,
    });

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
        payloadJson: payload,
      );

      return false;
    } else {
      // Like — insert locally + enqueue sync
      await _db.into(_db.localSessionLikes).insert(
        LocalSessionLikesCompanion.insert(
          sessionId: sessionId,
          userId: userId,
        ),
      );

      await _db.enqueueSync(
        targetTable: 'session_likes',
        operation: 'insert',
        recordId: '${sessionId}_$userId',
        payloadJson: payload,
      );

      return true;
    }
  }
}

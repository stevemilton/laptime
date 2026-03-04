import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

/// A comment with display info for the UI.
class CommentItem {
  const CommentItem({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String body;
  final DateTime createdAt;
}

/// Repository for session comments with offline-first writes and Supabase reads.
class CommentRepository {
  CommentRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;
  static const _uuid = Uuid();

  /// Add a comment to a session. Writes locally + enqueues sync.
  Future<String> addComment({
    required String sessionId,
    required String userId,
    required String body,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.into(_db.localSessionComments).insert(
      LocalSessionCommentsCompanion.insert(
        id: id,
        sessionId: sessionId,
        userId: userId,
        body: body,
        createdAt: Value(now),
      ),
    );

    await _db.enqueueSync(
      targetTable: 'session_comments',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'session_id': sessionId,
        'user_id': userId,
        'body': body,
        'created_at': now.toIso8601String(),
      }),
    );

    return id;
  }

  /// Delete a comment. Removes locally + enqueues sync.
  Future<void> deleteComment(String commentId) async {
    await (_db.delete(_db.localSessionComments)
          ..where((t) => t.id.equals(commentId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'session_comments',
      operation: 'delete',
      recordId: commentId,
      payloadJson: jsonEncode({'id': commentId}),
    );
  }

  /// Fetch comments for a session.
  ///
  /// Merges server results with unsynced local comments so newly posted
  /// comments appear immediately without waiting for sync.
  Future<List<CommentItem>> getSessionComments(String sessionId) async {
    // Always read local comments first (instant, offline-safe)
    final localComments = await (_db.select(_db.localSessionComments)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    // Try to fetch from server for other users' comments
    List<CommentItem> serverComments = [];
    try {
      final response = await _client
          .from('session_comments')
          .select('*, profiles!inner(display_name, avatar_url)')
          .eq('session_id', sessionId)
          .order('created_at', ascending: true);

      serverComments = (response as List).map((json) {
        return CommentItem(
          id: json['id'] as String,
          sessionId: json['session_id'] as String,
          userId: json['user_id'] as String,
          displayName:
              json['profiles']?['display_name'] as String? ?? 'Driver',
          avatarUrl: json['profiles']?['avatar_url'] as String?,
          body: json['body'] as String,
          createdAt: DateTime.parse(json['created_at'] as String),
        );
      }).toList();
    } catch (_) {
      // Offline — fall through to local-only results
    }

    // Merge: use server comments as base, add any local comments not yet on server
    final serverIds = serverComments.map((c) => c.id).toSet();
    final localOnly = localComments.where((lc) => !serverIds.contains(lc.id));

    // Convert local-only comments to CommentItem (no profile join, use userId)
    final localProfile = await _db.getProfile(
      localComments.isNotEmpty ? localComments.first.userId : '',
    );

    final merged = [
      ...serverComments,
      for (final lc in localOnly)
        CommentItem(
          id: lc.id,
          sessionId: lc.sessionId,
          userId: lc.userId,
          displayName: localProfile?.displayName ?? 'You',
          avatarUrl: localProfile?.avatarUrl,
          body: lc.body,
          createdAt: lc.createdAt,
        ),
    ];

    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }
}

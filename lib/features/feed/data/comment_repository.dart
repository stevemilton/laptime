import 'dart:convert';

import 'package:drift/drift.dart';
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

  /// Fetch comments for a session from Supabase (with profile data).
  Future<List<CommentItem>> getSessionComments(String sessionId) async {
    try {
      final response = await _client
          .from('session_comments')
          .select('*, profiles!inner(display_name, avatar_url)')
          .eq('session_id', sessionId)
          .order('created_at', ascending: true);

      return (response as List).map((json) {
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
    } catch (e) {
      return [];
    }
  }
}

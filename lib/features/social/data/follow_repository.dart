import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';

/// Repository for follow/unfollow operations and searching users.
class FollowRepository {
  FollowRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  /// Follow a user.
  Future<void> follow({
    required String followerId,
    required String followingId,
  }) async {
    // Write to local DB. insertOnConflictUpdate keeps a double-tap from
    // failing on the composite primary key.
    await _db.into(_db.localFollows).insertOnConflictUpdate(
      LocalFollowsCompanion.insert(
        followerId: followerId,
        followingId: followingId,
      ),
    );

    // Enqueue sync
    await _db.enqueueSync(
      targetTable: 'follows',
      operation: 'insert',
      recordId: '${followerId}_$followingId',
      payloadJson: jsonEncode({
        'follower_id': followerId,
        'following_id': followingId,
      }),
    );
  }

  /// Unfollow a user.
  Future<void> unfollow({
    required String followerId,
    required String followingId,
  }) async {
    await (_db.delete(_db.localFollows)
          ..where((t) =>
              t.followerId.equals(followerId) &
              t.followingId.equals(followingId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'follows',
      operation: 'delete',
      recordId: '${followerId}_$followingId',
      payloadJson: jsonEncode({
        'follower_id': followerId,
        'following_id': followingId,
      }),
    );
  }

  /// Check if the current user follows another user.
  Future<bool> isFollowing({
    required String followerId,
    required String followingId,
  }) async {
    final result = await (_db.select(_db.localFollows)
          ..where((t) =>
              t.followerId.equals(followerId) &
              t.followingId.equals(followingId)))
        .get();
    return result.isNotEmpty;
  }

  /// Get follower count for a user.
  Future<int> getFollowerCount(String userId) async {
    final result = await (_db.select(_db.localFollows)
          ..where((t) => t.followingId.equals(userId)))
        .get();
    return result.length;
  }

  /// Get following count for a user.
  Future<int> getFollowingCount(String userId) async {
    final result = await (_db.select(_db.localFollows)
          ..where((t) => t.followerId.equals(userId)))
        .get();
    return result.length;
  }

  /// Search for users by name or handle (via Supabase).
  Future<List<UserSearchResult>> searchUsers(String query) async {
    // Strip characters that break the PostgREST `.or()` filter grammar.
    final sanitized = _sanitizeSearchQuery(query);
    if (sanitized.isEmpty) return [];

    try {
      final response = await _client
          .from('profiles')
          .select()
          .or('display_name.ilike.%$sanitized%,handle.ilike.%$sanitized%')
          .limit(20);

      return (response as List)
          .map((json) => UserSearchResult.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// Strip characters that break the PostgREST `.or()` filter grammar
/// (`,` separates filters, `(`/`)` group, `.` separates operator parts,
/// `%` is the ilike wildcard).
String _sanitizeSearchQuery(String query) {
  return query.replaceAll(RegExp(r'[,().%\\]'), ' ').trim();
}

/// Search result for a user.
class UserSearchResult {
  UserSearchResult({
    required this.id,
    required this.displayName,
    this.handle,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? handle;
  final String? avatarUrl;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'Driver',
      handle: json['handle'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

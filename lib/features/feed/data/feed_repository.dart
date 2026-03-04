import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A feed item representing a session that appears in the social feed.
class FeedItem {
  FeedItem({
    required this.sessionId,
    required this.userId,
    required this.displayName,
    this.handle,
    this.avatarUrl,
    this.circuitName,
    this.circuitId,
    required this.startedAt,
    this.bestLapMs,
    this.lapCount,
    this.trackCondition,
    this.carMake,
    this.carModel,
    this.isPersonalBest,
    this.likeCount = 0,
    this.isLikedByMe = false,
    this.commentCount = 0,
  });

  final String sessionId;
  final String userId;
  final String displayName;
  final String? handle;
  final String? avatarUrl;
  final String? circuitName;
  final String? circuitId;
  final DateTime startedAt;
  final int? bestLapMs;
  final int? lapCount;
  final String? trackCondition;
  final String? carMake;
  final String? carModel;
  final bool? isPersonalBest;
  final int likeCount;
  final bool isLikedByMe;
  final int commentCount;

  factory FeedItem.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    // Compute best lap from embedded laps array
    final laps = json['laps'] as List? ?? [];
    int? bestLapMs;
    bool hasPersonalBest = false;
    for (final lap in laps) {
      final durationMs = lap['duration_ms'] as int?;
      if (durationMs != null) {
        if (bestLapMs == null || durationMs < bestLapMs) {
          bestLapMs = durationMs;
        }
      }
      if (lap['is_personal_best'] == true) {
        hasPersonalBest = true;
      }
    }

    // Compute like/comment counts from embedded arrays
    final likes = json['session_likes'] as List? ?? [];
    final comments = json['session_comments'] as List? ?? [];
    final isLikedByMe =
        likes.any((like) => like['user_id'] == currentUserId);

    return FeedItem(
      sessionId: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: json['profiles']?['display_name'] as String? ?? 'Driver',
      handle: json['profiles']?['handle'] as String?,
      avatarUrl: json['profiles']?['avatar_url'] as String?,
      circuitName: json['circuits']?['name'] as String? ??
          json['circuit_name'] as String?,
      circuitId: json['circuit_id'] as String?,
      startedAt: DateTime.parse(json['started_at'] as String),
      bestLapMs: bestLapMs,
      lapCount: laps.isNotEmpty ? laps.length : null,
      trackCondition: json['track_condition'] as String?,
      carMake: json['cars']?['make'] as String?,
      carModel: json['cars']?['model'] as String?,
      isPersonalBest: hasPersonalBest ? true : null,
      likeCount: likes.length,
      isLikedByMe: isLikedByMe,
      commentCount: comments.length,
    );
  }
}

/// Full select with social data (likes/comments). Falls back to _baseSelect
/// if PostgREST hasn't picked up the new tables yet.
const _fullSelect =
    '*, profiles!inner(*), circuits(*), cars(*), laps(duration_ms, is_personal_best), session_likes(user_id), session_comments(id)';

/// Base select without social tables — always works.
const _baseSelect =
    '*, profiles!inner(*), circuits(*), cars(*), laps(duration_ms, is_personal_best)';

/// Repository for the social feed.
///
/// Fetches public sessions from followed users, nearby users, and team members.
class FeedRepository {
  FeedRepository(this._client);

  final SupabaseClient _client;

  String get _currentUserId => _client.auth.currentUser?.id ?? '';

  /// Fetch the "Following" feed - public sessions from users you follow.
  Future<List<FeedItem>> getFollowingFeed({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      // Get followed user IDs
      final follows = await _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);

      final followedIds = (follows as List)
          .map((f) => f['following_id'] as String)
          .toList();

      // Always include the current user so their own sessions appear.
      final feedUserIds = {...followedIds, userId}.toList();

      // Try full query (with social data), fall back to base if it fails
      List response;
      try {
        response = await _client
            .from('sessions')
            .select(_fullSelect)
            .inFilter('user_id', feedUserIds)
            .eq('is_public', true)
            .order('started_at', ascending: false)
            .range(offset, offset + limit - 1);
        debugPrint('[Feed] Following full query OK: ${response.length} items');
      } catch (e) {
        debugPrint('[Feed] Following full query failed ($e), using base query');
        response = await _client
            .from('sessions')
            .select(_baseSelect)
            .inFilter('user_id', feedUserIds)
            .eq('is_public', true)
            .order('started_at', ascending: false)
            .range(offset, offset + limit - 1);
        debugPrint('[Feed] Following base query OK: ${response.length} items');
      }

      return response
          .map((json) => FeedItem.fromJson(
                json as Map<String, dynamic>,
                currentUserId: _currentUserId,
              ))
          .toList();
    } catch (e, stack) {
      debugPrint('[Feed] getFollowingFeed ERROR: $e');
      debugPrint('[Feed] STACK: $stack');
      return [];
    }
  }

  /// Fetch the "Nearby" feed - recent public sessions (location-based later).
  Future<List<FeedItem>> getNearbyFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      List response;
      try {
        response = await _client
            .from('sessions')
            .select(_fullSelect)
            .eq('is_public', true)
            .order('started_at', ascending: false)
            .range(offset, offset + limit - 1);
        debugPrint('[Feed] Nearby full query OK: ${response.length} items');
      } catch (e) {
        debugPrint('[Feed] Nearby full query failed ($e), using base query');
        response = await _client
            .from('sessions')
            .select(_baseSelect)
            .eq('is_public', true)
            .order('started_at', ascending: false)
            .range(offset, offset + limit - 1);
        debugPrint('[Feed] Nearby base query OK: ${response.length} items');
      }

      return response
          .map((json) => FeedItem.fromJson(
                json as Map<String, dynamic>,
                currentUserId: _currentUserId,
              ))
          .toList();
    } catch (e, stack) {
      debugPrint('[Feed] getNearbyFeed ERROR: $e');
      debugPrint('[Feed] STACK: $stack');
      return [];
    }
  }

  /// Fetch the "Teams" feed - sessions from team members.
  Future<List<FeedItem>> getTeamsFeed({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      // Get team IDs the user belongs to
      final memberships = await _client
          .from('team_members')
          .select('team_id')
          .eq('user_id', userId);

      final teamIds = (memberships as List)
          .map((m) => m['team_id'] as String)
          .toList();

      if (teamIds.isEmpty) return [];

      // Get user IDs of team members
      final members = await _client
          .from('team_members')
          .select('user_id')
          .inFilter('team_id', teamIds);

      final memberIds = (members as List)
          .map((m) => m['user_id'] as String)
          .toSet()
          .toList();

      List response;
      try {
        response = await _client
            .from('sessions')
            .select(_fullSelect)
            .inFilter('user_id', memberIds)
            .eq('is_public', true)
            .order('started_at', ascending: false)
            .range(offset, offset + limit - 1);
        debugPrint('[Feed] Teams full query OK: ${response.length} items');
      } catch (e) {
        debugPrint('[Feed] Teams full query failed ($e), using base query');
        response = await _client
            .from('sessions')
            .select(_baseSelect)
            .inFilter('user_id', memberIds)
            .eq('is_public', true)
            .order('started_at', ascending: false)
            .range(offset, offset + limit - 1);
        debugPrint('[Feed] Teams base query OK: ${response.length} items');
      }

      return response
          .map((json) => FeedItem.fromJson(
                json as Map<String, dynamic>,
                currentUserId: _currentUserId,
              ))
          .toList();
    } catch (e, stack) {
      debugPrint('[Feed] getTeamsFeed ERROR: $e');
      debugPrint('[Feed] STACK: $stack');
      return [];
    }
  }
}

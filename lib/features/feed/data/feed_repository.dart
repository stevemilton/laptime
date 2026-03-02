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
    required this.startedAt,
    this.bestLapMs,
    this.lapCount,
    this.trackCondition,
    this.carMake,
    this.carModel,
    this.isPersonalBest,
  });

  final String sessionId;
  final String userId;
  final String displayName;
  final String? handle;
  final String? avatarUrl;
  final String? circuitName;
  final DateTime startedAt;
  final int? bestLapMs;
  final int? lapCount;
  final String? trackCondition;
  final String? carMake;
  final String? carModel;
  final bool? isPersonalBest;

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    return FeedItem(
      sessionId: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: json['profiles']?['display_name'] as String? ?? 'Driver',
      handle: json['profiles']?['handle'] as String?,
      avatarUrl: json['profiles']?['avatar_url'] as String?,
      circuitName: json['circuits']?['name'] as String?,
      startedAt: DateTime.parse(json['started_at'] as String),
      bestLapMs: json['best_lap_ms'] as int?,
      lapCount: json['lap_count'] as int?,
      trackCondition: json['track_condition'] as String?,
      carMake: json['cars']?['make'] as String?,
      carModel: json['cars']?['model'] as String?,
      isPersonalBest: json['is_personal_best'] as bool?,
    );
  }
}

/// Repository for the social feed.
///
/// Fetches public sessions from followed users, nearby users, and team members.
class FeedRepository {
  FeedRepository(this._client);

  final SupabaseClient _client;

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

      if (followedIds.isEmpty) return [];

      final response = await _client
          .from('sessions')
          .select('*, profiles!inner(*), circuits(*), cars(*)')
          .inFilter('user_id', followedIds)
          .eq('is_public', true)
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Fetch the "Nearby" feed - recent public sessions (location-based later).
  Future<List<FeedItem>> getNearbyFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('sessions')
          .select('*, profiles!inner(*), circuits(*), cars(*)')
          .eq('is_public', true)
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
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

      final response = await _client
          .from('sessions')
          .select('*, profiles!inner(*), circuits(*), cars(*)')
          .inFilter('user_id', memberIds)
          .eq('is_public', true)
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List)
          .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

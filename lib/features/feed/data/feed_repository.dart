import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';

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
    int likeCount = 0,
    bool isLikedByMe = false,
    int commentCount = 0,
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
      likeCount: likeCount,
      isLikedByMe: isLikedByMe,
      commentCount: commentCount,
    );
  }
}

/// Full select with social count aggregates. Falls back to _baseSelect
/// only when PostgREST reports the social tables/columns as missing.
const _fullSelect =
    '*, profiles!inner(*), circuits(*), cars(*), laps(duration_ms, is_personal_best), session_likes(count), session_comments(count)';

/// Base select without social tables — always works.
const _baseSelect =
    '*, profiles!inner(*), circuits(*), cars(*), laps(duration_ms, is_personal_best)';

/// Repository for the social feed.
///
/// Fetches public sessions from followed users, nearby users, and team members.
/// Like/comment counts use PostgREST count embeds; "liked by me" is fetched
/// separately for just the page's session ids and merged with pending local
/// likes so cold starts show the user's own likes.
class FeedRepository {
  FeedRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  String get _currentUserId => _client.auth.currentUser?.id ?? '';

  /// Fetch the "Following" feed - public sessions from users you follow.
  Future<List<FeedItem>> getFollowingFeed({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
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

    return _fetchSessions(userIds: feedUserIds, limit: limit, offset: offset);
  }

  /// Fetch the "Nearby" feed - recent public sessions (location-based later).
  Future<List<FeedItem>> getNearbyFeed({
    int limit = 20,
    int offset = 0,
  }) {
    return _fetchSessions(userIds: null, limit: limit, offset: offset);
  }

  /// Fetch the "Teams" feed - sessions from team members.
  Future<List<FeedItem>> getTeamsFeed({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
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

    return _fetchSessions(userIds: memberIds, limit: limit, offset: offset);
  }

  // ── Private Helpers ──

  /// Fetch one page of public sessions, optionally restricted to [userIds],
  /// and hydrate like/comment state. Errors propagate to the caller so the
  /// UI can show a retry-able error state.
  Future<List<FeedItem>> _fetchSessions({
    required List<String>? userIds,
    required int limit,
    required int offset,
  }) async {
    var includesSocial = true;
    List<Map<String, dynamic>> rows;
    try {
      rows = await _runQuery(_fullSelect, userIds, limit, offset);
    } catch (e) {
      // Only fall back to the base select when the social tables/columns
      // are missing; rethrow everything else (network, RLS, ...).
      if (!_isMissingSchemaError(e)) rethrow;
      includesSocial = false;
      rows = await _runQuery(_baseSelect, userIds, limit, offset);
    }

    final sessionIds = [for (final row in rows) row['id'] as String];
    final likedRemotely = includesSocial
        ? await _fetchMyRemoteLikes(sessionIds)
        : <String>{};
    final likedLocally = await _fetchMyLocalLikes(sessionIds);

    return [
      for (final row in rows)
        _itemFromJson(
          row,
          likedRemotely: likedRemotely,
          likedLocally: likedLocally,
        ),
    ];
  }

  Future<List<Map<String, dynamic>>> _runQuery(
    String select,
    List<String>? userIds,
    int limit,
    int offset,
  ) async {
    var query = _client.from('sessions').select(select);
    if (userIds != null) {
      query = query.inFilter('user_id', userIds);
    }
    return await query
        .eq('is_public', true)
        .order('started_at', ascending: false)
        .range(offset, offset + limit - 1);
  }

  FeedItem _itemFromJson(
    Map<String, dynamic> json, {
    required Set<String> likedRemotely,
    required Set<String> likedLocally,
  }) {
    final sessionId = json['id'] as String;
    final remoteLiked = likedRemotely.contains(sessionId);
    final localLiked = likedLocally.contains(sessionId);

    var likeCount = _embeddedCount(json['session_likes']);
    if (localLiked && !remoteLiked) {
      // Pending local like that hasn't synced yet — not in the server count.
      likeCount += 1;
    }

    return FeedItem.fromJson(
      json,
      likeCount: likeCount,
      isLikedByMe: remoteLiked || localLiked,
      commentCount: _embeddedCount(json['session_comments']),
    );
  }

  /// Session ids in [sessionIds] the current user has liked on the server.
  Future<Set<String>> _fetchMyRemoteLikes(List<String> sessionIds) async {
    final userId = _currentUserId;
    if (userId.isEmpty || sessionIds.isEmpty) return {};

    final rows = await _client
        .from('session_likes')
        .select('session_id')
        .eq('user_id', userId)
        .inFilter('session_id', sessionIds);

    return {for (final row in rows as List) row['session_id'] as String};
  }

  /// Session ids in [sessionIds] the current user has liked locally
  /// (including likes still waiting in the sync queue).
  Future<Set<String>> _fetchMyLocalLikes(List<String> sessionIds) async {
    final userId = _currentUserId;
    if (userId.isEmpty || sessionIds.isEmpty) return {};

    final rows = await (_db.select(_db.localSessionLikes)
          ..where((t) => t.userId.equals(userId)))
        .get();

    final idSet = sessionIds.toSet();
    return {
      for (final row in rows)
        if (idSet.contains(row.sessionId)) row.sessionId,
    };
  }

  /// Parse a PostgREST count embed (`table(count)` → `[{'count': n}]`).
  /// Falls back to the row count when full rows were embedded.
  int _embeddedCount(dynamic embedded) {
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map && first.containsKey('count')) {
        return first['count'] as int? ?? 0;
      }
      return embedded.length;
    }
    return 0;
  }

  /// Whether [error] is a PostgrestException for a missing relation/column.
  bool _isMissingSchemaError(Object error) {
    if (error is! PostgrestException) return false;
    final code = error.code;
    // PGRST200: missing relationship, PGRST204: missing column,
    // 42P01: undefined table, 42703: undefined column.
    return code == 'PGRST200' ||
        code == 'PGRST204' ||
        code == '42P01' ||
        code == '42703';
  }
}

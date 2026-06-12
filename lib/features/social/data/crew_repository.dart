import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/utils/invite_code_utils.dart';

const _uuid = Uuid();

// ── Data Models ──

class CrewInfo {
  CrewInfo({
    required this.id,
    required this.teamId,
    required this.name,
    required this.inviteCode,
    required this.memberCount,
    this.isCurrentUserMember = false,
  });

  final String id;
  final String teamId;
  final String name;
  final String inviteCode;
  final int memberCount;
  final bool isCurrentUserMember;
}

class CrewMemberInfo {
  CrewMemberInfo({
    required this.crewId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.displayName,
    this.handle,
    this.avatarUrl,
  });

  final String crewId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final String displayName;
  final String? handle;
  final String? avatarUrl;
}

// ── Repository ──

class CrewRepository {
  CrewRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  Future<CrewInfo> createCrew({
    required String teamId,
    required String name,
  }) async {
    if (name.length < 2 || name.length > 100) {
      throw ArgumentError('Crew name must be 2-100 characters');
    }

    final id = _uuid.v4();
    final inviteCode = generateInviteCode();

    await _db.into(_db.localCrews).insert(
      LocalCrewsCompanion.insert(
        id: id,
        teamId: teamId,
        name: name,
        inviteCode: inviteCode,
      ),
    );

    await _db.enqueueSync(
      targetTable: 'crews',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'team_id': teamId,
        'name': name,
        'invite_code': inviteCode,
      }),
    );

    return CrewInfo(
      id: id,
      teamId: teamId,
      name: name,
      inviteCode: inviteCode,
      memberCount: 0,
    );
  }

  Future<void> deleteCrew(String crewId) async {
    // Remove all crew members first
    await (_db.delete(_db.localCrewMembers)
          ..where((t) => t.crewId.equals(crewId)))
        .go();

    await (_db.delete(_db.localCrews)
          ..where((t) => t.id.equals(crewId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'crews',
      operation: 'delete',
      recordId: crewId,
      payloadJson: jsonEncode({'id': crewId}),
    );
  }

  /// Remote-first: crews and their members are managed across devices, so
  /// query Supabase, cache results locally, and fall back to the local
  /// cache when the network call fails.
  Future<List<CrewInfo>> getCrewsForTeam(
    String teamId, {
    String? currentUserId,
  }) async {
    try {
      return await _getCrewsForTeamRemote(teamId, currentUserId: currentUserId);
    } catch (_) {
      return _getCrewsForTeamLocal(teamId, currentUserId: currentUserId);
    }
  }

  Future<List<CrewInfo>> _getCrewsForTeamRemote(
    String teamId, {
    String? currentUserId,
  }) async {
    final response = await _client
        .from('crews')
        .select('*, crew_members(user_id)')
        .eq('team_id', teamId)
        .order('name', ascending: true);

    final result = <CrewInfo>[];
    for (final json in (response as List).cast<Map<String, dynamic>>()) {
      await _cacheRemoteCrew(json);

      final memberIds = ((json['crew_members'] as List?) ?? const [])
          .map((m) => m['user_id'] as String)
          .toList();

      result.add(CrewInfo(
        id: json['id'] as String,
        teamId: json['team_id'] as String,
        name: json['name'] as String,
        inviteCode: json['invite_code'] as String,
        memberCount: memberIds.length,
        isCurrentUserMember:
            currentUserId != null && memberIds.contains(currentUserId),
      ));
    }

    return result;
  }

  Future<List<CrewInfo>> _getCrewsForTeamLocal(
    String teamId, {
    String? currentUserId,
  }) async {
    final crews = await (_db.select(_db.localCrews)
          ..where((t) => t.teamId.equals(teamId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();

    final result = <CrewInfo>[];
    for (final crew in crews) {
      final members = await (_db.select(_db.localCrewMembers)
            ..where((t) => t.crewId.equals(crew.id)))
          .get();

      bool isMember = false;
      if (currentUserId != null) {
        isMember = members.any((m) => m.userId == currentUserId);
      }

      result.add(CrewInfo(
        id: crew.id,
        teamId: crew.teamId,
        name: crew.name,
        inviteCode: crew.inviteCode,
        memberCount: members.length,
        isCurrentUserMember: isMember,
      ));
    }

    return result;
  }

  Future<CrewInfo?> getCrew(String crewId, {String? currentUserId}) async {
    final crew = await (_db.select(_db.localCrews)
          ..where((t) => t.id.equals(crewId)))
        .getSingleOrNull();
    if (crew == null) return null;

    final members = await (_db.select(_db.localCrewMembers)
          ..where((t) => t.crewId.equals(crewId)))
        .get();

    bool isMember = false;
    if (currentUserId != null) {
      isMember = members.any((m) => m.userId == currentUserId);
    }

    return CrewInfo(
      id: crew.id,
      teamId: crew.teamId,
      name: crew.name,
      inviteCode: crew.inviteCode,
      memberCount: members.length,
      isCurrentUserMember: isMember,
    );
  }

  /// Remote-first with local-cache fallback, mirroring [getCrewsForTeam].
  Future<List<CrewMemberInfo>> getCrewMembers(String crewId) async {
    try {
      return await _getCrewMembersRemote(crewId);
    } catch (_) {
      return _getCrewMembersLocal(crewId);
    }
  }

  Future<List<CrewMemberInfo>> _getCrewMembersRemote(String crewId) async {
    final response = await _client
        .from('crew_members')
        .select('*, profiles!inner(id, display_name, handle, avatar_url)')
        .eq('crew_id', crewId);

    final result = <CrewMemberInfo>[];
    for (final json in (response as List).cast<Map<String, dynamic>>()) {
      final userId = json['user_id'] as String;
      final role = json['role'] as String? ?? CrewRole.member;
      final joinedAt = _parseTimestamp(json['joined_at']);
      final profile = json['profiles'] as Map<String, dynamic>?;

      await _cacheRemoteProfile(profile);
      await _db.into(_db.localCrewMembers).insertOnConflictUpdate(
        LocalCrewMembersCompanion(
          crewId: Value(crewId),
          userId: Value(userId),
          role: Value(role),
          joinedAt: Value(joinedAt),
        ),
      );

      result.add(CrewMemberInfo(
        crewId: crewId,
        userId: userId,
        role: role,
        joinedAt: joinedAt,
        displayName: profile?['display_name'] as String? ?? 'Driver',
        handle: profile?['handle'] as String?,
        avatarUrl: profile?['avatar_url'] as String?,
      ));
    }

    _sortMembers(result);
    return result;
  }

  Future<List<CrewMemberInfo>> _getCrewMembersLocal(String crewId) async {
    final members = await (_db.select(_db.localCrewMembers)
          ..where((t) => t.crewId.equals(crewId)))
        .get();

    final result = <CrewMemberInfo>[];
    for (final m in members) {
      final profile = await _db.getProfile(m.userId);
      result.add(CrewMemberInfo(
        crewId: m.crewId,
        userId: m.userId,
        role: m.role,
        joinedAt: m.joinedAt,
        displayName: profile?.displayName ?? 'Driver',
        handle: profile?.handle,
        avatarUrl: profile?.avatarUrl,
      ));
    }

    _sortMembers(result);
    return result;
  }

  /// Sort: captains first, then by joinedAt.
  void _sortMembers(List<CrewMemberInfo> members) {
    members.sort((a, b) {
      if (a.role == CrewRole.captain && b.role != CrewRole.captain) return -1;
      if (a.role != CrewRole.captain && b.role == CrewRole.captain) return 1;
      return a.joinedAt.compareTo(b.joinedAt);
    });
  }

  Future<void> joinCrew({
    required String crewId,
    required String userId,
  }) async {
    // Check if already a member
    final existing = await (_db.select(_db.localCrewMembers)
          ..where(
              (t) => t.crewId.equals(crewId) & t.userId.equals(userId)))
        .getSingleOrNull();

    if (existing != null) throw Exception('Already a member of this crew');

    // insertOnConflictUpdate guards against a double-tap racing the
    // existence check above into a duplicate-PK insert.
    await _db.into(_db.localCrewMembers).insertOnConflictUpdate(
      LocalCrewMembersCompanion.insert(
        crewId: crewId,
        userId: userId,
      ),
    );

    await _db.enqueueSync(
      targetTable: 'crew_members',
      operation: 'insert',
      recordId: '${crewId}_$userId',
      payloadJson: jsonEncode({
        'crew_id': crewId,
        'user_id': userId,
        'role': CrewRole.member,
      }),
    );
  }

  Future<void> leaveCrew({
    required String crewId,
    required String userId,
  }) async {
    await (_db.delete(_db.localCrewMembers)
          ..where(
              (t) => t.crewId.equals(crewId) & t.userId.equals(userId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'crew_members',
      operation: 'delete',
      recordId: '${crewId}_$userId',
      payloadJson: jsonEncode({
        'crew_id': crewId,
        'user_id': userId,
      }),
    );
  }

  /// Join a crew by invite code. Auto-joins parent team if not already a member.
  Future<CrewInfo> joinCrewByCode({
    required String code,
    required String userId,
  }) async {
    // Look up crew by code (try local first, then remote)
    final normalizedCode = code.toUpperCase();
    var crew = await (_db.select(_db.localCrews)
          ..where((t) => t.inviteCode.equals(normalizedCode)))
        .getSingleOrNull();

    if (crew == null) {
      // Distinguish "not found" from a network failure.
      Map<String, dynamic>? response;
      try {
        response = await _client
            .from('crews')
            .select()
            .eq('invite_code', normalizedCode)
            .maybeSingle();
      } catch (_) {
        throw Exception(
            'Could not look up the crew. Check your connection and try again.');
      }

      if (response == null) {
        throw Exception('Crew not found with code: $code');
      }

      await _cacheRemoteCrew(response);

      crew = await (_db.select(_db.localCrews)
            ..where((t) => t.inviteCode.equals(normalizedCode)))
          .getSingleOrNull();
    }

    if (crew == null) throw Exception('Crew not found');

    // Auto-join parent team if not already a member
    final teamMembership = await (_db.select(_db.localTeamMembers)
          ..where((t) =>
              t.teamId.equals(crew!.teamId) & t.userId.equals(userId)))
        .getSingleOrNull();

    if (teamMembership == null) {
      await _db.into(_db.localTeamMembers).insertOnConflictUpdate(
        LocalTeamMembersCompanion.insert(
          teamId: crew.teamId,
          userId: userId,
        ),
      );

      await _db.enqueueSync(
        targetTable: 'team_members',
        operation: 'insert',
        recordId: '${crew.teamId}_$userId',
        payloadJson: jsonEncode({
          'team_id': crew.teamId,
          'user_id': userId,
          'role': CrewRole.member,
        }),
      );
    }

    // Join the crew
    await joinCrew(crewId: crew.id, userId: userId);

    final members = await (_db.select(_db.localCrewMembers)
          ..where((t) => t.crewId.equals(crew!.id)))
        .get();

    return CrewInfo(
      id: crew.id,
      teamId: crew.teamId,
      name: crew.name,
      inviteCode: crew.inviteCode,
      memberCount: members.length,
      isCurrentUserMember: true,
    );
  }

  // ── Private Helpers ──

  /// Upsert a remote crew row into the local cache.
  Future<void> _cacheRemoteCrew(Map<String, dynamic> json) {
    return _db.into(_db.localCrews).insertOnConflictUpdate(
      LocalCrewsCompanion(
        id: Value(json['id'] as String),
        teamId: Value(json['team_id'] as String),
        name: Value(json['name'] as String),
        inviteCode: Value(json['invite_code'] as String),
      ),
    );
  }

  /// Upsert a remote profile row into the local cache.
  Future<void> _cacheRemoteProfile(Map<String, dynamic>? json) async {
    final id = json?['id'] as String?;
    if (json == null || id == null) return;
    await _db.into(_db.localProfiles).insertOnConflictUpdate(
      LocalProfilesCompanion(
        id: Value(id),
        displayName: Value(json['display_name'] as String? ?? 'Driver'),
        handle: Value(json['handle'] as String?),
        avatarUrl: Value(json['avatar_url'] as String?),
      ),
    );
  }

  DateTime _parseTimestamp(dynamic value) =>
      value is String ? DateTime.parse(value) : DateTime.now();
}

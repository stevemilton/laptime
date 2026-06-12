import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/utils/invite_code_utils.dart';

const _uuid = Uuid();

// ── Data Models ──

class TeamInfo {
  TeamInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.createdBy,
    this.location,
    this.logoUrl,
    this.verified = false,
    required this.memberCount,
    this.currentUserRole,
    this.pendingRequestCount = 0,
  });

  final String id;
  final String name;
  final String code;
  final String createdBy;
  final String? location;
  final String? logoUrl;
  final bool verified;
  final int memberCount;
  final String? currentUserRole;
  final int pendingRequestCount;
}

class TeamMemberInfo {
  TeamMemberInfo({
    required this.teamId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.displayName,
    this.handle,
    this.avatarUrl,
  });

  final String teamId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final String displayName;
  final String? handle;
  final String? avatarUrl;
}

class TeamSearchResult {
  TeamSearchResult({
    required this.id,
    required this.name,
    this.location,
    this.logoUrl,
    this.verified = false,
    required this.memberCount,
    this.membershipStatus,
  });

  final String id;
  final String name;
  final String? location;
  final String? logoUrl;
  final bool verified;
  final int memberCount;
  final String? membershipStatus; // 'member' | 'pending' | null
}

class JoinRequestInfo {
  JoinRequestInfo({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.status,
    this.message,
    required this.requestedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    required this.displayName,
    this.handle,
    this.avatarUrl,
  });

  final String id;
  final String teamId;
  final String userId;
  final String status;
  final String? message;
  final DateTime requestedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final String displayName;
  final String? handle;
  final String? avatarUrl;
}

// ── Repository ──

class TeamRepository {
  TeamRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  // ── Queries ──

  /// Remote-first: teams/memberships live on the server (other devices add
  /// members), so query Supabase, cache the results locally, and only fall
  /// back to the local cache when the network call fails.
  Future<List<TeamInfo>> getUserTeams(String userId) async {
    try {
      return await _getUserTeamsRemote(userId);
    } catch (_) {
      return _getUserTeamsLocal(userId);
    }
  }

  Future<List<TeamInfo>> _getUserTeamsRemote(String userId) async {
    final response = await _client
        .from('team_members')
        .select('role, joined_at, teams!inner(*, team_members(count))')
        .eq('user_id', userId);

    final memberships = (response as List).cast<Map<String, dynamic>>();
    if (memberships.isEmpty) return [];

    // Pending request counts for teams where the user is an admin.
    final adminTeamIds = [
      for (final m in memberships)
        if (m['role'] == TeamRole.admin)
          (m['teams'] as Map<String, dynamic>)['id'] as String,
    ];
    final pendingCounts = <String, int>{};
    if (adminTeamIds.isNotEmpty) {
      final pending = await _client
          .from('team_join_requests')
          .select('team_id')
          .eq('status', JoinRequestStatus.pending)
          .inFilter('team_id', adminTeamIds);
      for (final row in pending as List) {
        final teamId = row['team_id'] as String;
        pendingCounts[teamId] = (pendingCounts[teamId] ?? 0) + 1;
      }
    }

    final teams = <TeamInfo>[];
    for (final m in memberships) {
      final teamJson = m['teams'] as Map<String, dynamic>;
      final teamId = teamJson['id'] as String;
      final role = m['role'] as String? ?? TeamRole.member;

      // Cache team + own membership locally for offline fallback.
      await _cacheRemoteTeam(teamJson);
      await _db.into(_db.localTeamMembers).insertOnConflictUpdate(
        LocalTeamMembersCompanion(
          teamId: Value(teamId),
          userId: Value(userId),
          role: Value(role),
          joinedAt: Value(_parseTimestamp(m['joined_at'])),
        ),
      );

      teams.add(TeamInfo(
        id: teamId,
        name: teamJson['name'] as String,
        code: teamJson['code'] as String,
        createdBy: teamJson['created_by'] as String? ?? '',
        location: teamJson['location'] as String?,
        logoUrl: teamJson['logo_url'] as String?,
        verified: teamJson['verified'] as bool? ?? false,
        memberCount: _embeddedCount(teamJson['team_members']),
        currentUserRole: role,
        pendingRequestCount: pendingCounts[teamId] ?? 0,
      ));
    }

    return teams;
  }

  Future<List<TeamInfo>> _getUserTeamsLocal(String userId) async {
    final memberships = await (_db.select(_db.localTeamMembers)
          ..where((t) => t.userId.equals(userId)))
        .get();

    if (memberships.isEmpty) return [];

    final teams = <TeamInfo>[];
    for (final membership in memberships) {
      final team = await (_db.select(_db.localTeams)
            ..where((t) => t.id.equals(membership.teamId)))
          .getSingleOrNull();
      if (team == null) continue;

      final memberCount = await _countTeamMembersLocal(team.id);
      final pendingCount = await _countPendingRequestsLocal(team.id);

      teams.add(TeamInfo(
        id: team.id,
        name: team.name,
        code: team.code,
        createdBy: team.createdBy,
        location: team.location,
        logoUrl: team.logoUrl,
        verified: team.verified,
        memberCount: memberCount,
        currentUserRole: membership.role,
        pendingRequestCount: pendingCount,
      ));
    }

    return teams;
  }

  Future<TeamInfo?> getTeam(String teamId, {String? currentUserId}) async {
    final team = await (_db.select(_db.localTeams)
          ..where((t) => t.id.equals(teamId)))
        .getSingleOrNull();
    if (team == null) return null;

    final memberCount = await _countTeamMembers(teamId);
    final pendingCount = await _countPendingRequests(teamId);

    String? role;
    if (currentUserId != null) {
      role = await getUserRoleInTeam(teamId, currentUserId);
    }

    return TeamInfo(
      id: team.id,
      name: team.name,
      code: team.code,
      createdBy: team.createdBy,
      location: team.location,
      logoUrl: team.logoUrl,
      verified: team.verified,
      memberCount: memberCount,
      currentUserRole: role,
      pendingRequestCount: pendingCount,
    );
  }

  /// Remote-first: other devices add/remove members, so query Supabase
  /// (joining profiles), cache locally, and fall back to the local cache
  /// when the network call fails.
  Future<List<TeamMemberInfo>> getTeamMembers(String teamId) async {
    try {
      return await _getTeamMembersRemote(teamId);
    } catch (_) {
      return _getTeamMembersLocal(teamId);
    }
  }

  Future<List<TeamMemberInfo>> _getTeamMembersRemote(String teamId) async {
    final response = await _client
        .from('team_members')
        .select('*, profiles!inner(id, display_name, handle, avatar_url)')
        .eq('team_id', teamId);

    final result = <TeamMemberInfo>[];
    for (final json in (response as List).cast<Map<String, dynamic>>()) {
      final userId = json['user_id'] as String;
      final role = json['role'] as String? ?? TeamRole.member;
      final joinedAt = _parseTimestamp(json['joined_at']);
      final profile = json['profiles'] as Map<String, dynamic>?;

      await _cacheRemoteProfile(profile);
      await _db.into(_db.localTeamMembers).insertOnConflictUpdate(
        LocalTeamMembersCompanion(
          teamId: Value(teamId),
          userId: Value(userId),
          role: Value(role),
          joinedAt: Value(joinedAt),
        ),
      );

      result.add(TeamMemberInfo(
        teamId: teamId,
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

  Future<List<TeamMemberInfo>> _getTeamMembersLocal(String teamId) async {
    final members = await (_db.select(_db.localTeamMembers)
          ..where((t) => t.teamId.equals(teamId)))
        .get();

    final result = <TeamMemberInfo>[];
    for (final m in members) {
      final profile = await _db.getProfile(m.userId);
      result.add(TeamMemberInfo(
        teamId: m.teamId,
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

  /// Sort: admins first, then by joinedAt.
  void _sortMembers(List<TeamMemberInfo> members) {
    members.sort((a, b) {
      if (a.role == TeamRole.admin && b.role != TeamRole.admin) return -1;
      if (a.role != TeamRole.admin && b.role == TeamRole.admin) return 1;
      return a.joinedAt.compareTo(b.joinedAt);
    });
  }

  Future<String?> getUserRoleInTeam(String teamId, String userId) async {
    final membership = await (_db.select(_db.localTeamMembers)
          ..where(
              (t) => t.teamId.equals(teamId) & t.userId.equals(userId)))
        .getSingleOrNull();
    return membership?.role;
  }

  Future<int> getAdminCount(String teamId) async {
    final admins = await (_db.select(_db.localTeamMembers)
          ..where(
              (t) => t.teamId.equals(teamId) & t.role.equals(TeamRole.admin)))
        .get();
    return admins.length;
  }

  // ── Create ──

  Future<TeamInfo> createTeam({
    required String name,
    required String createdBy,
    String? location,
  }) async {
    if (name.length < 2 || name.length > 100) {
      throw ArgumentError('Team name must be 2-100 characters');
    }
    if (location != null && location.length > 200) {
      throw ArgumentError('Location must be at most 200 characters');
    }

    final id = _uuid.v4();
    final code = generateInviteCode();

    await _db.into(_db.localTeams).insert(
      LocalTeamsCompanion.insert(
        id: id,
        name: name,
        code: code,
        createdBy: createdBy,
        location: Value(location),
      ),
    );

    // Add creator as admin
    await _db.into(_db.localTeamMembers).insert(
      LocalTeamMembersCompanion.insert(
        teamId: id,
        userId: createdBy,
        role: const Value(TeamRole.admin),
      ),
    );

    await _db.enqueueSync(
      targetTable: 'teams',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'name': name,
        'code': code,
        'created_by': createdBy,
        if (location != null) 'location': location,
      }),
    );

    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'insert',
      recordId: '${id}_$createdBy',
      payloadJson: jsonEncode({
        'team_id': id,
        'user_id': createdBy,
        'role': TeamRole.admin,
      }),
    );

    return TeamInfo(
      id: id,
      name: name,
      code: code,
      createdBy: createdBy,
      location: location,
      memberCount: 1,
      currentUserRole: TeamRole.admin,
    );
  }

  // ── Update ──

  Future<void> updateTeam({
    required String teamId,
    String? name,
    String? location,
    String? logoUrl,
  }) async {
    if (name != null && (name.length < 2 || name.length > 100)) {
      throw ArgumentError('Team name must be 2-100 characters');
    }
    if (location != null && location.length > 200) {
      throw ArgumentError('Location must be at most 200 characters');
    }

    final companion = LocalTeamsCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      location: location != null ? Value(location) : const Value.absent(),
      logoUrl: logoUrl != null ? Value(logoUrl) : const Value.absent(),
    );

    await (_db.update(_db.localTeams)..where((t) => t.id.equals(teamId)))
        .write(companion);

    final team = await (_db.select(_db.localTeams)
          ..where((t) => t.id.equals(teamId)))
        .getSingleOrNull();
    if (team == null) return;

    await _db.enqueueSync(
      targetTable: 'teams',
      operation: 'update',
      recordId: teamId,
      payloadJson: jsonEncode({
        'id': teamId,
        'name': team.name,
        'code': team.code,
        'created_by': team.createdBy,
        if (team.location != null) 'location': team.location,
        if (team.logoUrl != null) 'logo_url': team.logoUrl,
        'verified': team.verified,
      }),
    );
  }

  // ── Delete ──

  Future<void> deleteTeam(String teamId) async {
    // Cascade: crew members → crews → team members → join requests → team
    final crews = await (_db.select(_db.localCrews)
          ..where((t) => t.teamId.equals(teamId)))
        .get();

    for (final crew in crews) {
      await (_db.delete(_db.localCrewMembers)
            ..where((t) => t.crewId.equals(crew.id)))
          .go();
      await _db.enqueueSync(
        targetTable: 'crews',
        operation: 'delete',
        recordId: crew.id,
        payloadJson: jsonEncode({'id': crew.id}),
      );
    }

    await (_db.delete(_db.localCrews)
          ..where((t) => t.teamId.equals(teamId)))
        .go();

    await (_db.delete(_db.localTeamMembers)
          ..where((t) => t.teamId.equals(teamId)))
        .go();

    await (_db.delete(_db.localTeamJoinRequests)
          ..where((t) => t.teamId.equals(teamId)))
        .go();

    await (_db.delete(_db.localTeams)
          ..where((t) => t.id.equals(teamId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'teams',
      operation: 'delete',
      recordId: teamId,
      payloadJson: jsonEncode({'id': teamId}),
    );
  }

  // ── Join / Leave ──

  Future<void> joinTeamByCode({
    required String code,
    required String userId,
  }) async {
    final normalizedCode = code.toUpperCase();
    var team = await (_db.select(_db.localTeams)
          ..where((t) => t.code.equals(normalizedCode)))
        .getSingleOrNull();

    if (team == null) {
      // Distinguish "not found" from a network failure.
      Map<String, dynamic>? response;
      try {
        response = await _client
            .from('teams')
            .select()
            .eq('code', normalizedCode)
            .maybeSingle();
      } catch (_) {
        throw Exception(
            'Could not look up the team. Check your connection and try again.');
      }

      if (response == null) {
        throw Exception('Team not found with code: $code');
      }

      await _cacheRemoteTeam(response);

      team = await (_db.select(_db.localTeams)
            ..where((t) => t.code.equals(normalizedCode)))
          .getSingleOrNull();
    }

    if (team == null) throw Exception('Team not found');

    final existing = await (_db.select(_db.localTeamMembers)
          ..where(
              (t) => t.teamId.equals(team!.id) & t.userId.equals(userId)))
        .getSingleOrNull();

    if (existing != null) throw Exception('Already a member of this team');

    // insertOnConflictUpdate guards against a double-tap racing the
    // existence check above into a duplicate-PK insert.
    await _db.into(_db.localTeamMembers).insertOnConflictUpdate(
      LocalTeamMembersCompanion.insert(
        teamId: team.id,
        userId: userId,
      ),
    );

    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'insert',
      recordId: '${team.id}_$userId',
      payloadJson: jsonEncode({
        'team_id': team.id,
        'user_id': userId,
        'role': TeamRole.member,
      }),
    );
  }

  Future<void> leaveTeam({
    required String teamId,
    required String userId,
  }) async {
    final role = await getUserRoleInTeam(teamId, userId);
    if (role == TeamRole.admin) {
      final adminCount = await getAdminCount(teamId);
      if (adminCount <= 1) {
        throw Exception(
            'Cannot leave — you are the last admin. Promote another member first.');
      }
    }

    await _removeUserFromTeamAndCrews(teamId: teamId, userId: userId);
  }

  Future<void> removeMember({
    required String teamId,
    required String userId,
    required String removedByUserId,
  }) async {
    if (userId == removedByUserId) {
      throw Exception('Cannot remove yourself. Use Leave Team instead.');
    }
    await _requireAdmin(teamId, removedByUserId);

    await _removeUserFromTeamAndCrews(teamId: teamId, userId: userId);
  }

  /// Removes a user from all crews in a team, then removes team membership.
  Future<void> _removeUserFromTeamAndCrews({
    required String teamId,
    required String userId,
  }) async {
    final crews = await (_db.select(_db.localCrews)
          ..where((t) => t.teamId.equals(teamId)))
        .get();

    for (final crew in crews) {
      await (_db.delete(_db.localCrewMembers)
            ..where(
                (t) => t.crewId.equals(crew.id) & t.userId.equals(userId)))
          .go();

      await _db.enqueueSync(
        targetTable: 'crew_members',
        operation: 'delete',
        recordId: '${crew.id}_$userId',
        payloadJson: jsonEncode({
          'crew_id': crew.id,
          'user_id': userId,
        }),
      );
    }

    await (_db.delete(_db.localTeamMembers)
          ..where(
              (t) => t.teamId.equals(teamId) & t.userId.equals(userId)))
        .go();

    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'delete',
      recordId: '${teamId}_$userId',
      payloadJson: jsonEncode({
        'team_id': teamId,
        'user_id': userId,
      }),
    );
  }

  // ── Role Management ──

  /// Verify the caller is a team admin. Throws if not.
  ///
  /// Checks the remote membership first (memberships are managed across
  /// devices); falls back to the local cache when offline. RLS remains the
  /// real enforcement server-side.
  Future<void> _requireAdmin(String teamId, String callerUserId) async {
    String? role;
    try {
      final row = await _client
          .from('team_members')
          .select('role')
          .eq('team_id', teamId)
          .eq('user_id', callerUserId)
          .maybeSingle();
      role = row?['role'] as String?;
    } catch (_) {
      // Offline — fall through to the local cache.
    }
    role ??= await getUserRoleInTeam(teamId, callerUserId);
    if (role != TeamRole.admin) {
      throw Exception('Only team admins can perform this action');
    }
  }

  Future<void> promoteToAdmin({
    required String teamId,
    required String userId,
    required String callerUserId,
  }) async {
    await _requireAdmin(teamId, callerUserId);
    final adminCount = await getAdminCount(teamId);
    if (adminCount >= 3) {
      throw Exception('Maximum 3 admins per team');
    }

    await (_db.update(_db.localTeamMembers)
          ..where(
              (t) => t.teamId.equals(teamId) & t.userId.equals(userId)))
        .write(const LocalTeamMembersCompanion(role: Value('admin')));

    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'update',
      recordId: '${teamId}_$userId',
      payloadJson: jsonEncode({
        'team_id': teamId,
        'user_id': userId,
        'role': TeamRole.admin,
      }),
    );
  }

  Future<void> demoteToMember({
    required String teamId,
    required String userId,
    required String callerUserId,
  }) async {
    await _requireAdmin(teamId, callerUserId);
    final adminCount = await getAdminCount(teamId);
    if (adminCount <= 1) {
      throw Exception(
          'Cannot demote — this is the last admin. Promote another member first.');
    }

    await (_db.update(_db.localTeamMembers)
          ..where(
              (t) => t.teamId.equals(teamId) & t.userId.equals(userId)))
        .write(const LocalTeamMembersCompanion(role: Value(TeamRole.member)));

    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'update',
      recordId: '${teamId}_$userId',
      payloadJson: jsonEncode({
        'team_id': teamId,
        'user_id': userId,
        'role': TeamRole.member,
      }),
    );
  }

  // ── Invite Code ──

  Future<String> regenerateInviteCode(String teamId) async {
    final newCode = generateInviteCode();

    await (_db.update(_db.localTeams)..where((t) => t.id.equals(teamId)))
        .write(LocalTeamsCompanion(code: Value(newCode)));

    final team = await (_db.select(_db.localTeams)
          ..where((t) => t.id.equals(teamId)))
        .getSingleOrNull();
    if (team != null) {
      await _db.enqueueSync(
        targetTable: 'teams',
        operation: 'update',
        recordId: teamId,
        payloadJson: jsonEncode({
          'id': teamId,
          'name': team.name,
          'code': newCode,
          'created_by': team.createdBy,
          if (team.location != null) 'location': team.location,
          if (team.logoUrl != null) 'logo_url': team.logoUrl,
          'verified': team.verified,
        }),
      );
    }

    return newCode;
  }

  // ── Search (Supabase only) ──

  Future<List<TeamSearchResult>> searchTeams(
    String query, {
    String? currentUserId,
  }) async {
    // Strip characters that break the PostgREST `.or()` filter grammar.
    final sanitized = _sanitizeSearchQuery(query);
    if (sanitized.length < 2) return [];

    try {
      final response = await _client
          .from('teams')
          .select('*, team_members(count)')
          .or('name.ilike.%$sanitized%,location.ilike.%$sanitized%')
          .order('name')
          .limit(20);

      Set<String> memberTeamIds = {};
      Set<String> pendingTeamIds = {};

      if (currentUserId != null) {
        final memberships = await _client
            .from('team_members')
            .select('team_id')
            .eq('user_id', currentUserId);
        memberTeamIds =
            (memberships as List).map((m) => m['team_id'] as String).toSet();

        final requests = await _client
            .from('team_join_requests')
            .select('team_id')
            .eq('user_id', currentUserId)
            .eq('status', JoinRequestStatus.pending);
        pendingTeamIds =
            (requests as List).map((r) => r['team_id'] as String).toSet();
      }

      return (response as List).map((json) {
        final teamId = json['id'] as String;
        String? status;
        if (memberTeamIds.contains(teamId)) {
          status = MembershipStatus.member;
        } else if (pendingTeamIds.contains(teamId)) {
          status = MembershipStatus.pending;
        }

        final countData = json['team_members'] as List?;
        final memberCount = countData?.isNotEmpty == true
            ? (countData!.first['count'] as int? ?? 0)
            : 0;

        return TeamSearchResult(
          id: teamId,
          name: json['name'] as String,
          location: json['location'] as String?,
          logoUrl: json['logo_url'] as String?,
          verified: json['verified'] as bool? ?? false,
          memberCount: memberCount,
          membershipStatus: status,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // ── Join Requests ──

  Future<void> submitJoinRequest({
    required String teamId,
    required String userId,
    String? message,
  }) async {
    if (message != null && message.length > 500) {
      throw ArgumentError('Message must be at most 500 characters');
    }

    final existingMembership = await getUserRoleInTeam(teamId, userId);
    if (existingMembership != null) {
      throw Exception('Already a member of this team');
    }

    final existing = await (_db.select(_db.localTeamJoinRequests)
          ..where((t) =>
              t.teamId.equals(teamId) &
              t.userId.equals(userId) &
              t.status.equals(JoinRequestStatus.pending)))
        .getSingleOrNull();

    if (existing != null) {
      throw Exception('You already have a pending request for this team');
    }

    final id = _uuid.v4();

    await _db.into(_db.localTeamJoinRequests).insert(
      LocalTeamJoinRequestsCompanion.insert(
        id: id,
        teamId: teamId,
        userId: userId,
        message: Value(message),
      ),
    );

    await _db.enqueueSync(
      targetTable: 'team_join_requests',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'team_id': teamId,
        'user_id': userId,
        'status': JoinRequestStatus.pending,
        if (message != null) 'message': message,
      }),
    );
  }

  Future<void> cancelJoinRequest({
    required String requestId,
    required String userId,
  }) async {
    final request = await _getJoinRequest(requestId);
    if (request == null) throw Exception('Join request not found');
    if (request.userId != userId) {
      throw Exception('You can only cancel your own join requests');
    }

    await (_db.update(_db.localTeamJoinRequests)
          ..where((t) => t.id.equals(requestId) & t.userId.equals(userId)))
        .write(const LocalTeamJoinRequestsCompanion(
      status: Value(JoinRequestStatus.cancelled),
    ));

    await _db.enqueueSync(
      targetTable: 'team_join_requests',
      operation: 'update',
      recordId: requestId,
      payloadJson: jsonEncode(_joinRequestPayload(
        request,
        status: JoinRequestStatus.cancelled,
        reviewedBy: request.reviewedBy,
        reviewedAt: request.reviewedAt,
        rejectionReason: request.rejectionReason,
      )),
    );
  }

  Future<List<JoinRequestInfo>> getPendingRequests(String teamId) async {
    // Try remote first for enriched profile data
    try {
      final remoteRequests = await _client
          .from('team_join_requests')
          .select('*, profiles!inner(*)')
          .eq('team_id', teamId)
          .eq('status', JoinRequestStatus.pending)
          .order('requested_at');

      if (remoteRequests is List && remoteRequests.isNotEmpty) {
        return remoteRequests.map((json) {
          return JoinRequestInfo(
            id: json['id'] as String,
            teamId: json['team_id'] as String,
            userId: json['user_id'] as String,
            status: json['status'] as String,
            message: json['message'] as String?,
            requestedAt: DateTime.parse(json['requested_at'] as String),
            reviewedBy: json['reviewed_by'] as String?,
            reviewedAt: json['reviewed_at'] != null
                ? DateTime.parse(json['reviewed_at'] as String)
                : null,
            rejectionReason: json['rejection_reason'] as String?,
            displayName:
                json['profiles']?['display_name'] as String? ?? 'Driver',
            handle: json['profiles']?['handle'] as String?,
            avatarUrl: json['profiles']?['avatar_url'] as String?,
          );
        }).toList();
      }
    } catch (_) {
      // Fall back to local data
    }

    // Local fallback
    final requests = await (_db.select(_db.localTeamJoinRequests)
          ..where((t) =>
              t.teamId.equals(teamId) & t.status.equals(JoinRequestStatus.pending))
          ..orderBy([(t) => OrderingTerm.asc(t.requestedAt)]))
        .get();

    final result = <JoinRequestInfo>[];
    for (final r in requests) {
      final profile = await _db.getProfile(r.userId);
      result.add(JoinRequestInfo(
        id: r.id,
        teamId: r.teamId,
        userId: r.userId,
        status: r.status,
        message: r.message,
        requestedAt: r.requestedAt,
        displayName: profile?.displayName ?? 'Driver',
        handle: profile?.handle,
        avatarUrl: profile?.avatarUrl,
      ));
    }

    return result;
  }

  Future<void> approveJoinRequest({
    required String requestId,
    required String reviewerId,
  }) async {
    // The request is usually created on another device, so fetch it from
    // Supabase first (falling back to the local cache when offline).
    final request = await _getJoinRequest(requestId);

    if (request == null) throw Exception('Join request not found');
    await _requireAdmin(request.teamId, reviewerId);
    if (request.status != JoinRequestStatus.pending) {
      throw Exception('Request is no longer pending');
    }

    final now = DateTime.now();

    await (_db.update(_db.localTeamJoinRequests)
          ..where((t) => t.id.equals(requestId)))
        .write(LocalTeamJoinRequestsCompanion(
      status: const Value(JoinRequestStatus.approved),
      reviewedBy: Value(reviewerId),
      reviewedAt: Value(now),
    ));

    await _db.into(_db.localTeamMembers).insertOnConflictUpdate(
      LocalTeamMembersCompanion.insert(
        teamId: request.teamId,
        userId: request.userId,
      ),
    );

    await _db.enqueueSync(
      targetTable: 'team_join_requests',
      operation: 'update',
      recordId: requestId,
      payloadJson: jsonEncode(_joinRequestPayload(
        request,
        status: JoinRequestStatus.approved,
        reviewedBy: reviewerId,
        reviewedAt: now,
      )),
    );

    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'insert',
      recordId: '${request.teamId}_${request.userId}',
      payloadJson: jsonEncode({
        'team_id': request.teamId,
        'user_id': request.userId,
        'role': TeamRole.member,
      }),
    );
  }

  Future<void> rejectJoinRequest({
    required String requestId,
    required String reviewerId,
    String? reason,
  }) async {
    if (reason != null && reason.length > 500) {
      throw ArgumentError('Rejection reason must be at most 500 characters');
    }

    // The request is usually created on another device, so fetch it from
    // Supabase first (falling back to the local cache when offline).
    final request = await _getJoinRequest(requestId);
    if (request == null) throw Exception('Join request not found');
    await _requireAdmin(request.teamId, reviewerId);

    final now = DateTime.now();

    await (_db.update(_db.localTeamJoinRequests)
          ..where((t) => t.id.equals(requestId)))
        .write(LocalTeamJoinRequestsCompanion(
      status: const Value(JoinRequestStatus.rejected),
      reviewedBy: Value(reviewerId),
      reviewedAt: Value(now),
      rejectionReason: Value(reason),
    ));

    await _db.enqueueSync(
      targetTable: 'team_join_requests',
      operation: 'update',
      recordId: requestId,
      payloadJson: jsonEncode(_joinRequestPayload(
        request,
        status: JoinRequestStatus.rejected,
        reviewedBy: reviewerId,
        reviewedAt: now,
        rejectionReason: reason,
      )),
    );
  }

  // ── Private Helpers ──

  /// Fetch a join request from Supabase (the normal cross-device case) and
  /// upsert it into the local cache. Falls back to the local cache when the
  /// network call fails.
  Future<LocalTeamJoinRequest?> _getJoinRequest(String requestId) async {
    try {
      final json = await _client
          .from('team_join_requests')
          .select()
          .eq('id', requestId)
          .maybeSingle();

      if (json != null) {
        await _db.into(_db.localTeamJoinRequests).insertOnConflictUpdate(
          LocalTeamJoinRequestsCompanion(
            id: Value(json['id'] as String),
            teamId: Value(json['team_id'] as String),
            userId: Value(json['user_id'] as String),
            status:
                Value(json['status'] as String? ?? JoinRequestStatus.pending),
            message: Value(json['message'] as String?),
            requestedAt: Value(_parseTimestamp(json['requested_at'])),
            reviewedBy: Value(json['reviewed_by'] as String?),
            reviewedAt: Value(json['reviewed_at'] != null
                ? DateTime.parse(json['reviewed_at'] as String)
                : null),
            rejectionReason: Value(json['rejection_reason'] as String?),
          ),
        );
      }
    } catch (_) {
      // Offline — fall through to the local cache.
    }

    return (_db.select(_db.localTeamJoinRequests)
          ..where((t) => t.id.equals(requestId)))
        .getSingleOrNull();
  }

  /// Full-row payload for team_join_requests upserts. The sync queue
  /// executes updates as upserts, so every remote column must be present.
  Map<String, dynamic> _joinRequestPayload(
    LocalTeamJoinRequest request, {
    required String status,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? rejectionReason,
  }) {
    return {
      'id': request.id,
      'team_id': request.teamId,
      'user_id': request.userId,
      'status': status,
      'message': request.message,
      'requested_at': request.requestedAt.toUtc().toIso8601String(),
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
      'rejection_reason': rejectionReason,
    };
  }

  /// Upsert a remote team row into the local cache.
  Future<void> _cacheRemoteTeam(Map<String, dynamic> json) {
    return _db.into(_db.localTeams).insertOnConflictUpdate(
      LocalTeamsCompanion(
        id: Value(json['id'] as String),
        name: Value(json['name'] as String),
        code: Value(json['code'] as String),
        createdBy: Value(json['created_by'] as String? ?? ''),
        location: Value(json['location'] as String?),
        logoUrl: Value(json['logo_url'] as String?),
        verified: Value(json['verified'] as bool? ?? false),
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

  /// Member count, remote-first with local fallback.
  Future<int> _countTeamMembers(String teamId) async {
    try {
      final rows = await _client
          .from('team_members')
          .select('user_id')
          .eq('team_id', teamId);
      return (rows as List).length;
    } catch (_) {
      return _countTeamMembersLocal(teamId);
    }
  }

  Future<int> _countTeamMembersLocal(String teamId) async {
    final members = await (_db.select(_db.localTeamMembers)
          ..where((t) => t.teamId.equals(teamId)))
        .get();
    return members.length;
  }

  /// Pending join-request count, remote-first with local fallback.
  Future<int> _countPendingRequests(String teamId) async {
    try {
      final rows = await _client
          .from('team_join_requests')
          .select('id')
          .eq('team_id', teamId)
          .eq('status', JoinRequestStatus.pending);
      return (rows as List).length;
    } catch (_) {
      return _countPendingRequestsLocal(teamId);
    }
  }

  Future<int> _countPendingRequestsLocal(String teamId) async {
    final requests = await (_db.select(_db.localTeamJoinRequests)
          ..where((t) =>
              t.teamId.equals(teamId) & t.status.equals(JoinRequestStatus.pending)))
        .get();
    return requests.length;
  }

  DateTime _parseTimestamp(dynamic value) =>
      value is String ? DateTime.parse(value) : DateTime.now();

  /// Parse a PostgREST count embed (`table(count)` → `[{'count': n}]`).
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
}

/// Strip characters that break the PostgREST `.or()` filter grammar
/// (`,` separates filters, `(`/`)` group, `.` separates operator parts,
/// `%` is the ilike wildcard).
String _sanitizeSearchQuery(String query) {
  return query.replaceAll(RegExp(r'[,().%\\]'), ' ').trim();
}

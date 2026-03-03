import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';

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
    final id = _uuid.v4();
    final inviteCode = _generateInviteCode();

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

  Future<List<CrewInfo>> getCrewsForTeam(
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

  Future<List<CrewMemberInfo>> getCrewMembers(String crewId) async {
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

    // Sort: captains first, then by joinedAt
    result.sort((a, b) {
      if (a.role == 'captain' && b.role != 'captain') return -1;
      if (a.role != 'captain' && b.role == 'captain') return 1;
      return a.joinedAt.compareTo(b.joinedAt);
    });

    return result;
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

    await _db.into(_db.localCrewMembers).insert(
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
        'role': 'member',
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
    required AppDatabase db,
    required SupabaseClient client,
  }) async {
    // Look up crew by code (try local first, then remote)
    var crew = await (_db.select(_db.localCrews)
          ..where((t) => t.inviteCode.equals(code.toUpperCase())))
        .getSingleOrNull();

    if (crew == null) {
      try {
        final response = await _client
            .from('crews')
            .select()
            .eq('invite_code', code.toUpperCase())
            .single();

        await _db.into(_db.localCrews).insert(
          LocalCrewsCompanion.insert(
            id: response['id'] as String,
            teamId: response['team_id'] as String,
            name: response['name'] as String,
            inviteCode: response['invite_code'] as String,
          ),
        );

        crew = await (_db.select(_db.localCrews)
              ..where((t) => t.inviteCode.equals(code.toUpperCase())))
            .getSingleOrNull();
      } catch (_) {
        throw Exception('Crew not found with code: $code');
      }
    }

    if (crew == null) throw Exception('Crew not found');

    // Auto-join parent team if not already a member
    final teamMembership = await (_db.select(_db.localTeamMembers)
          ..where((t) =>
              t.teamId.equals(crew!.teamId) & t.userId.equals(userId)))
        .getSingleOrNull();

    if (teamMembership == null) {
      await _db.into(_db.localTeamMembers).insert(
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
          'role': 'member',
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

  String _generateInviteCode() {
    final random = Random.secure();
    return List.generate(
        8, (_) => random.nextInt(16).toRadixString(16)).join().toUpperCase();
  }
}

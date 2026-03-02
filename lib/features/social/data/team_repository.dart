import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/app_database.dart';

/// Repository for team operations.
class TeamRepository {
  TeamRepository(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;
  static const _uuid = Uuid();

  /// Get teams the user belongs to.
  Future<List<TeamInfo>> getUserTeams(String userId) async {
    // Get team IDs the user is a member of
    final memberships = await (_db.select(_db.localTeamMembers)
          ..where((t) => t.userId.equals(userId)))
        .get();

    final teamIds = memberships.map((m) => m.teamId).toList();
    if (teamIds.isEmpty) return [];

    final teams = <TeamInfo>[];
    for (final teamId in teamIds) {
      final team = await (_db.select(_db.localTeams)
            ..where((t) => t.id.equals(teamId)))
          .getSingleOrNull();
      if (team == null) continue;

      // Count members
      final members = await (_db.select(_db.localTeamMembers)
            ..where((t) => t.teamId.equals(teamId)))
          .get();

      teams.add(TeamInfo(
        id: team.id,
        name: team.name,
        code: team.code,
        createdBy: team.createdBy,
        memberCount: members.length,
      ));
    }

    return teams;
  }

  /// Create a new team with an auto-generated code.
  Future<TeamInfo> createTeam({
    required String name,
    required String createdBy,
  }) async {
    final id = _uuid.v4();
    final code = _generateTeamCode();

    await _db.into(_db.localTeams).insert(
      LocalTeamsCompanion.insert(
        id: id,
        name: name,
        code: code,
        createdBy: createdBy,
      ),
    );

    // Add creator as member with 'owner' role
    await _db.into(_db.localTeamMembers).insert(
      LocalTeamMembersCompanion.insert(
        teamId: id,
        userId: createdBy,
        role: const Value('owner'),
      ),
    );

    // Enqueue sync for team
    await _db.enqueueSync(
      targetTable: 'teams',
      operation: 'insert',
      recordId: id,
      payloadJson: jsonEncode({
        'id': id,
        'name': name,
        'code': code,
        'created_by': createdBy,
      }),
    );

    // Enqueue sync for membership
    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'insert',
      recordId: '${id}_$createdBy',
      payloadJson: jsonEncode({
        'team_id': id,
        'user_id': createdBy,
        'role': 'owner',
      }),
    );

    return TeamInfo(
      id: id,
      name: name,
      code: code,
      createdBy: createdBy,
      memberCount: 1,
    );
  }

  /// Join a team by its code.
  Future<void> joinTeam({
    required String code,
    required String userId,
  }) async {
    // Look up team by code (try local first, then remote)
    var team = await (_db.select(_db.localTeams)
          ..where((t) => t.code.equals(code)))
        .getSingleOrNull();

    if (team == null) {
      // Try Supabase
      try {
        final response = await _client
            .from('teams')
            .select()
            .eq('code', code)
            .single();

        // Insert team locally
        await _db.into(_db.localTeams).insert(
          LocalTeamsCompanion.insert(
            id: response['id'] as String,
            name: response['name'] as String,
            code: response['code'] as String,
            createdBy: response['created_by'] as String,
          ),
        );

        team = await (_db.select(_db.localTeams)
              ..where((t) => t.code.equals(code)))
            .getSingleOrNull();
      } catch (_) {
        throw Exception('Team not found with code: $code');
      }
    }

    if (team == null) throw Exception('Team not found');

    // Check if already a member
    final existing = await (_db.select(_db.localTeamMembers)
          ..where((t) =>
              t.teamId.equals(team!.id) & t.userId.equals(userId)))
        .getSingleOrNull();

    if (existing != null) throw Exception('Already a member of this team');

    // Add membership
    await _db.into(_db.localTeamMembers).insert(
      LocalTeamMembersCompanion.insert(
        teamId: team.id,
        userId: userId,
      ),
    );

    // Enqueue sync
    await _db.enqueueSync(
      targetTable: 'team_members',
      operation: 'insert',
      recordId: '${team.id}_$userId',
      payloadJson: jsonEncode({
        'team_id': team.id,
        'user_id': userId,
        'role': 'member',
      }),
    );
  }

  /// Leave a team.
  Future<void> leaveTeam({
    required String teamId,
    required String userId,
  }) async {
    await (_db.delete(_db.localTeamMembers)
          ..where((t) =>
              t.teamId.equals(teamId) & t.userId.equals(userId)))
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

  /// Generate a random 6-character team code.
  String _generateTeamCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

/// Team info with member count.
class TeamInfo {
  TeamInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.createdBy,
    required this.memberCount,
  });

  final String id;
  final String name;
  final String code;
  final String createdBy;
  final int memberCount;
}

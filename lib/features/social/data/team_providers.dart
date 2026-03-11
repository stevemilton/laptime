import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import 'team_repository.dart';
import 'crew_repository.dart';

// ── Repository Providers ──

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final client = ref.read(supabaseClientProvider);
  return TeamRepository(db, client);
});

final crewRepositoryProvider = Provider<CrewRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final client = ref.read(supabaseClientProvider);
  return CrewRepository(db, client);
});

// ── User's Teams ──

final userTeamsProvider = FutureProvider<List<TeamInfo>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.watch(teamRepositoryProvider);
  return repo.getUserTeams(user.id);
});

// ── Team Detail ──

final teamDetailProvider =
    FutureProvider.family<TeamInfo?, String>((ref, teamId) async {
  final user = ref.watch(currentUserProvider);
  final repo = ref.watch(teamRepositoryProvider);
  return repo.getTeam(teamId, currentUserId: user?.id);
});

// ── Team Members ──

final teamMembersProvider =
    FutureProvider.family<List<TeamMemberInfo>, String>((ref, teamId) async {
  final repo = ref.watch(teamRepositoryProvider);
  return repo.getTeamMembers(teamId);
});

// ── Pending Join Requests ──

final pendingRequestsProvider =
    FutureProvider.family<List<JoinRequestInfo>, String>((ref, teamId) async {
  final repo = ref.watch(teamRepositoryProvider);
  return repo.getPendingRequests(teamId);
});

// ── Current User's Role in Team ──

final userRoleProvider =
    FutureProvider.family<String?, String>((ref, teamId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final repo = ref.watch(teamRepositoryProvider);
  return repo.getUserRoleInTeam(teamId, user.id);
});

// ── Team Search ──

final teamSearchProvider =
    FutureProvider.family<List<TeamSearchResult>, String>((ref, query) async {
  if (query.length < 2) return [];
  final user = ref.watch(currentUserProvider);
  final repo = ref.watch(teamRepositoryProvider);
  return repo.searchTeams(query, currentUserId: user?.id);
});

// ── Crews for Team ──

final teamCrewsProvider =
    FutureProvider.family<List<CrewInfo>, String>((ref, teamId) async {
  final user = ref.watch(currentUserProvider);
  final repo = ref.watch(crewRepositoryProvider);
  return repo.getCrewsForTeam(teamId, currentUserId: user?.id);
});

// ── Crew Detail ──

final crewDetailProvider =
    FutureProvider.family<CrewInfo?, String>((ref, crewId) async {
  final user = ref.watch(currentUserProvider);
  final repo = ref.watch(crewRepositoryProvider);
  return repo.getCrew(crewId, currentUserId: user?.id);
});

// ── Crew Members ──

final crewMembersProvider =
    FutureProvider.family<List<CrewMemberInfo>, String>((ref, crewId) async {
  final repo = ref.watch(crewRepositoryProvider);
  return repo.getCrewMembers(crewId);
});


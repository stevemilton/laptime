/// Roles for team members.
abstract final class TeamRole {
  static const admin = 'admin';
  static const member = 'member';
}

/// Roles for crew members.
abstract final class CrewRole {
  static const captain = 'captain';
  static const member = 'member';
}

/// Statuses for team join requests.
abstract final class JoinRequestStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const cancelled = 'cancelled';
}

/// Membership status returned from team search.
abstract final class MembershipStatus {
  static const member = 'member';
  static const pending = 'pending';
}

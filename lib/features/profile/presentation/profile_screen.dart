import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_pill.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/stat_cell.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/empty_state.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import '../../../core/database/app_database.dart';
import '../../../core/utils/format_utils.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../social/data/team_providers.dart';
import '../data/profile_repository.dart';

/// Profile provider - watches the current user's profile.
final profileProvider = StreamProvider<LocalProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(db.localProfiles)
        ..where((t) => t.id.equals(user.id)))
      .watchSingleOrNull();
});

/// Cars provider - watches the user's garage.
final userCarsProvider = StreamProvider<List<LocalCar>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value([]);
  final db = ref.watch(databaseProvider);
  return db.watchUserCars(user.id);
});

/// Stats provider
final profileStatsProvider = FutureProvider<ProfileStats>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return ProfileStats(
      sessionCount: 0,
      circuitCount: 0,
      lapCount: 0,
      p1Count: 0,
    );
  }
  final db = ref.read(databaseProvider);
  final client = ref.read(supabaseClientProvider);
  final repo = ProfileRepository(db, client);
  return repo.getStats(user.id);
});

/// Recent sessions provider - watches last 5 sessions for the user.
final recentSessionsProvider = StreamProvider<List<LocalSession>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value([]);
  final db = ref.watch(databaseProvider);
  return (db.select(db.localSessions)
        ..where((t) => t.userId.equals(user.id))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
        ..limit(5))
      .watch();
});

/// Best lap for a session (profile card).
final _profileSessionBestLapProvider =
    FutureProvider.family<int?, String>((ref, sessionId) async {
  final db = ref.read(databaseProvider);
  final laps = await db.getSessionLaps(sessionId);
  if (laps.isEmpty) return null;
  return laps.map((l) => l.durationMs).reduce((a, b) => a < b ? a : b);
});

/// Profile tab screen with avatar, stats, garage, and recent sessions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final carsAsync = ref.watch(userCarsProvider);
    final statsAsync = ref.watch(profileStatsProvider);
    final sessionsAsync = ref.watch(recentSessionsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Profile header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildProfileAvatar(profileAsync.value),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profileAsync.value?.displayName ?? 'Driver',
                        style: AppTypography.headlineMedium,
                      ),
                      if (profileAsync.value?.handle != null)
                        Text(
                          '@${profileAsync.value!.handle}',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                AppPill.outlined(
                  label: 'Edit Profile',
                  icon: LucideIcons.pencil,
                  onTap: () => context.push('/edit-profile'),
                ),
                const SizedBox(width: 8),
                AppPill.outlined(
                  label: 'Settings',
                  icon: LucideIcons.settings,
                  onTap: () => context.push('/settings'),
                ),
                const Spacer(),
                AppPill.outlined(
                  label: 'Sign Out',
                  icon: LucideIcons.logOut,
                  foregroundColor: AppColors.red,
                  borderColor: AppColors.red.withValues(alpha: 0.3),
                  onTap: () {
                    ref.read(authControllerProvider.notifier).signOut();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Stats grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  StatCell(
                    value: statsAsync.value?.sessionCount.toString() ?? '0',
                    label: 'Sessions',
                  ),
                  StatCell(
                    value: statsAsync.value?.circuitCount.toString() ?? '0',
                    label: 'Circuits',
                  ),
                  StatCell(
                    value: statsAsync.value?.lapCount.toString() ?? '0',
                    label: 'Laps',
                  ),
                  StatCell(
                    value: statsAsync.value?.p1Count.toString() ?? '0',
                    label: 'P1s',
                    valueColor: AppColors.gold,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Garage section
          SectionHeader(
            title: 'Garage',
            trailing: SectionAction(
              label: 'Add',
              onTap: () => context.push('/car/new'),
            ),
          ),

          carsAsync.when(
            data: (cars) {
              if (cars.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.purplePale,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: const Icon(
                            LucideIcons.car,
                            color: AppColors.purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Add your first car to get started',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const Icon(
                          LucideIcons.plus,
                          color: AppColors.purple,
                          size: 20,
                        ),
                      ],
                    ),
                    onTap: () => context.push('/car/new'),
                  ),
                );
              }

              return SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: cars.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final car = cars[index];
                    return _CarCard(
                      car: car,
                      onTap: () => context.push('/car/${car.id}'),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error loading cars: $e'),
            ),
          ),

          const SizedBox(height: 24),

          // Teams section
          SectionHeader(
            title: 'Teams',
            trailing: SectionAction(
              label: 'All',
              onTap: () => context.push('/teams'),
            ),
          ),

          _buildTeamsSection(context, ref),

          const SizedBox(height: 24),

          // Recent sessions section
          SectionHeader(
            title: 'Recent Sessions',
            trailing: SectionAction(
              label: 'View All',
              onTap: () => context.push('/sessions'),
            ),
          ),
          sessionsAsync.when(
            data: (sessions) {
              if (sessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: EmptyState(
                    icon: LucideIcons.timer,
                    title: 'No sessions yet',
                    subtitle:
                        'Record your first track session to see it here.',
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    for (int i = 0; i < sessions.length; i++) ...[
                      _SessionCard(session: sessions[i]),
                      if (i < sessions.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: EmptyState(
                icon: LucideIcons.alertCircle,
                title: 'Error loading sessions',
                subtitle: 'Pull to refresh.',
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTeamsSection(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(userTeamsProvider);

    return teamsAsync.when(
      data: (teams) {
        if (teams.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.purplePale,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Icon(
                      LucideIcons.users,
                      color: AppColors.purple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Create or join a team',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const Icon(
                    LucideIcons.plus,
                    color: AppColors.purple,
                    size: 20,
                  ),
                ],
              ),
              onTap: () => context.push('/team/create'),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              for (int i = 0; i < teams.length; i++) ...[
                AppCard(
                  onTap: () => context.push('/team/${teams[i].id}'),
                  child: Row(
                    children: [
                      AppAvatar(
                        imageUrl: teams[i].logoUrl,
                        initials: teams[i].name.isNotEmpty
                            ? teams[i].name[0].toUpperCase()
                            : null,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              teams[i].name,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${teams[i].memberCount} member${teams[i].memberCount == 1 ? '' : 's'}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
                if (i < teams.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildProfileAvatar(LocalProfile? profile) {
    final avatarUrl = profile?.avatarUrl;
    final initials = _getInitials(profile?.displayName);

    // If the avatar is a local file path that exists, use FileImage
    if (avatarUrl != null &&
        avatarUrl.isNotEmpty &&
        !avatarUrl.startsWith('http') &&
        File(avatarUrl).existsSync()) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.purpleLight,
          image: DecorationImage(
            image: FileImage(File(avatarUrl)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return AppAvatar.xl(
      imageUrl: avatarUrl?.startsWith('http') == true ? avatarUrl : null,
      initials: initials,
    );
  }

  String? _getInitials(String? name) {
    if (name == null || name.isEmpty) return null;
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}

/// A compact session card for the recent sessions list.
class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.session});

  final LocalSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bestLapAsync =
        ref.watch(_profileSessionBestLapProvider(session.id));
    final bestLapMs = bestLapAsync.value;

    return GestureDetector(
      onTap: () => context.push('/session/${session.id}'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Best lap time
            if (bestLapMs != null) ...[
              Text(
                FormatUtils.formatLapTime(bestLapMs),
                style: AppTypography.headlineSmall.copyWith(
                  color: AppColors.green,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 12),
            ],
            // Date
            Expanded(
              child: Text(
                _formatDate(session.startedAt),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // Track condition pill
            if (session.trackCondition != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.purplePale,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  session.trackCondition!,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.purple,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(LucideIcons.chevronRight,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car, this.onTap});

  final LocalCar car;
  final VoidCallback? onTap;

  bool _imageFileExists(String? url) {
    if (url == null || url.isEmpty) return false;
    if (url.startsWith('http')) return true;
    return File(url).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageFileExists(car.imageUrl);
    final isKart = car.carClass == 'Kart';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo or icon placeholder
            if (hasImage)
              SizedBox(
                height: 56,
                width: double.infinity,
                child: Image(
                  image: car.imageUrl!.startsWith('http')
                      ? NetworkImage(car.imageUrl!) as ImageProvider
                      : FileImage(File(car.imageUrl!)),
                  fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => _buildIconPlaceholder(isKart),
                ),
              )
            else
              _buildIconPlaceholder(isKart),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${car.make} ${car.model}',
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (car.carClass != null)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.purplePale,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                car.carClass!,
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.purple,
                                  fontSize: 10,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        if (car.powerHp != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${car.powerHp}hp',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconPlaceholder(bool isKart) {
    return Container(
      height: 56,
      width: double.infinity,
      color: AppColors.purplePale,
      child: Icon(
        isKart ? LucideIcons.gauge : LucideIcons.car,
        size: 24,
        color: AppColors.purple.withValues(alpha: 0.5),
      ),
    );
  }
}

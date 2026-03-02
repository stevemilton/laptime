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
import '../../../core/database/app_database.dart';
import '../../auth/presentation/auth_controller.dart';
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

/// Profile tab screen with avatar, stats, garage, and recent sessions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final carsAsync = ref.watch(userCarsProvider);
    final statsAsync = ref.watch(profileStatsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Profile header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                AppAvatar.xl(
                  imageUrl: profileAsync.value?.avatarUrl,
                  initials: _getInitials(profileAsync.value?.displayName),
                ),
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
                height: 100,
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

          // Recent sessions section
          SectionHeader(
            title: 'Recent Sessions',
            trailing: SectionAction(
              label: 'View All',
              onTap: () {
                // TODO: Navigate to all sessions
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: EmptyState(
              icon: LucideIcons.timer,
              title: 'No sessions yet',
              subtitle: 'Record your first track session to see it here.',
            ),
          ),
        ],
      ),
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

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car, this.onTap});

  final LocalCar car;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.car, size: 16, color: AppColors.purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    car.make,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              car.model,
              style: AppTypography.headlineSmall.copyWith(fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Row(
              children: [
                if (car.year != null)
                  Text(
                    car.year.toString(),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (car.carClass != null) ...[
                  if (car.year != null)
                    Text(
                      ' / ',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  Text(
                    car.carClass!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

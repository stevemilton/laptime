import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../profile/presentation/profile_screen.dart';

/// Full-screen garage listing all the user's cars.
class GarageScreen extends ConsumerWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carsAsync = ref.watch(userCarsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Garage'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => context.push('/car/new'),
          ),
        ],
      ),
      body: carsAsync.when(
        data: (cars) {
          if (cars.isEmpty) {
            return EmptyState(
              icon: LucideIcons.car,
              title: 'No cars yet',
              subtitle: 'Add your first car to get started.',
              actionLabel: 'Add Vehicle',
              onAction: () => context.push('/car/new'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: cars.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _GarageCarTile(
                car: cars[index],
                onTap: () => context.push('/car/${cars[index].id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error loading cars: $e'),
          ),
        ),
      ),
    );
  }
}

/// A card-style tile for each car in the garage list.
class _GarageCarTile extends StatelessWidget {
  const _GarageCarTile({required this.car, this.onTap});

  final LocalCar car;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageFileExists(car.imageUrl);
    final isKart = car.carClass == 'Kart';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Photo or placeholder
            SizedBox(
              width: 100,
              height: 80,
              child: hasImage
                  ? Image(
                      image: car.imageUrl!.startsWith('http')
                          ? NetworkImage(car.imageUrl!) as ImageProvider
                          : FileImage(File(car.imageUrl!)),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildPlaceholder(isKart),
                    )
                  : _buildPlaceholder(isKart),
            ),
            // Info
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${car.make} ${car.model}',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (car.carClass != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.purplePale,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              car.carClass!,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.purple,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                        if (car.year != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${car.year}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                        if (car.powerHp != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${car.powerHp}hp',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Chevron
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _imageFileExists(String? url) {
    if (url == null || url.isEmpty) return false;
    if (url.startsWith('http')) return true;
    return File(url).existsSync();
  }

  Widget _buildPlaceholder(bool isKart) {
    return Container(
      color: AppColors.purplePale,
      child: Center(
        child: Icon(
          isKart ? LucideIcons.gauge : LucideIcons.car,
          size: 24,
          color: AppColors.purple.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

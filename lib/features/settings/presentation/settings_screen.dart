import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/services/sync_service.dart';

/// Settings screen with account, sync status, and legal links.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // Sync status section
          _SectionTitle(title: 'SYNC'),
          _SettingsTile(
            icon: _syncIcon(syncStatus),
            iconColor: _syncColor(syncStatus),
            title: _syncTitle(syncStatus),
            subtitle: pendingCount > 0
                ? '$pendingCount item${pendingCount == 1 ? '' : 's'} pending'
                : 'All data synced',
            onTap: () {
              ref.read(syncServiceProvider).requestSync();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sync triggered'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),

          const Divider(indent: 56),

          // Account section
          _SectionTitle(title: 'ACCOUNT'),
          _SettingsTile(
            icon: LucideIcons.user,
            title: 'Edit Profile',
            onTap: () => context.push('/edit-profile'),
          ),
          _SettingsTile(
            icon: LucideIcons.car,
            title: 'Garage',
            subtitle: 'Manage your cars',
            onTap: () => context.push('/car/new'),
          ),

          const Divider(indent: 56),

          // Units & preferences
          _SectionTitle(title: 'PREFERENCES'),
          _SettingsTile(
            icon: LucideIcons.ruler,
            title: 'Units',
            subtitle: 'Metric',
            onTap: () {
              // TODO: Unit selector
            },
          ),
          _SettingsTile(
            icon: LucideIcons.globe,
            title: 'Default Session Privacy',
            subtitle: 'Public',
            onTap: () {
              // TODO: Default privacy setting
            },
          ),

          const Divider(indent: 56),

          // Legal section
          _SectionTitle(title: 'LEGAL'),
          _SettingsTile(
            icon: LucideIcons.shield,
            title: 'Privacy Policy',
            onTap: () => context.push('/privacy-policy'),
          ),
          _SettingsTile(
            icon: LucideIcons.fileText,
            title: 'Terms of Service',
            onTap: () => context.push('/terms'),
          ),
          _SettingsTile(
            icon: LucideIcons.alertTriangle,
            title: 'Disclaimer',
            onTap: () => context.push('/legal-disclaimer'),
          ),

          const Divider(indent: 56),

          // About section
          _SectionTitle(title: 'ABOUT'),
          _SettingsTile(
            icon: LucideIcons.info,
            title: 'Version',
            subtitle: '1.0.0',
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  IconData _syncIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return LucideIcons.checkCircle;
      case SyncStatus.syncing:
        return LucideIcons.refreshCw;
      case SyncStatus.error:
        return LucideIcons.alertCircle;
    }
  }

  Color _syncColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return AppColors.green;
      case SyncStatus.syncing:
        return AppColors.purple;
      case SyncStatus.error:
        return AppColors.red;
    }
  }

  String _syncTitle(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return 'Synced';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.error:
        return 'Sync Error';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: AppTypography.sectionLabel,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.purple).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Icon(
          icon,
          size: 18,
          color: iconColor ?? AppColors.purple,
        ),
      ),
      title: Text(title, style: AppTypography.bodyMedium),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            )
          : null,
      trailing: onTap != null
          ? const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textTertiary)
          : null,
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/section_header.dart';

/// Provider for app version string.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Settings screen with account, sync status, preferences, and legal links.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider);
    final deadLetterCount = ref.watch(deadLetterCountProvider);
    final userId = ref.watch(currentUserIdProvider);
    final units = ref.watch(unitsProvider);
    final privacy = ref.watch(defaultPrivacyProvider);
    final versionAsync = ref.watch(appVersionProvider);

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
          const SectionHeader(title: 'SYNC', padding: EdgeInsets.fromLTRB(20, 20, 20, 8)),
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
          _SettingsTile(
            icon: LucideIcons.alertCircle,
            iconColor:
                deadLetterCount > 0 ? AppColors.red : AppColors.textTertiary,
            title: 'Retry Failed Sync',
            subtitle: deadLetterCount > 0
                ? '$deadLetterCount item${deadLetterCount == 1 ? '' : 's'} failed to sync'
                : 'No failed items',
            onTap: deadLetterCount > 0
                ? () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref.read(syncServiceProvider).retryDeadLetters();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Retrying failed items'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                : null,
          ),
          if (userId != null)
            _SettingsTile(
              icon: LucideIcons.upload,
              title: 'Re-upload All Data',
              subtitle: 'Push everything on this device to the cloud',
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref
                    .read(reconciliationServiceProvider)
                    .resyncAll(userId);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Re-upload started'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),

          const Divider(indent: 56),

          // Account section
          const SectionHeader(title: 'ACCOUNT', padding: EdgeInsets.fromLTRB(20, 20, 20, 8)),
          _SettingsTile(
            icon: LucideIcons.user,
            title: 'Edit Profile',
            onTap: () => context.push('/edit-profile'),
          ),
          _SettingsTile(
            icon: LucideIcons.car,
            title: 'Garage',
            subtitle: 'Manage your cars',
            onTap: () => context.push('/garage'),
          ),
          _SettingsTile(
            icon: LucideIcons.trash2,
            iconColor: AppColors.red,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account and all data',
            onTap: () => _confirmDeleteAccount(context, ref),
          ),

          const Divider(indent: 56),

          // Units & preferences
          const SectionHeader(title: 'PREFERENCES', padding: EdgeInsets.fromLTRB(20, 20, 20, 8)),
          _SettingsTile(
            icon: LucideIcons.ruler,
            title: 'Units',
            subtitle: units.label,
            onTap: () => _showUnitPicker(context, ref, units),
          ),
          _SettingsTile(
            icon: LucideIcons.globe,
            title: 'Default Session Privacy',
            subtitle: privacy,
            onTap: () => _showPrivacyPicker(context, ref, privacy),
          ),

          const Divider(indent: 56),

          // Legal section
          const SectionHeader(title: 'LEGAL', padding: EdgeInsets.fromLTRB(20, 20, 20, 8)),
          _SettingsTile(
            icon: LucideIcons.shield,
            title: 'Privacy Policy',
            onTap: () => context.push('/privacy-policy'),
          ),
          _SettingsTile(
            icon: LucideIcons.fileText,
            title: 'Terms and Conditions',
            onTap: () => context.push('/terms'),
          ),
          _SettingsTile(
            icon: LucideIcons.alertTriangle,
            title: 'Disclaimer',
            onTap: () => context.push('/legal-disclaimer'),
          ),

          const Divider(indent: 56),

          // Contact & Social section
          _SectionTitle(title: 'CONNECT'),
          _SettingsTile(
            icon: LucideIcons.mail,
            title: 'Contact Us',
            onTap: () => launchUrl(
              Uri.parse('mailto:support@polarindustries.co'),
            ),
          ),
          _SettingsTile(
            icon: LucideIcons.x,
            title: 'X',
            subtitle: 'Coming soon',
          ),
          _SettingsTile(
            icon: LucideIcons.instagram,
            title: 'Instagram',
            subtitle: 'Coming soon',
          ),
          _SettingsTile(
            icon: LucideIcons.music,
            title: 'TikTok',
            subtitle: 'Coming soon',
          ),

          const Divider(indent: 56),

          // About section
          const SectionHeader(title: 'ABOUT', padding: EdgeInsets.fromLTRB(20, 20, 20, 8)),
          _SettingsTile(
            icon: LucideIcons.info,
            title: 'Version',
            subtitle: versionAsync.when(
              data: (v) => v,
              loading: () => '...',
              error: (_, _) => '0.1.0',
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Account deletion (App Store Guideline 5.1.1(v)).
  ///
  /// Requires the user to type DELETE, then deletes the server-side
  /// account via the `delete_account` Postgres function (auth user +
  /// cascading data), wipes all local data, and signs out.
  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes your account and all of your data '
                '- sessions, laps, telemetry, cars, sectors, and social '
                'activity - from LapTime. This cannot be undone.',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Type DELETE to confirm.',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'DELETE'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: confirmController.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      ),
    );
    confirmController.dispose();

    if (confirmed != true || !context.mounted) return;
    await _deleteAccount(context, ref);
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final supabase = ref.read(supabaseClientProvider);
    final db = ref.read(databaseProvider);

    // Block interaction while deleting.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // 1. Delete the auth user server-side; all data cascades.
    try {
      await supabase.rpc('delete_account');
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not delete account. Check your connection and try again.'),
            backgroundColor: AppColors.red,
          ),
        );
      }
      return;
    }

    // 2. Wipe everything local.
    await db.wipeAllData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // 3. Sign out - the auth user may already be invalid, so failures
    // here are expected; fall back to clearing the local session.
    try {
      await supabase.auth.signOut();
    } catch (_) {
      try {
        await supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Local session cleanup failed; the router will still redirect
        // once the session expires.
      }
    }
  }

  void _showUnitPicker(BuildContext context, WidgetRef ref, UnitSystem current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Units', style: AppTypography.headlineSmall),
                ),
                const SizedBox(height: 8),
                for (final option in UnitSystem.values)
                  ListTile(
                    leading: Icon(
                      option == current
                          ? LucideIcons.checkCircle2
                          : LucideIcons.circle,
                      color: option == current
                          ? AppColors.purple
                          : AppColors.textTertiary,
                      size: 20,
                    ),
                    title: Text(option.label, style: AppTypography.bodyMedium),
                    subtitle: Text(
                      option == UnitSystem.metric
                          ? 'km/h, km, \u00B0C, hPa'
                          : 'mph, mi, \u00B0F, inHg',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                    onTap: () {
                      ref.read(unitsProvider.notifier).set(option);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPrivacyPicker(
      BuildContext context, WidgetRef ref, String current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Default Session Privacy',
                      style: AppTypography.headlineSmall),
                ),
                const SizedBox(height: 8),
                for (final option in ['Public', 'Private'])
                  ListTile(
                    leading: Icon(
                      option == current
                          ? LucideIcons.checkCircle2
                          : LucideIcons.circle,
                      color: option == current
                          ? AppColors.purple
                          : AppColors.textTertiary,
                      size: 20,
                    ),
                    title: Text(option, style: AppTypography.bodyMedium),
                    subtitle: Text(
                      option == 'Public'
                          ? 'Sessions visible to followers and on leaderboards'
                          : 'Sessions only visible to you',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textTertiary),
                    ),
                    onTap: () {
                      ref.read(defaultPrivacyProvider.notifier).set(option);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        );
      },
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
          ? const Icon(LucideIcons.chevronRight,
              size: 18, color: AppColors.textTertiary)
          : null,
      onTap: onTap,
    );
  }
}

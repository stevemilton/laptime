import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/services/sync_service.dart';

// ── Preference keys ──

const _kUnitsKey = 'pref_units';
const _kDefaultPrivacyKey = 'pref_default_privacy';

// ── Preference providers ──

/// Provider for the shared preferences instance.
final _sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// Provider for the user's preferred unit system.
final unitsProvider = StateNotifierProvider<_UnitsNotifier, String>((ref) {
  final prefsAsync = ref.watch(_sharedPrefsProvider);
  final prefs = prefsAsync.value;
  final initial = prefs?.getString(_kUnitsKey) ?? 'Metric';
  return _UnitsNotifier(prefs, initial);
});

class _UnitsNotifier extends StateNotifier<String> {
  _UnitsNotifier(this._prefs, String initial) : super(initial);
  final SharedPreferences? _prefs;

  void set(String value) {
    state = value;
    _prefs?.setString(_kUnitsKey, value);
  }
}

/// Provider for the default session privacy setting.
final defaultPrivacyProvider =
    StateNotifierProvider<_PrivacyNotifier, String>((ref) {
  final prefsAsync = ref.watch(_sharedPrefsProvider);
  final prefs = prefsAsync.value;
  final initial = prefs?.getString(_kDefaultPrivacyKey) ?? 'Public';
  return _PrivacyNotifier(prefs, initial);
});

class _PrivacyNotifier extends StateNotifier<String> {
  _PrivacyNotifier(this._prefs, String initial) : super(initial);
  final SharedPreferences? _prefs;

  void set(String value) {
    state = value;
    _prefs?.setString(_kDefaultPrivacyKey, value);
  }
}

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
            onTap: () => context.push('/garage'),
          ),

          const Divider(indent: 56),

          // Units & preferences
          _SectionTitle(title: 'PREFERENCES'),
          _SettingsTile(
            icon: LucideIcons.ruler,
            title: 'Units',
            subtitle: units,
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
          _SectionTitle(title: 'LEGAL'),
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
          _SectionTitle(title: 'ABOUT'),
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

  void _showUnitPicker(BuildContext context, WidgetRef ref, String current) {
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
                for (final option in ['Metric', 'Imperial'])
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
                      option == 'Metric'
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
          ? const Icon(LucideIcons.chevronRight,
              size: 18, color: AppColors.textTertiary)
          : null,
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/sync_provider.dart';
import 'core/services/watch_bridge_service.dart';
import 'features/profile/data/profile_providers.dart';
import 'features/profile/data/ensure_local_profile.dart';

class LapTimeApp extends ConsumerStatefulWidget {
  const LapTimeApp({super.key});

  @override
  ConsumerState<LapTimeApp> createState() => _LapTimeAppState();
}

class _LapTimeAppState extends ConsumerState<LapTimeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize Apple Watch bridge (listens for incoming session files)
      ref.read(watchBridgeProvider);

      // Ensure local profile exists on cold start with restored session.
      // This is critical: when the app restarts, Supabase restores the session
      // from local storage, but ensureLocalProfile only ran during explicit
      // sign-in. Without this, the profile row may not exist and all UPDATE
      // operations silently affect 0 rows.
      _ensureProfileOnStartup();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncServiceProvider).onAppResumed();
      ref.read(watchBridgeProvider).refreshConfig();
    }
  }

  /// If a Supabase session already exists (restored from storage),
  /// ensure the local Drift profile row exists.
  Future<void> _ensureProfileOnStartup() async {
    final repo = ref.read(profileRepositoryProvider);
    await ensureLocalProfile(repo);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One-shot reconciliation gate: re-uploads local data once per install
    // after the v2 sync fixes. Must be watched at the app root.
    ref.watch(resyncGateProvider);

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'LapTime',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

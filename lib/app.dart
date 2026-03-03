import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/supabase_provider.dart';
import 'core/providers/sync_provider.dart';
import 'features/profile/data/profile_repository.dart';

class TestTrackApp extends ConsumerStatefulWidget {
  const TestTrackApp({super.key});

  @override
  ConsumerState<TestTrackApp> createState() => _TestTrackAppState();
}

class _TestTrackAppState extends ConsumerState<TestTrackApp> {
  SyncLifecycleObserver? _syncObserver;

  @override
  void initState() {
    super.initState();
    // Register sync lifecycle observer after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncObserver = SyncLifecycleObserver(ref.read(syncServiceProvider));
      WidgetsBinding.instance.addObserver(_syncObserver!);

      // Ensure local profile exists on cold start with restored session.
      // This is critical: when the app restarts, Supabase restores the session
      // from local storage, but ensureLocalProfile only ran during explicit
      // sign-in. Without this, the profile row may not exist and all UPDATE
      // operations silently affect 0 rows.
      _ensureProfileOnStartup();
    });
  }

  /// If a Supabase session already exists (restored from storage),
  /// ensure the local Drift profile row exists.
  Future<void> _ensureProfileOnStartup() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final db = ref.read(databaseProvider);
      final client = ref.read(supabaseClientProvider);
      final repo = ProfileRepository(db, client);

      final meta = user.userMetadata;
      final name = meta?['full_name'] as String? ??
          meta?['name'] as String? ??
          user.email?.split('@').first ??
          'Driver';

      await repo.ensureLocalProfile(userId: user.id, displayName: name);
    } catch (e) {
      debugPrint('Failed to ensure local profile on startup: $e');
    }
  }

  @override
  void dispose() {
    if (_syncObserver != null) {
      WidgetsBinding.instance.removeObserver(_syncObserver!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TestTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

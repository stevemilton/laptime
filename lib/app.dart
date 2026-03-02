import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/sync_provider.dart';

class LapTimeApp extends ConsumerStatefulWidget {
  const LapTimeApp({super.key});

  @override
  ConsumerState<LapTimeApp> createState() => _LapTimeAppState();
}

class _LapTimeAppState extends ConsumerState<LapTimeApp> {
  SyncLifecycleObserver? _syncObserver;

  @override
  void initState() {
    super.initState();
    // Register sync lifecycle observer after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncObserver = SyncLifecycleObserver(ref.read(syncServiceProvider));
      WidgetsBinding.instance.addObserver(_syncObserver!);
    });
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
      title: 'Lap Time',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/image_upload_service.dart';
import '../services/sync_service.dart';
import 'connectivity_provider.dart';
import 'database_provider.dart';
import 'supabase_provider.dart';

/// Provides a singleton [SyncService] instance wired to the app's database,
/// Supabase client, and connectivity state.
///
/// The service starts its periodic timer on creation and is disposed
/// automatically when the provider is invalidated.
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final supabase = ref.watch(supabaseClientProvider);

  final service = SyncService(
    database: db,
    supabaseClient: supabase,
    imageUploadService: ImageUploadService(supabaseClient: supabase),
  );

  // Start the 60-second periodic sync timer.
  service.start();

  // React to connectivity changes: trigger a sync pass when back online.
  ref.listen<bool>(isOnlineProvider, (previous, next) {
    service.onConnectivityChanged(isOnline: next);
  });

  ref.onDispose(() => service.dispose());

  return service;
});

/// Streams the current [SyncState] (status + pending count + last error).
///
/// Widgets and other providers can watch this to display sync indicators,
/// badge counts, or error banners.
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service.statusStream;
});

/// Convenience provider that returns the current [SyncStatus] enum value.
final syncStatusProvider = Provider<SyncStatus>((ref) {
  final state = ref.watch(syncStateProvider);
  return state.when(
    data: (s) => s.status,
    loading: () => SyncStatus.idle,
    error: (_, _) => SyncStatus.error,
  );
});

/// Convenience provider that returns the number of pending sync items.
final pendingSyncCountProvider = Provider<int>((ref) {
  final state = ref.watch(syncStateProvider);
  return state.when(
    data: (s) => s.pendingCount,
    loading: () => 0,
    error: (_, _) => 0,
  );
});

/// Observer that hooks into [AppLifecycleState] changes and triggers the
/// sync engine when the app resumes.
///
/// Register this observer in your [WidgetsApp] or top-level widget:
/// ```dart
/// WidgetsBinding.instance.addObserver(
///   SyncLifecycleObserver(ref.read(syncServiceProvider)),
/// );
/// ```
class SyncLifecycleObserver with WidgetsBindingObserver {
  SyncLifecycleObserver(this._syncService);

  final SyncService _syncService;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncService.onAppResumed();
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/database_provider.dart';
import '../providers/supabase_provider.dart';
import '../providers/sync_provider.dart';
import 'watch_import_service.dart';

/// MethodChannel bridge between Flutter and the iOS WatchConnectivity handler.
///
/// Receives session files from the Watch (via native iOS handler) and imports
/// them into the local database. Also pushes user/circuit configuration to
/// the Watch when needed.
class WatchBridgeService {
  WatchBridgeService(this._ref);

  final Ref _ref;
  static const _channel = MethodChannel('com.laptime.laptime/watch');

  bool _initialized = false;

  /// Initialize the bridge. Call once at app startup.
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);

    refreshConfig();
  }

  /// Handle incoming calls from native iOS (session file received from Watch).
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'sessionFileReceived':
        final args = call.arguments as Map<Object?, Object?>;
        final filePath = args['filePath'] as String?;
        if (filePath != null) {
          await _onSessionFileReceived(filePath);
        }
        return null;
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Import a Watch session file and trigger sync.
  Future<void> _onSessionFileReceived(String filePath) async {
    debugPrint('[WatchBridge] Session file received: $filePath');

    final db = _ref.read(databaseProvider);
    final importService = WatchImportService(db);

    final sessionId = await importService.importSessionFile(filePath);
    if (sessionId != null) {
      debugPrint('[WatchBridge] Imported session $sessionId, triggering sync');
      _ref.read(syncServiceProvider).requestSync();
    }
  }

  /// Push current user ID and circuit config to the Watch.
  Future<void> _pushUserConfig({
    String? userId,
    double? sfLat1,
    double? sfLng1,
    double? sfLat2,
    double? sfLng2,
  }) async {
    try {
      final resolvedUserId =
          userId ?? Supabase.instance.client.auth.currentUser?.id;
      if (resolvedUserId == null) {
        await _channel.invokeMethod('clearConfig');
        return;
      }

      final args = <String, dynamic>{
        'userId': resolvedUserId,
      };

      if (sfLat1 != null && sfLng1 != null && sfLat2 != null && sfLng2 != null) {
        args['sfLat1'] = sfLat1;
        args['sfLng1'] = sfLng1;
        args['sfLat2'] = sfLat2;
        args['sfLng2'] = sfLng2;
      }

      await _channel.invokeMethod('pushConfig', args);
    } catch (e) {
      debugPrint('[WatchBridge] Failed to push config: $e');
    }
  }

  /// Refresh the currently active watch configuration.
  Future<void> refreshConfig() {
    return _pushUserConfig();
  }

  /// Push start/finish line configuration to the Watch.
  /// Call this when the user selects a circuit on the phone.
  Future<void> pushStartFinishLine({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) async {
    await _pushUserConfig(
      sfLat1: lat1,
      sfLng1: lng1,
      sfLat2: lat2,
      sfLng2: lng2,
    );
  }

  /// Check if an Apple Watch is paired.
  Future<bool> isWatchPaired() async {
    try {
      final result = await _channel.invokeMethod<bool>('isWatchPaired');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}

/// Riverpod provider for WatchBridgeService.
final watchBridgeProvider = Provider<WatchBridgeService>((ref) {
  final service = WatchBridgeService(ref);
  service.initialize();
  ref.listen(authStateProvider, (previous, next) {
    service.refreshConfig();
  });
  return service;
});

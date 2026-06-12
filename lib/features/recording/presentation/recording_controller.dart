import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/providers/sync_provider.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../sectors/data/sector_repository.dart';
import '../data/recording_repository.dart';

/// Provider for the recording repository.
final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = RecordingRepository(db);
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Provider for the current recording state stream.
final recordingStateProvider = StreamProvider<RecordingState>((ref) {
  final repo = ref.watch(recordingRepositoryProvider);
  return repo.stateStream;
});

/// Controller for recording actions.
final recordingControllerProvider =
    StateNotifierProvider<RecordingController, AsyncValue<void>>((ref) {
  return RecordingController(ref);
});

class RecordingController extends StateNotifier<AsyncValue<void>> {
  RecordingController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  RecordingRepository get _repo => _ref.read(recordingRepositoryProvider);

  /// Start a new recording session.
  ///
  /// [circuitId] arms automatic lap detection when the circuit has a
  /// start/finish line; [carId] attributes the session to a garage car.
  Future<String?> startSession({String? circuitId, String? carId}) async {
    state = const AsyncLoading();
    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) throw Exception('Not authenticated');

      final sessionId = await _repo.startSession(
        userId: user.id,
        circuitId: circuitId,
        carId: carId,
      );
      state = const AsyncData(null);
      return sessionId;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  /// Finalize sessions left open by a crash or force-quit, then sync them.
  Future<void> recoverOrphanedSessions() async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;
    final recovered = await _repo.recoverOrphanedSessions(user.id);
    if (recovered > 0) {
      _ref.read(syncServiceProvider).requestSync();
    }
  }

  /// Manually add a lap split.
  Future<void> manualLapSplit() async {
    await _repo.manualLapSplit();
  }

  /// Stop the current recording session.
  Future<String?> stopSession() async {
    state = const AsyncLoading();
    try {
      final privacy = _ref.read(defaultPrivacyProvider);
      final isPublic = privacy != 'Private';
      final sessionId = await _repo.stopSession(isPublic: isPublic);

      if (sessionId != null) {
        // Score the new laps against the circuit's sectors (own and other
        // users'). Fire-and-forget: never blocks finishing a session.
        unawaited(_ref
            .read(sectorRepositoryProvider)
            .persistSectorTimesForSession(sessionId)
            .then((_) => _ref.read(syncServiceProvider).requestSync()));
      }

      // Trigger immediate sync so session + laps + sensor data upload promptly.
      _ref.read(syncServiceProvider).requestSync();

      state = const AsyncData(null);
      return sessionId;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

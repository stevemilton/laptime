import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/supabase_provider.dart';
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
  Future<String?> startSession() async {
    state = const AsyncLoading();
    try {
      final user = _ref.read(currentUserProvider);
      if (user == null) throw Exception('Not authenticated');

      final sessionId = await _repo.startSession(userId: user.id);
      state = const AsyncData(null);
      return sessionId;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
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
      final sessionId = await _repo.stopSession();
      state = const AsyncData(null);
      return sessionId;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

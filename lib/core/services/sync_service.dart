import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'image_upload_service.dart';

/// Sentinel value for [SyncState.copyWith] to distinguish "not provided" from null.
const _sentinel = Object();

/// The current state of the sync engine.
enum SyncStatus { idle, syncing, error }

/// Snapshot of the sync engine's status, exposed via [SyncService.statusStream].
class SyncState {
  const SyncState({
    required this.status,
    required this.pendingCount,
    this.deadLetterCount = 0,
    this.lastError,
  });

  /// Current processing status.
  final SyncStatus status;

  /// Number of items still waiting in the queue.
  final int pendingCount;

  /// Number of items that exhausted their retries and need manual retry
  /// (surfaced in Settings).
  final int deadLetterCount;

  /// Most recent error message, if any.
  final String? lastError;

  static const initial = SyncState(
    status: SyncStatus.idle,
    pendingCount: 0,
  );

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    int? deadLetterCount,
    Object? lastError = _sentinel,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      deadLetterCount: deadLetterCount ?? this.deadLetterCount,
      lastError: lastError == _sentinel ? this.lastError : lastError as String?,
    );
  }
}

/// Offline-first sync engine that processes the [LocalSyncQueue] table and
/// pushes pending mutations to Supabase when connectivity is available.
///
/// ## Triggers
/// The sync loop is triggered when:
/// - Network connectivity is restored (call [onConnectivityChanged]).
/// - The app resumes from background (call [onAppResumed]).
/// - A new item is enqueued after a session save (call [requestSync]).
/// - A periodic 60-second timer fires.
///
/// ## Retry Strategy
/// Failed items are retried up to [maxRetries] times with exponential backoff
/// (base [retryBaseSeconds] seconds, capped at 60 seconds). Items that exceed
/// the retry limit remain in the queue with an error message and are skipped
/// during subsequent sync passes.
///
/// ## Chunked Uploads
/// Large sensor payloads (table `lap_sensor_data`) are split into chunks of
/// [sensorChunkSize] bytes and uploaded sequentially. Each chunk is stored as
/// a separate row on the remote table with a `chunk_index` field.
class SyncService {
  SyncService({
    required AppDatabase database,
    required SupabaseClient supabaseClient,
    required ImageUploadService imageUploadService,
  })  : _db = database,
        _supabase = supabaseClient,
        _imageUpload = imageUploadService;

  final AppDatabase _db;
  final SupabaseClient _supabase;
  final ImageUploadService _imageUpload;

  /// Maximum number of retry attempts per queue item.
  static const int maxRetries = 5;

  /// Base delay in seconds for exponential backoff (2^attempt * base).
  static const int retryBaseSeconds = 2;

  /// Maximum payload size (in bytes) before sensor data is chunked.
  /// Supabase / PostgREST has a ~1 MB default body limit; we chunk at 500 KB
  /// to leave headroom for JSON overhead.
  static const int sensorChunkSize = 500 * 1024;

  /// Number of queue items fetched per processing pass.
  static const int _batchSize = 50;

  /// Tables that other queued rows can reference via FK. A failure (or
  /// backoff wait) on one of these halts the pass so children enqueued
  /// behind it don't burn their retries on FK violations. Failures on
  /// leaf tables (likes, comments, sensor data, ...) skip and continue —
  /// one poisoned row must not freeze unrelated sync traffic.
  static const Set<String> _parentTables = {
    'profiles',
    'cars',
    'circuits',
    'sessions',
    'laps',
    'sectors',
    'teams',
    'crews',
  };

  Timer? _periodicTimer;
  bool _isSyncing = false;
  bool _disposed = false;
  bool _hasVerifiedBuckets = false;

  final _statusController = StreamController<SyncState>.broadcast();

  /// Stream of sync status updates for the UI / providers.
  Stream<SyncState> get statusStream => _statusController.stream;

  SyncState _currentState = SyncState.initial;

  // ── Lifecycle ──

  /// Start the periodic sync timer. Should be called once when the service
  /// is created.
  void start() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _processQueue(),
    );
  }

  /// Tear down timers and close the status stream.
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _statusController.close();
  }

  // ── Public Triggers ──

  /// Called when network connectivity changes. Triggers a sync pass if
  /// the device has come back online.
  void onConnectivityChanged({required bool isOnline}) {
    if (isOnline) {
      _processQueue();
    }
  }

  /// Called when the app resumes from the background.
  void onAppResumed() {
    _processQueue();
  }

  /// Request an immediate sync pass. Typically called after a session save
  /// enqueues new items.
  void requestSync() {
    _processQueue();
  }

  /// Reset all dead-lettered items for another full round of retries,
  /// then process the queue. Surfaced as "Retry failed sync" in Settings.
  Future<void> retryDeadLetters() async {
    await _db.resetDeadLetters(maxRetries: maxRetries);
    await _processQueue();
  }

  // ── Core Processing Loop ──

  Future<void> _processQueue() async {
    if (_isSyncing || _disposed) return;

    // Don't process if user is not authenticated — would burn retry attempts.
    final session = _supabase.auth.currentSession;
    if (session == null) {
      debugPrint('SyncService: skipping sync — no active auth session');
      return;
    }

    _isSyncing = true;
    _emitState(status: SyncStatus.syncing);

    try {
      // On first authenticated sync pass, verify required storage buckets
      // exist. Logs a prominent warning if a bucket is missing (most likely
      // the storage migration was never applied).
      if (!_hasVerifiedBuckets) {
        await _verifyStorageBuckets();
        _hasVerifiedBuckets = true;
      }

      // FIFO with dependency-aware halting: rows are enqueued
      // parent-before-child (session before its laps, lap before its
      // sensor data). A failed or backoff-delayed PARENT row halts the
      // pass so children behind it don't burn retries on FK violations;
      // failed leaf rows are skipped so one poisoned like/comment can't
      // freeze the rest of the queue.
      String? haltError;
      var halted = false;
      var offset = 0;
      while (!_disposed && !halted) {
        final items = await _db.getPendingSyncItems(
          limit: _batchSize + offset,
          maxRetries: maxRetries,
        );
        if (items.length <= offset) break;

        var processedAny = false;
        for (final item in items.skip(offset)) {
          if (_disposed) break;
          final isParent = _parentTables.contains(item.targetTable);
          if (!_isEligibleForRetry(item)) {
            if (isParent) {
              halted = true;
              break;
            }
            offset++; // leaf in backoff: leave it, keep going
            continue;
          }
          final error = await _processSingleItem(item);
          processedAny = true;
          if (error != null) {
            if (isParent) {
              haltError = '${item.targetTable}: $error';
              halted = true;
              break;
            }
            offset++; // failed leaf stays for its backoff retry
          }
        }
        if (!processedAny && !halted) break;
      }

      _emitState(
        status: SyncStatus.idle,
        pendingCount: await _db.pendingSyncCount(maxRetries: maxRetries),
        deadLetterCount: await _db.deadLetterCount(maxRetries: maxRetries),
        lastError: haltError,
      );
    } catch (e) {
      debugPrint('SyncService: queue processing error: $e');
      _emitState(
        status: SyncStatus.error,
        lastError: e.toString(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Verify that required Supabase Storage buckets exist by attempting to
  /// list their contents. Logs a clear warning for any missing bucket so
  /// the developer knows to apply the storage migration.
  Future<void> _verifyStorageBuckets() async {
    const requiredBuckets = ['avatars', 'car-images', 'team-logos'];
    for (final bucket in requiredBuckets) {
      try {
        // A minimal list call — returns empty list if the bucket is empty,
        // throws StorageException if the bucket doesn't exist.
        await _supabase.storage.from(bucket).list(path: '', searchOptions: const SearchOptions(limit: 1));
      } catch (e) {
        debugPrint(
          '╔══════════════════════════════════════════════════════════╗\n'
          '║  SYNC ERROR: Storage bucket "$bucket" is not accessible ║\n'
          '║  Error: $e\n'
          '║  Run the migration: 20260303_storage_and_car_columns.sql ║\n'
          '╚══════════════════════════════════════════════════════════╝',
        );
      }
    }
  }

  /// Determine whether a queue item should be attempted right now.
  ///
  /// Items that have exceeded [maxRetries] are skipped. Items with a
  /// [lastAttemptedAt] timestamp are subject to exponential backoff; they
  /// are only eligible once the required delay has elapsed.
  bool _isEligibleForRetry(LocalSyncQueueData item) {
    if (item.retryCount >= maxRetries) return false;

    if (item.lastAttemptedAt != null && item.retryCount > 0) {
      final delaySec =
          min(pow(2, item.retryCount) * retryBaseSeconds, 60).toInt();
      final nextAttempt =
          item.lastAttemptedAt!.add(Duration(seconds: delaySec));
      if (DateTime.now().isBefore(nextAttempt)) return false;
    }

    return true;
  }

  /// Process a single sync queue item. Returns null on success, or the
  /// error message on failure (which makes the queue pass halt when the
  /// item belongs to a parent table).
  ///
  /// Image uploads and data upserts are decoupled: if an image upload fails
  /// (e.g. Supabase Storage connectivity issue), the row data is still pushed
  /// to the remote table — just without the image URL. The sync item stays in
  /// the queue so the image upload is retried on the next pass. Once it
  /// eventually succeeds, the remote row is updated with the public URL.
  Future<String?> _processSingleItem(LocalSyncQueueData item) async {
    try {
      if (item.targetTable == 'lap_sensor_data' &&
          item.operation != 'delete') {
        await _uploadSensorData(item);
      } else {
        final payload =
            jsonDecode(item.payloadJson) as Map<String, dynamic>;

        // Attempt to upload any local image files.
        // Returns the list of field names whose upload failed.
        var failedImageFields = const <String>[];
        if (item.operation != 'delete') {
          failedImageFields = await _uploadImageFields(
            table: item.targetTable,
            recordId: item.recordId,
            payload: payload,
          );

          // Persist the payload with any successfully-uploaded public URLs
          // so that retries don't re-upload from local paths that iOS may
          // have cleaned up.
          await _db.updateSyncPayload(item.id, jsonEncode(payload));
        }

        // Build the upsert payload. Strip fields that still hold a local
        // file path — we never want device-specific paths in the remote DB.
        final upsertPayload = Map<String, dynamic>.from(payload);
        for (final field in failedImageFields) {
          upsertPayload.remove(field);
        }

        await _executeOperation(
          table: item.targetTable,
          operation: item.operation,
          recordId: item.recordId,
          payload: upsertPayload,
        );

        if (failedImageFields.isNotEmpty) {
          // Row data synced, but one or more images couldn't upload.
          // Keep the item in the queue so the image upload is retried.
          // Returns SUCCESS to the queue loop: the row exists remotely, so
          // children must not be halted behind a pending image.
          debugPrint(
            'SyncService: data synced for ${item.targetTable}/${item.recordId} '
            'but image upload failed for $failedImageFields — will retry',
          );
          await _db.markSyncFailed(
            item.id,
            'Image upload pending for: $failedImageFields',
          );
          return null;
        }
      }

      await _db.markSyncCompleted(item.id);
      return null;
    } catch (e, stack) {
      debugPrint(
        'SyncService: failed to sync item ${item.id} '
        '(${item.targetTable}/${item.operation}): $e\n$stack',
      );
      await _db.markSyncFailed(item.id, e.toString());
      return e.toString();
    }
  }

  /// Attempt to upload local image files referenced in [payload] to Supabase
  /// Storage. For each image that uploads successfully the local path in
  /// [payload] is replaced with the public URL **in-place** and the local
  /// Drift record is updated.
  ///
  /// Returns the list of field names whose upload **failed**. An empty list
  /// means all images (if any) were uploaded successfully.
  Future<List<String>> _uploadImageFields({
    required String table,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot upload images without authenticated user');
    }

    final failedFields = <String>[];

    for (final field in ImageUploadService.imageFields) {
      final value = payload[field] as String?;
      if (!ImageUploadService.isLocalPath(value)) continue;

      debugPrint(
        'SyncService: detected local image for $table.$field = $value',
      );

      final bucket = ImageUploadService.bucketFor(table, field);
      if (bucket == null) {
        debugPrint(
          'SyncService: no bucket mapping for $table:$field — skipping',
        );
        continue;
      }

      try {
        final storagePath =
            ImageUploadService.buildStoragePath(userId, recordId, value!);

        final publicUrl = await _imageUpload.uploadFile(
          localPath: value,
          bucket: bucket,
          storagePath: storagePath,
        );

        // Replace local path with public URL in the outgoing payload.
        payload[field] = publicUrl;

        // Update the local Drift record so the UI shows the remote URL.
        await _updateLocalImageUrl(
          table: table,
          recordId: recordId,
          field: field,
          url: publicUrl,
        );
      } catch (e) {
        debugPrint(
          'SyncService: image upload FAILED for $table.$field: $e — '
          'data will sync without image, upload will retry next pass',
        );
        failedFields.add(field);
      }
    }

    return failedFields;
  }

  /// Writes the uploaded public URL back to the local Drift record.
  Future<void> _updateLocalImageUrl({
    required String table,
    required String recordId,
    required String field,
    required String url,
  }) async {
    switch ('$table:$field') {
      case 'profiles:avatar_url':
        await (_db.update(_db.localProfiles)
              ..where((t) => t.id.equals(recordId)))
            .write(LocalProfilesCompanion(avatarUrl: Value(url)));
      case 'cars:image_url':
        await (_db.update(_db.localCars)
              ..where((t) => t.id.equals(recordId)))
            .write(LocalCarsCompanion(imageUrl: Value(url)));
      case 'teams:logo_url':
        await (_db.update(_db.localTeams)
              ..where((t) => t.id.equals(recordId)))
            .write(LocalTeamsCompanion(logoUrl: Value(url)));
    }
  }

  /// Composite-PK tables don't have a single 'id' column.
  /// Use payload fields for update/delete filters instead.
  static const _compositePkTables = {
    'team_members': ['team_id', 'user_id'],
    'crew_members': ['crew_id', 'user_id'],
    'session_likes': ['session_id', 'user_id'],
    'follows': ['follower_id', 'following_id'],
  };

  /// Execute a single Supabase operation (insert/update/delete).
  Future<void> _executeOperation({
    required String table,
    required String operation,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    switch (operation) {
      case 'insert':
      // Inserts AND updates execute as idempotent upserts: every enqueued
      // payload is a full row (built by SyncPayloads), so the insert path
      // of the upsert can never trip NOT NULL constraints, and an update
      // that races a missing remote row recreates it instead of silently
      // matching zero rows.
      case 'update':
        if (table == 'circuits') {
          // Reconciliation re-enqueues every locally cached circuit,
          // including catalogue rows that already exist remotely and
          // aren't ours to update — insert-or-skip instead of upsert.
          await _supabase.from(table).upsert(payload, ignoreDuplicates: true);
        } else {
          await _supabase.from(table).upsert(payload);
        }
      case 'delete':
        if (_compositePkTables.containsKey(table)) {
          var query = _supabase.from(table).delete();
          for (final col in _compositePkTables[table]!) {
            final value = payload[col];
            if (value == null) {
              throw StateError(
                'Missing composite PK field "$col" in payload for $table delete',
              );
            }
            query = query.eq(col, value);
          }
          await query;
        } else if (table == 'lap_sensor_data') {
          // Large records were uploaded as chunk rows carrying parent_id;
          // an id-only delete would orphan them.
          await _supabase
              .from(table)
              .delete()
              .or('id.eq.$recordId,parent_id.eq.$recordId');
        } else {
          await _supabase.from(table).delete().eq('id', recordId);
        }
      default:
        throw ArgumentError('Unknown sync operation: $operation');
    }
  }

  // ── Chunked Sensor Data Upload ──

  static const _uuid = Uuid();

  /// Upload sensor data, splitting into chunks if the payload exceeds
  /// [sensorChunkSize] bytes.
  ///
  /// Small payloads are upserted as a single row. Large payloads are split
  /// by dividing the arrays into roughly equal parts; each part is stored
  /// as a separate row (fresh UUID) carrying `parent_id`, `chunk_index`
  /// and `chunk_total` so readers can reassemble the logical record.
  /// Chunk rows upsert on (parent_id, chunk_index), so retries after a
  /// partial failure are idempotent.
  Future<void> _uploadSensorData(LocalSyncQueueData item) async {
    final payload = jsonDecode(item.payloadJson) as Map<String, dynamic>;
    final encoded = utf8.encode(item.payloadJson);

    if (encoded.length <= sensorChunkSize) {
      // Small enough to upload in one go.
      await _supabase.from(item.targetTable).upsert(payload);
      return;
    }

    // Determine number of chunks needed.
    final chunkCount = (encoded.length / sensorChunkSize).ceil();

    // Identify array fields that should be split across chunks.
    final arrayFields = <String, List<dynamic>>{};
    final scalarFields = <String, dynamic>{};

    for (final entry in payload.entries) {
      if (entry.value is List) {
        arrayFields[entry.key] = entry.value as List<dynamic>;
      } else {
        scalarFields[entry.key] = entry.value;
      }
    }

    // If there are no array fields, just upload the whole thing.
    if (arrayFields.isEmpty) {
      await _supabase.from(item.targetTable).upsert(payload);
      return;
    }

    // Compute the length of the longest array to determine slice size.
    final maxLen = arrayFields.values
        .map((list) => list.length)
        .reduce((a, b) => a > b ? a : b);
    final sliceSize = (maxLen / chunkCount).ceil();

    final originalId = payload['id'] as String? ?? item.recordId;

    for (var i = 0; i < chunkCount; i++) {
      final chunkPayload = Map<String, dynamic>.from(scalarFields);

      // Each chunk is its own row with a real UUID primary key; the
      // original record reference lives in parent_id.
      chunkPayload['id'] = _uuid.v4();
      chunkPayload['chunk_index'] = i;
      chunkPayload['chunk_total'] = chunkCount;
      chunkPayload['parent_id'] = originalId;

      for (final entry in arrayFields.entries) {
        final start = i * sliceSize;
        final end = min(start + sliceSize, entry.value.length);
        chunkPayload[entry.key] = start < entry.value.length
            ? entry.value.sublist(start, end)
            : <dynamic>[];
      }

      await _supabase
          .from(item.targetTable)
          .upsert(chunkPayload, onConflict: 'parent_id,chunk_index');
    }
  }

  // ── State Emission ──

  void _emitState({
    SyncStatus? status,
    int? pendingCount,
    int? deadLetterCount,
    String? lastError,
  }) {
    if (_disposed) return;

    _currentState = _currentState.copyWith(
      status: status,
      pendingCount: pendingCount,
      deadLetterCount: deadLetterCount,
      lastError: lastError,
    );

    if (!_statusController.isClosed) {
      _statusController.add(_currentState);
    }
  }
}

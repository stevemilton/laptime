import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'image_upload_service.dart';

/// The current state of the sync engine.
enum SyncStatus { idle, syncing, error }

/// Snapshot of the sync engine's status, exposed via [SyncService.statusStream].
class SyncState {
  const SyncState({
    required this.status,
    required this.pendingCount,
    this.lastError,
  });

  /// Current processing status.
  final SyncStatus status;

  /// Number of items still waiting in the queue.
  final int pendingCount;

  /// Most recent error message, if any.
  final String? lastError;

  static const initial = SyncState(
    status: SyncStatus.idle,
    pendingCount: 0,
  );

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    String? lastError,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastError: lastError ?? this.lastError,
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

      while (!_disposed) {
        final items = await _db.getPendingSyncItems(
          limit: _batchSize,
          maxRetries: maxRetries,
        );

        // Filter to only items that are eligible for retry (backoff).
        final eligible = items.where(_isEligibleForRetry).toList();
        if (eligible.isEmpty) break;

        for (final item in eligible) {
          if (_disposed) break;
          await _processSingleItem(item);
        }
      }

      // After processing, update the pending count.
      final remaining = await _db.getPendingSyncItems(
        limit: _batchSize,
        maxRetries: maxRetries,
      );

      _emitState(
        status: SyncStatus.idle,
        pendingCount: remaining.length,
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

  /// Process a single sync queue item.
  ///
  /// Image uploads and data upserts are decoupled: if an image upload fails
  /// (e.g. Supabase Storage connectivity issue), the row data is still pushed
  /// to the remote table — just without the image URL. The sync item stays in
  /// the queue so the image upload is retried on the next pass. Once it
  /// eventually succeeds, the remote row is updated with the public URL.
  Future<void> _processSingleItem(LocalSyncQueueData item) async {
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
          debugPrint(
            'SyncService: data synced for ${item.targetTable}/${item.recordId} '
            'but image upload failed for $failedImageFields — will retry',
          );
          await _db.markSyncFailed(
            item.id,
            'Image upload pending for: $failedImageFields',
          );
          return;
        }
      }

      await _db.markSyncCompleted(item.id);
    } catch (e, stack) {
      debugPrint(
        'SyncService: failed to sync item ${item.id} '
        '(${item.targetTable}/${item.operation}): $e\n$stack',
      );
      await _db.markSyncFailed(item.id, e.toString());
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
        await _supabase.from(table).upsert(payload);
      case 'update':
        // Use update (not upsert) for update operations. Upsert generates
        // INSERT ... ON CONFLICT DO UPDATE which requires all NOT NULL columns
        // in the INSERT portion. Update payloads only include changed fields,
        // so the INSERT would fail with a NOT NULL constraint violation
        // (e.g. cars.user_id is NOT NULL but not in the update payload).
        if (_compositePkTables.containsKey(table)) {
          var query = _supabase.from(table).update(payload);
          for (final col in _compositePkTables[table]!) {
            final value = payload[col];
            if (value == null) {
              throw StateError(
                'Missing composite PK field "$col" in payload for $table update',
              );
            }
            query = query.eq(col, value);
          }
          await query;
        } else {
          await _supabase.from(table).update(payload).eq('id', recordId);
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
        } else {
          await _supabase.from(table).delete().eq('id', recordId);
        }
      default:
        throw ArgumentError('Unknown sync operation: $operation');
    }
  }

  // ── Chunked Sensor Data Upload ──

  /// Upload sensor data, splitting into chunks if the payload exceeds
  /// [sensorChunkSize] bytes.
  ///
  /// Small payloads are upserted as a single row. Large payloads are split
  /// by dividing the JSON-encoded arrays into roughly equal parts, each
  /// stored as a separate row with a `chunk_index` field appended.
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

    for (var i = 0; i < chunkCount; i++) {
      final chunkPayload = Map<String, dynamic>.from(scalarFields);

      // Override the `id` so each chunk has a unique primary key.
      final originalId = payload['id'] as String? ?? item.recordId;
      chunkPayload['id'] = '${originalId}_chunk_$i';

      // Keep the original record reference so chunks can be reassembled.
      chunkPayload['chunk_index'] = i;
      chunkPayload['chunk_total'] = chunkCount;
      chunkPayload['parent_id'] = originalId;

      for (final entry in arrayFields.entries) {
        final start = i * sliceSize;
        final end = min(start + sliceSize, entry.value.length);
        if (start < entry.value.length) {
          chunkPayload[entry.key] = jsonEncode(entry.value.sublist(start, end));
        } else {
          chunkPayload[entry.key] = jsonEncode(<dynamic>[]);
        }
      }

      await _supabase.from(item.targetTable).upsert(chunkPayload);
    }
  }

  // ── State Emission ──

  void _emitState({
    SyncStatus? status,
    int? pendingCount,
    String? lastError,
  }) {
    if (_disposed) return;

    _currentState = _currentState.copyWith(
      status: status,
      pendingCount: pendingCount,
      lastError: lastError,
    );

    if (!_statusController.isClosed) {
      _statusController.add(_currentState);
    }
  }
}

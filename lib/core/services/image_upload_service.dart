import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles uploading local image files to Supabase Storage and returning
/// the public URL to store in the database.
///
/// Maps known table + column pairs to the appropriate storage bucket:
///   - `profiles:avatar_url` → `avatars`
///   - `cars:image_url`      → `car-images`
///   - `teams:logo_url`      → `team-logos`
class ImageUploadService {
  ImageUploadService({required SupabaseClient supabaseClient})
      : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  /// Maps `table:field` to storage bucket name.
  static const _bucketMap = <String, String>{
    'profiles:avatar_url': 'avatars',
    'cars:image_url': 'car-images',
    'teams:logo_url': 'team-logos',
  };

  /// The set of field names that may contain image paths.
  static const imageFields = {'avatar_url', 'image_url', 'logo_url'};

  /// Returns the bucket name for a given [table] and [field], or `null` if
  /// the combination is not a known image field.
  static String? bucketFor(String table, String field) {
    return _bucketMap['$table:$field'];
  }

  /// Returns `true` if [value] looks like a local file path rather than a
  /// remote URL. Null and empty strings return `false`.
  static bool isLocalPath(String? value) {
    if (value == null || value.isEmpty) return false;
    return !value.startsWith('http');
  }

  /// Builds the storage path: `{userId}/{recordId}.{ext}`
  ///
  /// This matches the RLS folder constraint that scopes writes to the
  /// authenticated user's folder.
  static String buildStoragePath(
      String userId, String recordId, String localPath) {
    final ext = p.extension(localPath).replaceFirst('.', '');
    final safeExt = ext.isNotEmpty ? ext : 'jpg';
    return '$userId/$recordId.$safeExt';
  }

  /// Uploads a local file to [bucket] at [storagePath] and returns the
  /// public URL.
  ///
  /// Uses `upsert: true` so re-uploads (e.g. after a retry) overwrite the
  /// previous version instead of failing.
  Future<String> uploadFile({
    required String localPath,
    required String bucket,
    required String storagePath,
  }) async {
    final file = File(localPath);
    if (!file.existsSync()) {
      debugPrint(
        'ImageUploadService: file NOT found on disk: $localPath',
      );
      throw FileSystemException('Image file not found', localPath);
    }

    final bytes = await file.readAsBytes();
    debugPrint(
      'ImageUploadService: uploading ${bytes.length} bytes '
      'to $bucket/$storagePath ...',
    );

    try {
      await _supabase.storage.from(bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
    } catch (e) {
      debugPrint(
        'ImageUploadService: uploadBinary FAILED '
        'bucket=$bucket path=$storagePath error=$e',
      );
      rethrow;
    }

    final publicUrl =
        _supabase.storage.from(bucket).getPublicUrl(storagePath);

    debugPrint(
      'ImageUploadService: uploaded $localPath → $publicUrl',
    );

    return publicUrl;
  }
}

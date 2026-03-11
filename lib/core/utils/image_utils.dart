import 'dart:io';

/// Check whether a local image file actually exists on disk.
///
/// Returns true for HTTP URLs (assumed to exist remotely) and for
/// local file paths that resolve to a real file.
bool imageFileExists(String? path) {
  if (path == null || path.isEmpty) return false;
  if (path.startsWith('http')) return true;
  return File(path).existsSync();
}

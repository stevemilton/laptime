/// Extract initials from a display name.
///
/// Returns up to 2 uppercase characters from the first and last words,
/// or a single character if the name has only one word.
/// Returns null if the name is null or empty.
String? getInitials(String? name) {
  if (name == null || name.isEmpty) return null;
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : null;
}

import 'dart:math';

/// Generates a random 8-character hex invite code (uppercase).
String generateInviteCode() {
  final random = Random.secure();
  return List.generate(
      8, (_) => random.nextInt(16).toRadixString(16)).join().toUpperCase();
}

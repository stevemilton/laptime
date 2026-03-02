import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the current connectivity status.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Returns true if the device has any network connection.
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (results) => results.any((r) => r != ConnectivityResult.none),
    loading: () => true, // assume online until proven otherwise
    error: (_, _) => false,
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/format_utils.dart';

// ── Preference keys ──

const _kUnitsKey = 'pref_units';
const _kDefaultPrivacyKey = 'pref_default_privacy';

// ── Shared Preferences ──

/// Provider for the shared preferences instance.
final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

// ── Units ──

/// Provider for the user's preferred unit system.
final unitsProvider = StateNotifierProvider<UnitsNotifier, UnitSystem>((ref) {
  final prefsAsync = ref.watch(sharedPrefsProvider);
  final prefs = prefsAsync.value;
  final stored = prefs?.getString(_kUnitsKey) ?? 'Metric';
  final initial =
      stored == 'Imperial' ? UnitSystem.imperial : UnitSystem.metric;
  return UnitsNotifier(prefs, initial);
});

class UnitsNotifier extends StateNotifier<UnitSystem> {
  UnitsNotifier(this._prefs, UnitSystem initial) : super(initial);
  final SharedPreferences? _prefs;

  void set(UnitSystem value) {
    state = value;
    _prefs?.setString(_kUnitsKey, value.label);
  }
}

// ── Default Privacy ──

/// Provider for the default session privacy setting.
final defaultPrivacyProvider =
    StateNotifierProvider<PrivacyNotifier, String>((ref) {
  final prefsAsync = ref.watch(sharedPrefsProvider);
  final prefs = prefsAsync.value;
  final initial = prefs?.getString(_kDefaultPrivacyKey) ?? 'Public';
  return PrivacyNotifier(prefs, initial);
});

class PrivacyNotifier extends StateNotifier<String> {
  PrivacyNotifier(this._prefs, String initial) : super(initial);
  final SharedPreferences? _prefs;

  void set(String value) {
    state = value;
    _prefs?.setString(_kDefaultPrivacyKey, value);
  }
}

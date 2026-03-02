/// Environment configuration.
///
/// All values MUST be provided via --dart-define at build time.
/// No secrets or keys are hardcoded in source.
///
/// Example:
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://yourproject.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=your_anon_key \
///   --dart-define=OPENWEATHERMAP_API_KEY=your_key
/// ```
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const openWeatherMapApiKey = String.fromEnvironment(
    'OPENWEATHERMAP_API_KEY',
    defaultValue: '',
  );
}

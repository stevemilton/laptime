/// Environment configuration.
///
/// The Supabase anon key is a public/publishable key by design
/// (enforced by RLS, not secrecy). Safe to include as compile-time default.
/// Override via --dart-define for CI/CD or different environments.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://clptbdjqnnvwmxgusmma.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNscHRiZGpxbm52d214Z3VzbW1hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzOTc1MDUsImV4cCI6MjA4Nzk3MzUwNX0.6z4R402-nIZg1InBY0lla6OAOpu5kT9trjRnBTtKaHg',
  );

  static const openWeatherMapApiKey = String.fromEnvironment(
    'OPENWEATHERMAP_API_KEY',
    defaultValue: '',
  );
}

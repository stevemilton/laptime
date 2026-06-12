# LapTime - Claude Code Context

## What This Is
LapTime is a production Flutter iOS app - "Strava for track days." It records GPS traces + phone sensor data during motorsport track sessions, captures weather automatically, enables user-defined sectors with retroactive leaderboards, and has a social feed.

## Tech Stack
- **Framework**: Flutter (iOS 16+), Dart 3.x
- **State**: Riverpod 2.x (manual providers, no code-gen) via `flutter_riverpod`
- **Routing**: GoRouter with ShellRoute (4 bottom tabs: Record, Feed, Sectors, Profile)
- **Backend**: Supabase (PostgreSQL + PostGIS), project ID `clptbdjqnnvwmxgusmma`
- **Local DB**: Drift (SQLite), offline-first with sync queue
- **GPS**: `geolocator` with automotive navigation activity type
- **Sensors**: `sensors_plus` (accel 50Hz, gyro 50Hz, baro 1Hz, mag 10Hz)
- **Maps**: `flutter_map` + OpenStreetMap tiles
- **Weather**: OpenWeatherMap One Call 3.0 via `dio`
- **Auth**: Apple Sign-In + Google Sign-In + email/password
- **Icons**: Lucide only (NO EMOJIS anywhere)
- **Fonts**: Rufner (headings), Rethink Sans (body)

## Project Structure
```
lib/
  main.dart, app.dart
  core/          # theme, router, database, services, providers, utils, widgets
  features/
    auth/        # login, auth controller
    disclaimer/  # legal disclaimer acceptance
    recording/   # record screen, recording screen, lap detection
    session/     # session detail, edit, lap detail
    feed/        # social feed with Following/Nearby/Teams tabs
    sectors/     # sector creation, leaderboards
    profile/     # profile screen, edit profile
    garage/      # car form CRUD
    social/      # following, teams
    settings/    # settings, legal screens
    telemetry/   # lap comparison, charts, G-G diagram
```

## Architecture Principles
1. **Offline-first writes**: All mutations written to Drift (SQLite) first, synced to Supabase via a strictly FIFO queue (parent rows enqueued before children). Sync payloads are built by `SyncPayloads` (lib/core/services/sync_payloads.dart) — every key must match a remote column; inserts/updates execute as upserts, so payloads must be full rows. Multi-user reads (feed, leaderboards, team members, circuits) are remote-first with the local DB as cache.
2. **Never block recording**: Weather is fire-and-forget, sync is async, lap state transitions are synchronous with persistence deferred.
3. **Pure geometry lap detection**: 2D line-segment intersection with tolerance, no cloud dependency. Armed from the selected circuit's start/finish line.
4. **Retroactive sector scoring**: Sector creation scores all historical laps; finishing a session scores its laps against all of the circuit's sectors.
5. **Trace format v2**: lap traces are JSON arrays of `[lng, lat, tMs, speedMps]` (see `TraceCodec` in lib/core/utils/trace_codec.dart). GPS Doppler speed is the only speed source — never integrate accelerometer data. Use `userAccelerometerEventStream` (gravity-removed) for G channels.

## Design System
- Primary purple: `#5B3491`, Deep: `#1E0F35`, Bright: `#7B4DB8`
- Light/white UI with purple-tinted shadows
- Border radii: 6 (sm), 12 (md), 18 (lg), 24 (xl)
- No emojis - use `LucideIcons.*` exclusively

## Build & Run
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://clptbdjqnnvwmxgusmma.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<key> \
  --dart-define=OPENWEATHERMAP_API_KEY=<key> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<id>.apps.googleusercontent.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
```

## Key Files
- `lib/core/database/app_database.dart` - Drift schema (13 local tables + sync queue)
- `lib/core/router/app_router.dart` - All routes + auth/disclaimer redirect guards
- `lib/core/services/sync_service.dart` - Offline sync engine with exponential backoff
- `lib/features/recording/data/recording_repository.dart` - GPS + sensor recording orchestrator
- `lib/features/recording/data/lap_detection_service.dart` - Start/finish line crossing detection
- `supabase/migrations/` - SQL schema (run in Supabase SQL editor)

## Conventions
- Feature folders follow `data/` + `presentation/` pattern
- Providers use Riverpod with `ref.watch()` / `ref.read()`
- All Supabase writes go through Drift sync queue, never direct
- `AppColors`, `AppTypography`, `AppTheme` for all styling
- `format_utils.dart` for time/distance formatting

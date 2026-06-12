# LapTime — Full Code Review & v2 Readiness Assessment

Date: 2026-06-12. Scope: entire `lib/` tree (~20k lines), all 4 Supabase migrations, iOS config, pubspec. Review method: line-by-line review of the recording/telemetry pipeline, plus three deep reviews of (1) the data/sync layer, (2) social/feed/sectors, (3) app shell/auth/iOS.

## Executive summary

The UI layer is in good shape — consistent design system, proper controller disposal, clean Riverpod usage, sensible empty/loading states. But **the app's core promises are currently not functioning**:

1. **Cloud sync is broken end-to-end.** The local Drift schema and the Supabase schema have drifted apart, so laps, sensor data, sectors, session edits, car edits, and unfollows fail to sync 100% of the time, exhaust their 5 retries, and are silently dead-lettered. The app looks offline-first but is effectively offline-only for recorded data.
2. **Automatic lap detection is dead code.** `setStartFinishLine` is never called from anywhere; only the Manual Lap button produces laps. The circuits table (with PostGIS start/finish lines) is completely unwired from the UI.
3. **Sector timing can never produce a result** for app-recorded laps (traces have no timestamps; sessions have no circuit ID), and sector times are never synced, so leaderboards are single-player by construction.
4. **The speed channel is physically incapable of being right** (gravity-contaminated accelerometer integration; the accurate GPS speed is discarded). This is the "speed tracking is off" issue.
5. **App Store blocker:** no account deletion flow (Guideline 5.1.1(v)), despite the app's own Terms promising one.

The architecture (Drift + FIFO sync queue + Supabase, pure-geometry lap detection) is sound and salvageable. The systemic root cause is that **nothing ever exercised the sync queue or RLS policies against the real remote schema**, and `catch (_)` swallows every failure, so none of this surfaced. The single biggest v2 investment should be: trace format v2 (with timestamps + speed), schema parity + integration tests, and a pull-sync direction.

---

## 1. The speed tracking issue (root cause analysis)

Three compounding defects:

### 1a. Speed is integrated from a gravity-contaminated accelerometer — Critical
`lib/features/telemetry/data/telemetry_processor.dart:117-130` estimates speed by numerically integrating longitudinal acceleration from v=0 at each lap start. But `lib/core/services/sensor_service.dart:85` subscribes to `accelerometerEventStream`, which **includes gravity** (~9.81 m/s²). Unless the phone is perfectly level, a constant gravity component leaks into the Y axis and integrates into velocity at up to 9.81 m/s per second — the estimate saturates at the 0 or 300 km/h clamp within seconds. It also assumes a fixed landscape mount (`X = lateral, Y = longitudinal`) with no calibration, and never re-anchors to any absolute reference. The same gravity contamination corrupts the G-G diagram and lateral/longitudinal G channels.

**Fix:** use `userAccelerometerEventStream` (gravity-removed) for G channels; take speed from GPS (see 1b), optionally sensor-fused with accelerometer between GPS fixes; add a mount-calibration step (capture gravity vector at session start, rotate axes into the car frame).

### 1b. The accurate GPS speed is thrown away — Critical
`lib/core/services/location_service.dart:94` captures `position.speed` (Doppler-based, the most accurate speed source on a phone) into `GpsPoint`, but `GeoUtils.encodeTrace` (`lib/core/utils/geo_utils.dart:97-102`) serializes only `[lng,lat]` pairs. No speed, no timestamp, no altitude, no accuracy is ever persisted. Post-hoc speed reconstruction from the trace is impossible (no timestamps).

**Fix (cornerstone of v2):** trace format v2 — `[lng, lat, t_ms, speed_mps]` (optionally alt/accuracy). This single change unlocks correct speed charts, sector timing (§3), distance-based lap comparison, and map playback.

### 1c. The lap-comparison "delta trace" is fake — High
`telemetry_processor.dart:182-214` (`computeTimeDelta`) interpolates linearly between the two laps' total times — the output is a straight line from 0 to (lap2 − lap1) by construction. It uses no positional data. With trace v2, compute delta-by-distance properly.

Also: no live speed is displayed anywhere on the recording screen (`recording_screen.dart`) — table stakes for a track app — and the Speed charts hardcode km/h, ignoring the imperial units setting (`lap_detail_screen.dart:368`, `lap_comparison_screen.dart:418`).

---

## 2. Recording pipeline (reviewed line-by-line)

### R1. Automatic lap detection is never armed — Critical
`RecordingRepository.setStartFinishLine` (`recording_repository.dart:184`) and `LapDetectionService` have **zero callers** in UI/controllers. `_sfLat1` stays null, `processPoint` always returns null. The flagship feature — pure-geometry start/finish detection — is dead code. There is no circuit-selection flow: `recording_controller.dart:43` calls `startSession(userId: user.id)` with no `circuitId`/`carId`, and the session edit screen only sets a free-text `circuitName` (`session_edit_screen.dart:207-213`), never `circuitId`. The Supabase `circuits` table with `GEOMETRY(LINESTRING)` start/finish lines and a GIST index (`initial_schema.sql:26-36`) is fully built and entirely unwired.

**Fix:** circuit picker (or GPS-based auto-detect of nearest circuit) at session start → load `start_finish_line` → call `setStartFinishLine`. Seed a circuits database.

### R2. Final partial lap is recorded as a real lap and can be flagged a PB — Critical
`stopSession` (`recording_repository.dart:200-202`) calls `_completeLap(DateTime.now())` on the in-progress lap. A partial in-lap is shorter than any real lap, so it sets `_bestLapMs` and is written with `isPersonalBest: true`, corrupting session bests, circuit PBs, and (eventually) leaderboards. **Fix:** store the final partial as an in-lap (flagged, excluded from PB/best logic) or discard it.

### R3. Lap-boundary race loses GPS points and mis-splits traces — High
`_onGpsPoint` (`recording_repository.dart:245-253`) fire-and-forgets `_completeLap`, which `clear()`s `_currentLapPoints` only after several awaited DB writes — points arriving during the awaits are appended then destroyed (they belonged to the next lap). The trace also isn't split at the interpolated crossing point. **Fix:** synchronously swap the point-list at crossing time before any await; split the crossing segment between the two laps.

### R4. First "lap" includes the out-lap — Medium
Lap 1 is timed from session start, not from the first line crossing (`_lapStart = _sessionStart`, `recording_repository.dart:138`). Convention is: first crossing arms lap 1.

### R5. No crash/interruption recovery — High
If the app is killed mid-session, the `LocalSessions` row (null `endedAt`) and completed laps exist locally but the session is never finalized or enqueued — no recovery path on next launch. For a recording app this is a data-loss bug users will hit. **Fix:** on startup, detect open sessions and offer to finalize them.

### R6. Sensors stop in background / screen lock — High
No wakelock dependency exists, and CoreMotion accelerometer/gyro streams (sensors_plus) do not deliver in background even with the location background mode active. If the screen locks mid-session, GPS continues but telemetry silently goes flat. **Fix:** add `wakelock_plus` during recording at minimum; document the limitation.

### R7. Weather fetch is one 2-second shot — Low
`_fetchWeather` (`recording_repository.dart:369-381`) waits 2s for a GPS fix and gives up forever if there isn't one. Retry once a fix arrives.

### R8. Unbounded in-memory growth & UI churn — Medium
`_allPoints` grows unbounded and a 100ms timer re-emits the full list to the UI (`recording_repository.dart:168-171`); sensor JSON for a 2-minute lap is ~6,000 samples × 9 channels stored as JSON text in SQLite and mirrored into sync payloads. Fine for v1 scale; needs decimation/binary encoding for v2.

### Lap detection service itself (`lap_detection_service.dart`) — Good
The geometry is correct where it matters: segment-intersection detection is affine-invariant so degree-space math is fine; crossing-time interpolation is proper; debounce + move-away hysteresis are sensible. Minor: `distanceToLineSegment` projects in anisotropic degree space (approximate but adequate at 15m tolerance); `_computeHeading` (`sensor_service.dart:191-194`) is not tilt-compensated.

---

## 3. Sectors — feature cannot work today

### S1. Sector times can never be computed from app-recorded laps — Critical
`sector_repository.dart:344-367` parses traces expecting `[lng,lat,timestamp]`; app traces have no timestamps (§1b), so every point gets `t=0` and the guard `endCrossing.timestamp <= startCrossing.timestamp` (`sector_repository.dart:271`) rejects every lap. **No sector time has ever been computable from real recorded data.** Blocked on trace format v2.

### S2. Retroactive scoring matches zero sessions — Critical
`persistSectorTimesForCircuit` selects sessions `WHERE circuitId = sector.circuitId` (`sector_repository.dart:305-307`), but sessions never get a `circuitId` (§R1). Even with timestamps fixed, scoring finds nothing.

### S3. Sector times are never synced; leaderboards are single-player — Critical
No `enqueueSync('sector_times', ...)` exists anywhere, and `getSectorLeaderboard` (`sector_repository.dart:158-221`) reads only local Drift. The remote `sector_times` table and its public-leaderboard RLS policy are dead infrastructure. The sync engine is push-only — there is no pull direction at all — so other users' sectors/times could never appear regardless.

### S4. Gate geometry is wrong — High
`_findLineCrossing` (`sector_repository.dart:371-397`) builds gates as fixed **east-west** segments, not perpendicular to the track: east-west track sections miss crossings; `0.0002°` longitude is ~12m at UK latitudes, not the claimed 20m; a wide gate can intersect a different part of the circuit; and the end-gate is searched from index 0, so an end-crossing earlier in the trace voids the whole lap instead of searching after the start crossing. **Fix:** orient gates perpendicular to local trace heading, scale by `cos(lat)`, search end-crossing after the start index.

### S5. New laps are never scored against existing sectors — High
Scoring runs only at sector creation (`sector_from_lap_screen.dart:201`) — and not even then for the coordinate-entry flow (`sector_creation_screen.dart:318-332` never calls it). Leaderboards freeze at creation time. **Fix:** score new laps in the recording pipeline post-session; move the persist call inside `createSector`.

### S6. Sector defs don't sync; deletes silently no-op — High
Insert payloads send `start_point_json`/`end_point_json` but remote columns are `GEOMETRY(POINT)` (`sector_repository.dart:118-126` vs `initial_schema.sql:86-95`) → every insert dies. `sectors` has no UPDATE/DELETE RLS policy, so the enqueued delete affects 0 rows and is marked completed — silent divergence.

Also: car-class leaderboard filter drops drivers instead of re-ranking (best-per-user selected before class filter, `sector_repository.dart:170-203`); duplicate (sectorId, lapId) rows would crash the scoring pass's `getSingleOrNull` (`:315-318`).

---

## 4. Sync engine & schema — broken end-to-end

The engine's shape is good (append-only queue, backoff, image interception, composite-PK awareness, lifecycle/connectivity triggers). The execution has one systemic gap: **client payloads and the remote schema were never tested against each other.**

| # | Sev | Finding | Where |
|---|-----|---------|-------|
| D1 | Critical | Lap payloads send `trace_json`; remote `laps` has `trace GEOMETRY` — every lap insert rejected (PGRST204), dead after 5 retries, never re-enqueued | `recording_repository.dart:313` vs `initial_schema.sql:58-66` |
| D2 | Critical | Sensor sync triply broken: wrong column names (`accel_x_json` vs `accel_x REAL[]`), non-UUID ids (`${lapId}_sensors`, `_chunk_$i`), phantom `chunk_index/chunk_total/parent_id` columns that exist in no migration | `recording_repository.dart:318-339`, `sync_service.dart:375-436` |
| D3 | Critical | Laps enqueued during recording, session row only at stop → FIFO + RLS guarantees FK failures; laps from early in a long session exhaust retries before the session row exists | `recording_repository.dart:303` vs `:214` |
| D4 | Critical | Dead-letter items invisible & unrecoverable: retry-exhausted rows are hidden from every query, never surfaced, never purged; settings shows "0 pending" while the graveyard grows. Local write + enqueue are not transactional | `app_database.dart:116-146`, `sync_service.dart:210-222` |
| D5 | High | Session edits never sync: payload includes `circuit_name`, column doesn't exist remotely. Includes the **privacy toggle** — user sets private locally, remote stays public | `session_repository.dart:129`, no migration adds it |
| D6 | High | Unfollow never syncs: `follows` (composite PK) missing from `compositePkTables` → delete targets nonexistent `id` column | `sync_service.dart:341-345` |
| D7 | High | `update` mapped to `upsert(partial payload)` violates NOT NULL on cars (missing `user_id/make/model`) — car edits never land | `sync_service.dart:336-337`, `car_repository.dart:159-169` |
| D8 | Medium | Queue ordering ties: Drift stores DateTime at second precision; same-second parent/child order unspecified. Tiebreak on autoincrement id | `app_database.dart:122` |
| D9 | Medium | `sessions.car_id` FK has no `ON DELETE` → deleting a referenced car fails remotely, car resurrects cross-device | `initial_schema.sql:42` |
| D10 | Medium | `weather_json` double-encoding: insert sends object, update sends string → two shapes in the same JSONB column | `session_repository.dart:138` vs `recording_repository.dart:225` |
| D11 | Medium | `updateSession` nulls unspecified fields (`Value(x)` instead of `Value.absent()`); same pattern risk in `updateProfile` | `session_repository.dart:101-115` |
| D12 | Medium | Missing remote indexes: `sessions(user_id)`, `cars(user_id)`, `sector_times(sector_id/lap_id)`, `session_comments(session_id)`, `follows(following_id)`, `team_members(user_id)` — RLS policies run correlated subqueries on these | migrations |
| D13 | Low | `pendingCount` capped at batch size 50; `profiles` lacks INSERT RLS policy; unique-constraint collisions (handle, team code, re-request) burn retries with no UX | various |

**No reconciliation path exists** for historical data: even after fixing the schema, already-dead-lettered laps/sessions need a sweep that re-enqueues local rows missing remotely.

---

## 5. Social: teams, feed, follows

| # | Sev | Finding | Where |
|---|-----|---------|-------|
| T1 | Critical | Team creation impossible: v2 migration replaced `teams_own` with `teams_admin FOR ALL USING (admin-membership-exists)` — circular with the FK (membership can't precede team). Every team since the migration is device-local | `20260304_team_system_v2.sql:75-93`, `team_repository.dart:262-284` |
| T2 | Critical | `team_members_admin` policy subqueries `team_members` itself → Postgres 42P17 "infinite recursion" on essentially every team_members query, including ones joined by other policies. Needs a `SECURITY DEFINER is_team_admin()` helper | `20260304_team_system_v2.sql:91-93` |
| T3 | Critical | Join-request approval only works for requests created on the admin's own phone: `approveJoinRequest` looks up the request in *local* Drift and throws when absent (the normal cross-device case); reject path skips the admin check and enqueues a partial upsert that fails NOT NULL | `team_repository.dart:759-891` |
| T4 | High | Member lists/counts read only local Drift with no pull sync → a team joined by code shows 1 member (you), forever | `team_repository.dart:119-224`, `crew_repository.dart:114-199` |
| T5 | High | Admin removing a member can't remove their crew memberships server-side (only `crew_members_self` policy exists) | `team_repository.dart:482-521`, `20260304_team_system_v2.sql:70` |
| T6 | High | All feed methods `catch (_) { return []; }` → network/RLS/schema failures render as "No sessions yet" with go-follow-people copy; the error UI branch is dead code | `feed_repository.dart:157-253` |
| T7 | Medium | No feed pagination (hardcoded limit 20, no load-more); like/comment counts fetched by embedding full rows instead of count aggregates | `feed_providers.dart:12-17`, `feed_repository.dart:95` |
| T8 | Medium | Like state split-brain: local optimistic writes vs server-only reads; feed invalidation races the sync queue; cold start shows your likes as un-liked and re-tap double-inserts | `like_repository.dart`, `feed_screen.dart:288-315` |
| T9 | Medium | PostgREST filter injection in search (`,`/`(`/`.` in query breaks `.or(...)` grammar → silently empty results); search has no debounce or response sequencing | `team_repository.dart:633`, `follow_repository.dart:97`, `following_screen.dart:34-63` |
| T10 | Low | "Nearby" feed is just all public sessions globally; `deleteComment` has no ownership check and no caller; crew name validation missing (teams has it) | `feed_repository.dart:163-194` etc. |

**Duplication:** `team_repository` and `crew_repository` share ~150 lines of near-identical join-by-code/member-hydration/count logic; the three feed methods repeat the same query block; `SectorRepository` is constructed ad hoc in six widgets despite a provider existing; every repo hand-builds snake_case sync payloads (a typed `enqueue(table, op, model)` helper would eliminate the T3/D7 class of bugs).

---

## 6. App shell, auth, iOS

| # | Sev | Finding | Where |
|---|-----|---------|-------|
| A1 | Critical | **No account deletion** — App Store Guideline 5.1.1(v) rejection risk; the app's own Terms (`assets/legal/terms.md:46`) and Privacy Policy promise it. Needs an Edge Function (`auth.admin.deleteUser` + cascade) + local wipe | `settings_screen.dart:69-80` |
| A2 | Critical | Entire GoRouter recreated on auth churn: `tokenRefreshed` (~hourly) → new `User` instance (no value equality) → disclaimer provider re-fetches through `AsyncLoading` (treated as "not accepted") → redirect to `/disclaimer`, then new router resets nav to `/record`. **Can yank a user out of a live recording.** Build the router once; use `refreshListenable`; select on `user?.id`; no-op redirect while loading | `app_router.dart:40-71`, `supabase_provider.dart:10-21` |
| A3 | High | Sign-out leaves previous user's Drift DB, sync queue, and prefs on device; user A's pending queue items get pushed under user B's JWT (engine checks only that *a* session exists), failing RLS and polluting the queue | `auth_repository.dart:129-137`, `sync_service.dart:154-203` |
| A4 | High | Password reset implemented but unreachable — no "Forgot password?" UI anywhere; email users can be locked out permanently | `auth_controller.dart:110-113`, `login_screen.dart:161-275` |
| A5 | High | Email sign-up with confirmation enabled strands users silently (null session treated as success; no "check your email" state) | `auth_controller.dart:90-107` |
| A6 | Medium | Apple full name requested but never persisted — unrecoverable after first sign-in; Hide-My-Email users get handles like `xkq7m2ab9c` | `auth_repository.dart:48-54`, `ensure_local_profile.dart:14-17` |
| A7 | Medium | Sign-in cancellation rendered as a raw red exception string | `auth_repository.dart:79-82`, `login_screen.dart:297-300` |
| A8 | Medium | "Remove photo" can't work: profile sync omits null `avatar_url`; `updateCar` coalesces every field with existing values so clearing anything is ignored | `profile_repository.dart:45-48`, `car_repository.dart:145-154` |
| A9 | Medium | Zero form validation on profile (empty name, unconstrained handle → remote unique violation dies silently in queue) and car form (no numeric validators) | `edit_profile_screen.dart:118-139`, `car_form_screen.dart:591-593` |
| A10 | Medium | Disclaimer/auth redirects treat loading and error as "not accepted" → startup flashes; a DB error traps the user on the disclaimer screen | `app_router.dart:63-71` |
| A11 | Medium | Dependency debt: `google_sign_in` 6.x (deprecated API line; v7 is a breaking rewrite), `lucide_icons` abandoned (successor `lucide_icons_flutter`), `go_router` ~2 majors behind. CLAUDE.md claims Riverpod code-gen; plain Riverpod 2.x is used | `pubspec.yaml` |
| A12 | Low | Apple nonce charset missing `W` (63-char alphabet); hand-built JSON in disclaimer payload; `existsSync()` in build paths; missing `ITSAppUsesNonExemptEncryption`; portrait lock vs landscape plist entries; **branding split: code says LapTime, every user-facing string says "TestTrack"** | various |

Positives: no hardcoded secrets (env-based), correct nonce-hashed Apple sign-in, all iOS permission strings present and specific, `UIBackgroundModes: location` declared, controllers disposed consistently.

---

## 7. Testing & tooling

- `test/` contains only the default `widget_test.dart`. **Effectively zero test coverage** for an app with geometry math, a sync state machine, and RLS-coupled payloads.
- Highest-leverage tests, in order: (1) schema-parity test that diffs every sync payload builder against the SQL migrations; (2) queue-drain integration test against a Supabase branch (would have caught D1-D7, T1-T3 wholesale); (3) unit tests for `GeoUtils` intersection/interpolation and sector gate crossing; (4) lap-detection replay tests from recorded traces.

---

## 8. Recommended v2 roadmap

**Phase 0 — stop the bleeding (small, do first)**
- Fix RLS: `teams_create WITH CHECK`, `SECURITY DEFINER is_team_admin()`, sectors UPDATE/DELETE policies, crew_members admin policy, profiles INSERT policy (T1, T2, H4/S6, T5).
- Schema alignment migration: `sessions.circuit_name`, lap trace column (JSONB), sensor columns/chunk columns, `follows` in `compositePkTables`, real `update()` for updates, `ON DELETE SET NULL` for `sessions.car_id`, missing indexes (D1-D7, D9, D12).
- Account deletion flow (A1). Sign-out local wipe (A3). Forgot-password link + email-confirmation state (A4, A5).
- Router: build once + `refreshListenable` (A2).
- Don't PB the final partial lap (R2).

**Phase 1 — make the core product real**
- **Trace format v2**: `[lng, lat, t_ms, speed_mps]` (+ alt/accuracy). Migrate readers (`parseTraceJson`, `_parseTrace`). This unblocks speed, sectors, and comparison in one move (1b, S1).
- **Speed**: GPS speed as the primary channel; `userAccelerometerEventStream` for G-channels; mount calibration; live speed on the recording screen; respect units setting (1a, 1c).
- **Circuits**: seed a circuit DB; circuit picker / GPS auto-detect at session start; arm `setStartFinishLine`; persist `circuit_id` (R1, S2).
- **Sync hardening**: enqueue session at start (not stop); dependency-aware or recording-paused queue; dead-letter surfaced in Settings with manual retry; transactional write+enqueue; reconciliation sweep to re-upload historical local data (D3, D4).
- Lap-boundary trace split + crash recovery + wakelock (R3, R5, R6).

**Phase 2 — make social/sectors multiplayer**
- Add a **pull-sync direction** (or remote-first reads with local cache) for teams/members, sectors, sector_times, follows (T4, S3).
- Fix sector gates (perpendicular, cos-lat scaling, end-after-start search) and score new laps automatically (S4, S5). Enqueue sector_times.
- Cross-device join-request approval via remote fetch (T3). Feed pagination + count aggregates + typed errors instead of `catch (_)` (T6, T7). Like-state merge (T8).

**Phase 3 — quality & debt**
- Test suite per §7. Repository dedup (membership base class, typed enqueue helper). Dependency migrations (google_sign_in 7, lucide_icons_flutter, go_router). Form validation. Apple name capture. Branding sweep (LapTime vs TestTrack). Telemetry storage decimation.

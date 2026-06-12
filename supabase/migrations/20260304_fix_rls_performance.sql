-- Fix RLS performance issues flagged by Supabase linter:
--   1. auth_rls_initplan: wrap auth.uid() in (select auth.uid()) to avoid per-row re-evaluation
--   2. multiple_permissive_policies: drop dashboard-created duplicates + split FOR ALL policies
--      where they overlap with separate SELECT policies
--
-- Strategy: for each table, drop ALL existing policies, then recreate them cleanly.
-- This is safer than trying to ALTER individual policies (which PostgreSQL doesn't support).

BEGIN;

-- ══════════════════════════════════════════════════════════════
-- PROFILES
-- ══════════════════════════════════════════════════════════════
-- Migration-created: profiles_read (SELECT, true), profiles_update (UPDATE, uid=id)
-- Dashboard-created: "Users can view all profiles", "Users can update own profile"

DROP POLICY IF EXISTS profiles_read ON public.profiles;
DROP POLICY IF EXISTS profiles_update ON public.profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

CREATE POLICY profiles_read ON public.profiles
  FOR SELECT USING (true);

CREATE POLICY profiles_update ON public.profiles
  FOR UPDATE USING ((select auth.uid()) = id);

-- ══════════════════════════════════════════════════════════════
-- CARS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: cars_all (ALL, uid=user_id)
-- Dashboard-created: "Users can view own cars", "Users can insert own cars",
--                    "Users can update own cars", "Users can delete own cars"

DROP POLICY IF EXISTS cars_all ON public.cars;
DROP POLICY IF EXISTS "Users can view own cars" ON public.cars;
DROP POLICY IF EXISTS "Users can insert own cars" ON public.cars;
DROP POLICY IF EXISTS "Users can update own cars" ON public.cars;
DROP POLICY IF EXISTS "Users can delete own cars" ON public.cars;

CREATE POLICY cars_all ON public.cars
  FOR ALL USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- SESSIONS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: sessions_own (ALL, uid=user_id), sessions_public_read (SELECT, is_public)
-- Dashboard-created: "Users can view own sessions", "Users can insert own sessions",
--                    "Users can update own sessions", "Users can delete own sessions",
--                    "Users can view public sessions"
-- Fix: sessions_own FOR ALL overlaps with sessions_public_read for SELECT.
--      Split into: combined SELECT + separate INSERT/UPDATE/DELETE.

DROP POLICY IF EXISTS sessions_own ON public.sessions;
DROP POLICY IF EXISTS sessions_public_read ON public.sessions;
DROP POLICY IF EXISTS "Users can view own sessions" ON public.sessions;
DROP POLICY IF EXISTS "Users can insert own sessions" ON public.sessions;
DROP POLICY IF EXISTS "Users can update own sessions" ON public.sessions;
DROP POLICY IF EXISTS "Users can delete own sessions" ON public.sessions;
DROP POLICY IF EXISTS "Users can view public sessions" ON public.sessions;

CREATE POLICY sessions_select ON public.sessions
  FOR SELECT USING ((select auth.uid()) = user_id OR is_public = true);

CREATE POLICY sessions_insert ON public.sessions
  FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY sessions_update ON public.sessions
  FOR UPDATE USING ((select auth.uid()) = user_id);

CREATE POLICY sessions_delete ON public.sessions
  FOR DELETE USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- LAPS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: laps_own (ALL, EXISTS own session), laps_public_read (SELECT, EXISTS public)
-- Dashboard-created: "Users can view laps of accessible sessions",
--                    "Users can insert laps to own sessions",
--                    "Users can update laps in own sessions"
-- Fix: laps_own FOR ALL overlaps with laps_public_read for SELECT.

DROP POLICY IF EXISTS laps_own ON public.laps;
DROP POLICY IF EXISTS laps_public_read ON public.laps;
DROP POLICY IF EXISTS "Users can view laps of accessible sessions" ON public.laps;
DROP POLICY IF EXISTS "Users can insert laps to own sessions" ON public.laps;
DROP POLICY IF EXISTS "Users can update laps in own sessions" ON public.laps;

CREATE POLICY laps_select ON public.laps
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id
        AND (s.user_id = (select auth.uid()) OR s.is_public = true)
    )
  );

CREATE POLICY laps_insert ON public.laps
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND s.user_id = (select auth.uid())
    )
  );

CREATE POLICY laps_update ON public.laps
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND s.user_id = (select auth.uid())
    )
  );

CREATE POLICY laps_delete ON public.laps
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND s.user_id = (select auth.uid())
    )
  );

-- ══════════════════════════════════════════════════════════════
-- LAP_SENSOR_DATA
-- ══════════════════════════════════════════════════════════════
-- Migration-created: sensor_own (ALL, EXISTS via laps+sessions)
-- Dashboard-created: "Users can view own sensor data", "Users can insert own sensor data"
-- No overlap (single FOR ALL), just fix auth.uid() and drop duplicates.

DROP POLICY IF EXISTS sensor_own ON public.lap_sensor_data;
DROP POLICY IF EXISTS "Users can view own sensor data" ON public.lap_sensor_data;
DROP POLICY IF EXISTS "Users can insert own sensor data" ON public.lap_sensor_data;

CREATE POLICY sensor_own ON public.lap_sensor_data
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.laps l
      JOIN public.sessions s ON s.id = l.session_id
      WHERE l.id = lap_id AND s.user_id = (select auth.uid())
    )
  );

-- ══════════════════════════════════════════════════════════════
-- SECTORS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: sectors_read (SELECT, true), sectors_insert (INSERT, uid=created_by)
-- Dashboard-created: "Anyone can view sectors", "Users can create sectors",
--                    "Users can delete own sectors"
-- No FOR ALL overlap, just fix auth.uid() and drop duplicates.

DROP POLICY IF EXISTS sectors_read ON public.sectors;
DROP POLICY IF EXISTS sectors_insert ON public.sectors;
DROP POLICY IF EXISTS "Anyone can view sectors" ON public.sectors;
DROP POLICY IF EXISTS "Users can create sectors" ON public.sectors;
DROP POLICY IF EXISTS "Users can delete own sectors" ON public.sectors;

CREATE POLICY sectors_read ON public.sectors
  FOR SELECT USING (true);

CREATE POLICY sectors_insert ON public.sectors
  FOR INSERT WITH CHECK ((select auth.uid()) = created_by);

CREATE POLICY sectors_delete ON public.sectors
  FOR DELETE USING ((select auth.uid()) = created_by);

-- ══════════════════════════════════════════════════════════════
-- SECTOR_TIMES
-- ══════════════════════════════════════════════════════════════
-- Migration-created: sector_times_read (SELECT, true), sector_times_own (ALL, uid=user_id)
-- Dashboard-created: "Anyone can view sector times", "Users can insert own sector times"
-- Fix: sector_times_own FOR ALL overlaps with sector_times_read for SELECT.

DROP POLICY IF EXISTS sector_times_read ON public.sector_times;
DROP POLICY IF EXISTS sector_times_own ON public.sector_times;
DROP POLICY IF EXISTS "Anyone can view sector times" ON public.sector_times;
DROP POLICY IF EXISTS "Users can insert own sector times" ON public.sector_times;

CREATE POLICY sector_times_select ON public.sector_times
  FOR SELECT USING (true);

CREATE POLICY sector_times_insert ON public.sector_times
  FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY sector_times_update ON public.sector_times
  FOR UPDATE USING ((select auth.uid()) = user_id);

CREATE POLICY sector_times_delete ON public.sector_times
  FOR DELETE USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- FOLLOWS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: follows_own (ALL, uid=follower_id), follows_read (SELECT, true)
-- Dashboard-created: "Anyone can view follows", "Users can follow", "Users can unfollow"
-- Fix: follows_own FOR ALL overlaps with follows_read for SELECT.

DROP POLICY IF EXISTS follows_own ON public.follows;
DROP POLICY IF EXISTS follows_read ON public.follows;
DROP POLICY IF EXISTS "Anyone can view follows" ON public.follows;
DROP POLICY IF EXISTS "Users can follow" ON public.follows;
DROP POLICY IF EXISTS "Users can unfollow" ON public.follows;

CREATE POLICY follows_select ON public.follows
  FOR SELECT USING (true);

CREATE POLICY follows_insert ON public.follows
  FOR INSERT WITH CHECK ((select auth.uid()) = follower_id);

CREATE POLICY follows_delete ON public.follows
  FOR DELETE USING ((select auth.uid()) = follower_id);

-- ══════════════════════════════════════════════════════════════
-- TEAMS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: teams_read (SELECT, true), teams_admin (ALL, EXISTS admin check)
-- Dashboard-created: "Anyone can view teams", "Users can create teams"
-- Fix: teams_admin FOR ALL overlaps with teams_read for SELECT.

DROP POLICY IF EXISTS teams_read ON public.teams;
DROP POLICY IF EXISTS teams_admin ON public.teams;
DROP POLICY IF EXISTS "Anyone can view teams" ON public.teams;
DROP POLICY IF EXISTS "Users can create teams" ON public.teams;

CREATE POLICY teams_select ON public.teams
  FOR SELECT USING (true);

-- Any authenticated user can create a team
CREATE POLICY teams_insert ON public.teams
  FOR INSERT WITH CHECK ((select auth.uid()) IS NOT NULL);

-- Only admins can update/delete teams
CREATE POLICY teams_update ON public.teams
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = teams.id AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

CREATE POLICY teams_delete ON public.teams
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = teams.id AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

-- ══════════════════════════════════════════════════════════════
-- TEAM_MEMBERS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: team_members_read (SELECT, true),
--   team_members_self_insert (INSERT, uid=user_id),
--   team_members_self_delete (DELETE, uid=user_id),
--   team_members_admin (ALL, EXISTS admin check)
-- Dashboard-created: "Anyone can view team members", "Users can join teams", "Users can leave teams"
-- Fix: team_members_admin FOR ALL overlaps with team_members_read for SELECT,
--       and with self_insert/self_delete for INSERT/DELETE.

DROP POLICY IF EXISTS team_members_read ON public.team_members;
DROP POLICY IF EXISTS team_members_self_insert ON public.team_members;
DROP POLICY IF EXISTS team_members_self_delete ON public.team_members;
DROP POLICY IF EXISTS team_members_admin ON public.team_members;
DROP POLICY IF EXISTS "Anyone can view team members" ON public.team_members;
DROP POLICY IF EXISTS "Users can join teams" ON public.team_members;
DROP POLICY IF EXISTS "Users can leave teams" ON public.team_members;

CREATE POLICY team_members_select ON public.team_members
  FOR SELECT USING (true);

-- Users can add themselves, admins can add anyone
CREATE POLICY team_members_insert ON public.team_members
  FOR INSERT WITH CHECK (
    (select auth.uid()) = user_id
    OR EXISTS (
      SELECT 1 FROM public.team_members tm2
      WHERE tm2.team_id = team_members.team_id
        AND tm2.user_id = (select auth.uid()) AND tm2.role = 'admin'
    )
  );

-- Admins can update roles
CREATE POLICY team_members_update ON public.team_members
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.team_members tm2
      WHERE tm2.team_id = team_members.team_id
        AND tm2.user_id = (select auth.uid()) AND tm2.role = 'admin'
    )
  );

-- Users can remove themselves, admins can remove anyone
CREATE POLICY team_members_delete ON public.team_members
  FOR DELETE USING (
    (select auth.uid()) = user_id
    OR EXISTS (
      SELECT 1 FROM public.team_members tm2
      WHERE tm2.team_id = team_members.team_id
        AND tm2.user_id = (select auth.uid()) AND tm2.role = 'admin'
    )
  );

-- ══════════════════════════════════════════════════════════════
-- DISCLAIMER_ACCEPTANCES
-- ══════════════════════════════════════════════════════════════
-- Migration-created: disclaimer_own (ALL, uid=user_id)
-- Dashboard-created: "Users can view own acceptances", "Users can insert own acceptances"
-- No overlap, just fix auth.uid() and drop duplicates.

DROP POLICY IF EXISTS disclaimer_own ON public.disclaimer_acceptances;
DROP POLICY IF EXISTS "Users can view own acceptances" ON public.disclaimer_acceptances;
DROP POLICY IF EXISTS "Users can insert own acceptances" ON public.disclaimer_acceptances;

CREATE POLICY disclaimer_own ON public.disclaimer_acceptances
  FOR ALL USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- SESSION_LIKES
-- ══════════════════════════════════════════════════════════════
-- Migration-created: "Anyone can read likes" (SELECT, true),
--                    "Users manage own likes" (ALL, uid=user_id)
-- Fix: FOR ALL overlaps with SELECT.

DROP POLICY IF EXISTS "Anyone can read likes" ON public.session_likes;
DROP POLICY IF EXISTS "Users manage own likes" ON public.session_likes;

CREATE POLICY session_likes_select ON public.session_likes
  FOR SELECT USING (true);

CREATE POLICY session_likes_insert ON public.session_likes
  FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY session_likes_delete ON public.session_likes
  FOR DELETE USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- SESSION_COMMENTS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: "Anyone can read comments" (SELECT, true),
--                    "Users manage own comments" (ALL, uid=user_id)
-- Fix: FOR ALL overlaps with SELECT.

DROP POLICY IF EXISTS "Anyone can read comments" ON public.session_comments;
DROP POLICY IF EXISTS "Users manage own comments" ON public.session_comments;

CREATE POLICY session_comments_select ON public.session_comments
  FOR SELECT USING (true);

CREATE POLICY session_comments_insert ON public.session_comments
  FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY session_comments_update ON public.session_comments
  FOR UPDATE USING ((select auth.uid()) = user_id);

CREATE POLICY session_comments_delete ON public.session_comments
  FOR DELETE USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- CREWS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: crews_read (SELECT, EXISTS team member), crews_admin (ALL, EXISTS admin)
-- Fix: crews_admin FOR ALL overlaps with crews_read for SELECT.

DROP POLICY IF EXISTS crews_read ON public.crews;
DROP POLICY IF EXISTS crews_admin ON public.crews;

CREATE POLICY crews_select ON public.crews
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = crews.team_id AND tm.user_id = (select auth.uid())
    )
  );

CREATE POLICY crews_insert ON public.crews
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = crews.team_id
        AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

CREATE POLICY crews_update ON public.crews
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = crews.team_id
        AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

CREATE POLICY crews_delete ON public.crews
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = crews.team_id
        AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

-- ══════════════════════════════════════════════════════════════
-- CREW_MEMBERS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: crew_members_read (SELECT, EXISTS via crew+team), crew_members_self (ALL, uid=user_id)
-- Fix: crew_members_self FOR ALL overlaps with crew_members_read for SELECT.

DROP POLICY IF EXISTS crew_members_read ON public.crew_members;
DROP POLICY IF EXISTS crew_members_self ON public.crew_members;

CREATE POLICY crew_members_select ON public.crew_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.crews c
      JOIN public.team_members tm ON tm.team_id = c.team_id
      WHERE c.id = crew_members.crew_id AND tm.user_id = (select auth.uid())
    )
  );

CREATE POLICY crew_members_insert ON public.crew_members
  FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY crew_members_update ON public.crew_members
  FOR UPDATE USING ((select auth.uid()) = user_id);

CREATE POLICY crew_members_delete ON public.crew_members
  FOR DELETE USING ((select auth.uid()) = user_id);

-- ══════════════════════════════════════════════════════════════
-- TEAM_JOIN_REQUESTS
-- ══════════════════════════════════════════════════════════════
-- Migration-created: join_requests_own (ALL, uid=user_id),
--                    join_requests_admin (SELECT, EXISTS admin),
--                    join_requests_admin_update (UPDATE, EXISTS admin)
-- Fix: join_requests_own FOR ALL overlaps with join_requests_admin for SELECT,
--       and with join_requests_admin_update for UPDATE.

DROP POLICY IF EXISTS join_requests_own ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_admin ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_admin_update ON public.team_join_requests;

-- Combined SELECT: own requests OR admin of the team
CREATE POLICY join_requests_select ON public.team_join_requests
  FOR SELECT USING (
    (select auth.uid()) = user_id
    OR EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = team_join_requests.team_id
        AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

-- Users can create their own requests
CREATE POLICY join_requests_insert ON public.team_join_requests
  FOR INSERT WITH CHECK ((select auth.uid()) = user_id);

-- Combined UPDATE: own requests OR admin of the team
CREATE POLICY join_requests_update ON public.team_join_requests
  FOR UPDATE USING (
    (select auth.uid()) = user_id
    OR EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.team_id = team_join_requests.team_id
        AND tm.user_id = (select auth.uid()) AND tm.role = 'admin'
    )
  );

-- Users can delete (cancel) their own requests
CREATE POLICY join_requests_delete ON public.team_join_requests
  FOR DELETE USING ((select auth.uid()) = user_id);

COMMIT;

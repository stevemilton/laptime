-- V2 Schema Alignment & RLS Fixes
--
-- Fixes the systemic drift between the client's sync payloads and the remote
-- schema, hardens the RLS policy set, adds missing indexes, and introduces
-- server-side account deletion.
--
-- NOTE: the live database's policies had drifted from the committed
-- migration files (per-command policies were created via the SQL editor).
-- This migration reconciles against the LIVE state: it drops both the
-- repo-file policy names and the live policy names before recreating, so
-- it is idempotent and safe regardless of which state a database is in.
--
-- Findings reference: docs/V2_CODE_REVIEW.md (D1-D13, T1/T2/T5, S6, A1).

-- ════════════════════════════════════════════════════════════════════
-- 1. Column alignment with client sync payloads
-- ════════════════════════════════════════════════════════════════════

-- D1: laps are synced with a JSON trace (trace format v2:
-- [[lng, lat, t_ms, speed_mps], ...]). The PostGIS column stays for
-- future geo queries but the client writes JSONB. is_partial marks
-- incomplete laps (excluded from PBs and sector scoring).
ALTER TABLE public.laps
  ADD COLUMN IF NOT EXISTS trace_json JSONB,
  ADD COLUMN IF NOT EXISTS is_partial BOOLEAN DEFAULT false;

-- D5: session edits include the user-entered circuit name.
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS circuit_name TEXT;

-- D2: chunked sensor uploads reference a parent row. Chunk rows carry
-- real UUIDs; parent_id links them back to the logical record.
ALTER TABLE public.lap_sensor_data
  ADD COLUMN IF NOT EXISTS chunk_index INTEGER,
  ADD COLUMN IF NOT EXISTS chunk_total INTEGER,
  ADD COLUMN IF NOT EXISTS parent_id UUID;
-- NOT a partial index: the client upserts chunks with
-- ON CONFLICT (parent_id, chunk_index), and Postgres cannot infer a
-- partial unique index from a bare conflict target. NULL parent_ids
-- (whole rows) never conflict because NULLs are distinct.
CREATE UNIQUE INDEX IF NOT EXISTS lap_sensor_data_parent_chunk
  ON public.lap_sensor_data (parent_id, chunk_index);
-- Re-uploads of the same lap's sensor data must not duplicate rows.
CREATE UNIQUE INDEX IF NOT EXISTS lap_sensor_data_lap_whole
  ON public.lap_sensor_data (lap_id)
  WHERE parent_id IS NULL;

-- S6: sectors are synced with JSON points ({"lat": .., "lng": ..}).
ALTER TABLE public.sectors
  ADD COLUMN IF NOT EXISTS start_point_json JSONB,
  ADD COLUMN IF NOT EXISTS end_point_json JSONB,
  ADD COLUMN IF NOT EXISTS line_json JSONB;

-- Circuits: user-created circuits from the app. The start/finish line is
-- synced as JSON ([[lat, lng], [lat, lng]]) matching the local schema.
ALTER TABLE public.circuits
  ADD COLUMN IF NOT EXISTS start_finish_line_json JSONB,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- M4: one sector time per (sector, lap).
CREATE UNIQUE INDEX IF NOT EXISTS sector_times_sector_lap
  ON public.sector_times (sector_id, lap_id);

-- ════════════════════════════════════════════════════════════════════
-- 2. Foreign-key behaviour fixes
-- ════════════════════════════════════════════════════════════════════

-- D9: deleting a car must not strand sessions (car_id is nullable).
ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_car_id_fkey;
ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_car_id_fkey
  FOREIGN KEY (car_id) REFERENCES public.cars(id) ON DELETE SET NULL;

-- A1 (account deletion): every user-owned row must be deletable when the
-- auth user is removed. Cascade or detach the FKs that currently block it.
ALTER TABLE public.sectors
  DROP CONSTRAINT IF EXISTS sectors_created_by_fkey;
ALTER TABLE public.sectors
  ADD CONSTRAINT sectors_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.sector_times
  DROP CONSTRAINT IF EXISTS sector_times_user_id_fkey;
ALTER TABLE public.sector_times
  ADD CONSTRAINT sector_times_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.sector_times
  DROP CONSTRAINT IF EXISTS sector_times_session_id_fkey;
ALTER TABLE public.sector_times
  ADD CONSTRAINT sector_times_session_id_fkey
  FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;

ALTER TABLE public.disclaimer_acceptances
  DROP CONSTRAINT IF EXISTS disclaimer_acceptances_user_id_fkey;
ALTER TABLE public.disclaimer_acceptances
  ADD CONSTRAINT disclaimer_acceptances_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Teams outlive their creator.
ALTER TABLE public.teams
  ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE public.teams
  DROP CONSTRAINT IF EXISTS teams_created_by_fkey;
ALTER TABLE public.teams
  ADD CONSTRAINT teams_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ════════════════════════════════════════════════════════════════════
-- 3. RLS fixes
-- ════════════════════════════════════════════════════════════════════

-- T1/T2: policies that check team membership/adminship by subquerying
-- team_members are fragile on team_members itself (self-reference only
-- avoids infinite recursion while team_members' SELECT policy stays
-- `USING (true)`). SECURITY DEFINER helpers bypass RLS inside the check.
CREATE OR REPLACE FUNCTION public.is_team_admin(check_team_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.team_members tm
    WHERE tm.team_id = check_team_id
      AND tm.user_id = auth.uid()
      AND tm.role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_team_member(check_team_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.team_members tm
    WHERE tm.team_id = check_team_id
      AND tm.user_id = auth.uid()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_team_admin(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_team_member(UUID) FROM anon;

-- Teams: creators insert their own teams; admins update/delete.
DROP POLICY IF EXISTS teams_admin ON public.teams;
DROP POLICY IF EXISTS teams_insert ON public.teams;
DROP POLICY IF EXISTS teams_update ON public.teams;
DROP POLICY IF EXISTS teams_delete ON public.teams;
CREATE POLICY teams_insert ON public.teams
  FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY teams_update ON public.teams
  FOR UPDATE USING (public.is_team_admin(id));
CREATE POLICY teams_delete ON public.teams
  FOR DELETE USING (public.is_team_admin(id));

-- Team members: self can join/leave; admins manage all (this matches the
-- live semantics — the approve flow has an admin insert the requester's
-- membership row).
DROP POLICY IF EXISTS team_members_admin ON public.team_members;
DROP POLICY IF EXISTS team_members_insert ON public.team_members;
DROP POLICY IF EXISTS team_members_update ON public.team_members;
DROP POLICY IF EXISTS team_members_delete ON public.team_members;
CREATE POLICY team_members_insert ON public.team_members
  FOR INSERT WITH CHECK (
    auth.uid() = user_id OR public.is_team_admin(team_id)
  );
CREATE POLICY team_members_update ON public.team_members
  FOR UPDATE USING (public.is_team_admin(team_id));
CREATE POLICY team_members_delete ON public.team_members
  FOR DELETE USING (
    auth.uid() = user_id OR public.is_team_admin(team_id)
  );

-- Crews: members read, admins manage.
DROP POLICY IF EXISTS crews_read ON public.crews;
DROP POLICY IF EXISTS crews_admin ON public.crews;
DROP POLICY IF EXISTS crews_select ON public.crews;
DROP POLICY IF EXISTS crews_insert ON public.crews;
DROP POLICY IF EXISTS crews_update ON public.crews;
DROP POLICY IF EXISTS crews_delete ON public.crews;
CREATE POLICY crews_select ON public.crews
  FOR SELECT USING (public.is_team_member(team_id));
CREATE POLICY crews_insert ON public.crews
  FOR INSERT WITH CHECK (public.is_team_admin(team_id));
CREATE POLICY crews_update ON public.crews
  FOR UPDATE USING (public.is_team_admin(team_id));
CREATE POLICY crews_delete ON public.crews
  FOR DELETE USING (public.is_team_admin(team_id));

-- Crew members: self can join/leave; T5 — team admins must also be able
-- to remove other members' crew memberships.
DROP POLICY IF EXISTS crew_members_read ON public.crew_members;
DROP POLICY IF EXISTS crew_members_admin ON public.crew_members;
DROP POLICY IF EXISTS crew_members_self ON public.crew_members;
DROP POLICY IF EXISTS crew_members_select ON public.crew_members;
DROP POLICY IF EXISTS crew_members_insert ON public.crew_members;
DROP POLICY IF EXISTS crew_members_update ON public.crew_members;
DROP POLICY IF EXISTS crew_members_delete ON public.crew_members;
CREATE POLICY crew_members_select ON public.crew_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_member(c.team_id)
    )
  );
CREATE POLICY crew_members_insert ON public.crew_members
  FOR INSERT WITH CHECK (
    auth.uid() = user_id OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_admin(c.team_id)
    )
  );
CREATE POLICY crew_members_update ON public.crew_members
  FOR UPDATE USING (
    auth.uid() = user_id OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_admin(c.team_id)
    )
  );
CREATE POLICY crew_members_delete ON public.crew_members
  FOR DELETE USING (
    auth.uid() = user_id OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_admin(c.team_id)
    )
  );

-- Join requests: requesters manage their own; team admins review.
DROP POLICY IF EXISTS join_requests_own ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_admin ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_admin_update ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_select ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_insert ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_update ON public.team_join_requests;
DROP POLICY IF EXISTS join_requests_delete ON public.team_join_requests;
CREATE POLICY join_requests_select ON public.team_join_requests
  FOR SELECT USING (
    auth.uid() = user_id OR public.is_team_admin(team_id)
  );
CREATE POLICY join_requests_insert ON public.team_join_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY join_requests_update ON public.team_join_requests
  FOR UPDATE USING (
    auth.uid() = user_id OR public.is_team_admin(team_id)
  );
CREATE POLICY join_requests_delete ON public.team_join_requests
  FOR DELETE USING (auth.uid() = user_id);

-- Car make/model/class are shown on the public feed and sector
-- leaderboards; the owner-only policy made every embed return null.
DROP POLICY IF EXISTS cars_public_read ON public.cars;
CREATE POLICY cars_public_read ON public.cars FOR SELECT USING (true);

-- L2: allow the client's profile upsert path.
DROP POLICY IF EXISTS profiles_insert ON public.profiles;
CREATE POLICY profiles_insert ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update ON public.profiles
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- H4/S6: sector owners can update their sectors (delete already exists).
DROP POLICY IF EXISTS sectors_update ON public.sectors;
CREATE POLICY sectors_update ON public.sectors
  FOR UPDATE USING (auth.uid() = created_by);
DROP POLICY IF EXISTS sectors_delete ON public.sectors;
CREATE POLICY sectors_delete ON public.sectors
  FOR DELETE USING (auth.uid() = created_by);

-- Authenticated users can create circuits from the app.
DROP POLICY IF EXISTS circuits_insert ON public.circuits;
CREATE POLICY circuits_insert ON public.circuits
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = created_by);
DROP POLICY IF EXISTS circuits_update ON public.circuits;
CREATE POLICY circuits_update ON public.circuits
  FOR UPDATE USING (auth.uid() = created_by);

-- ════════════════════════════════════════════════════════════════════
-- 4. Missing indexes (D12)
-- ════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS sessions_user ON public.sessions(user_id);
CREATE INDEX IF NOT EXISTS sessions_circuit ON public.sessions(circuit_id);
CREATE INDEX IF NOT EXISTS sessions_public_started
  ON public.sessions(started_at DESC) WHERE is_public = true;
CREATE INDEX IF NOT EXISTS cars_user ON public.cars(user_id);
CREATE INDEX IF NOT EXISTS sector_times_sector ON public.sector_times(sector_id);
CREATE INDEX IF NOT EXISTS sector_times_lap ON public.sector_times(lap_id);
CREATE INDEX IF NOT EXISTS sector_times_user ON public.sector_times(user_id);
CREATE INDEX IF NOT EXISTS sectors_circuit ON public.sectors(circuit_id);
CREATE INDEX IF NOT EXISTS session_comments_session ON public.session_comments(session_id);
CREATE INDEX IF NOT EXISTS session_likes_session ON public.session_likes(session_id);
CREATE INDEX IF NOT EXISTS follows_following ON public.follows(following_id);
CREATE INDEX IF NOT EXISTS team_members_user ON public.team_members(user_id);
CREATE INDEX IF NOT EXISTS lap_sensor_data_lap ON public.lap_sensor_data(lap_id);
CREATE INDEX IF NOT EXISTS disclaimer_acceptances_user ON public.disclaimer_acceptances(user_id);

-- ════════════════════════════════════════════════════════════════════
-- 5. Account deletion (A1 — App Store Guideline 5.1.1(v))
-- ════════════════════════════════════════════════════════════════════

-- Deletes the calling user's auth record; profiles cascades from
-- auth.users, and all user data cascades (or detaches) from profiles
-- via the FK changes in section 2.
CREATE OR REPLACE FUNCTION public.delete_account()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_account() TO authenticated;

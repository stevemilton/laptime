-- V2 advisor hardening: fixes flagged by the Supabase security and
-- performance linters after the v2 schema alignment was applied.
--
-- Applied to production 2026-06-12 (migration: v2_advisor_hardening).
--
-- Remaining linter items, all intentional or platform-owned:
-- * delete_account / is_team_admin / is_team_member executable by
--   `authenticated` — by design (account deletion is a user feature;
--   the helpers are evaluated inside RLS policies as the querying role).
-- * spatial_ref_sys RLS disabled / postgis in public / st_estimatedextent —
--   PostGIS platform objects (the SRID catalogue holds no user data).
-- * Public bucket listing on avatars/car-images/team-logos — buckets are
--   deliberately public; tighten if asset privacy ever matters.

-- ── 1. Function grants: REVOKE FROM anon alone is insufficient because
-- EXECUTE flows through the default PUBLIC grant. ──

REVOKE EXECUTE ON FUNCTION public.delete_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_account() TO authenticated;

-- Policy expressions run as the querying role, so authenticated needs
-- EXECUTE on the helpers; nobody else does.
REVOKE EXECUTE ON FUNCTION public.is_team_admin(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_team_admin(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.is_team_member(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_team_member(UUID) TO authenticated;

-- The signup trigger runs as supabase_auth_admin; it must not be callable
-- through the REST RPC surface.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO supabase_auth_admin;

-- ── 2. auth_rls_initplan: wrap auth.uid() in (SELECT auth.uid()) so it is
-- evaluated once per statement instead of once per row. ──

DROP POLICY IF EXISTS teams_insert ON public.teams;
CREATE POLICY teams_insert ON public.teams
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = created_by);

DROP POLICY IF EXISTS team_members_insert ON public.team_members;
CREATE POLICY team_members_insert ON public.team_members
  FOR INSERT WITH CHECK (
    (SELECT auth.uid()) = user_id OR public.is_team_admin(team_id)
  );
DROP POLICY IF EXISTS team_members_delete ON public.team_members;
CREATE POLICY team_members_delete ON public.team_members
  FOR DELETE USING (
    (SELECT auth.uid()) = user_id OR public.is_team_admin(team_id)
  );

DROP POLICY IF EXISTS crew_members_insert ON public.crew_members;
CREATE POLICY crew_members_insert ON public.crew_members
  FOR INSERT WITH CHECK (
    (SELECT auth.uid()) = user_id OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_admin(c.team_id)
    )
  );
DROP POLICY IF EXISTS crew_members_update ON public.crew_members;
CREATE POLICY crew_members_update ON public.crew_members
  FOR UPDATE USING (
    (SELECT auth.uid()) = user_id OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_admin(c.team_id)
    )
  );
DROP POLICY IF EXISTS crew_members_delete ON public.crew_members;
CREATE POLICY crew_members_delete ON public.crew_members
  FOR DELETE USING (
    (SELECT auth.uid()) = user_id OR EXISTS (
      SELECT 1 FROM public.crews c
      WHERE c.id = crew_members.crew_id
        AND public.is_team_admin(c.team_id)
    )
  );

DROP POLICY IF EXISTS join_requests_select ON public.team_join_requests;
CREATE POLICY join_requests_select ON public.team_join_requests
  FOR SELECT USING (
    (SELECT auth.uid()) = user_id OR public.is_team_admin(team_id)
  );
DROP POLICY IF EXISTS join_requests_insert ON public.team_join_requests;
CREATE POLICY join_requests_insert ON public.team_join_requests
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS join_requests_update ON public.team_join_requests;
CREATE POLICY join_requests_update ON public.team_join_requests
  FOR UPDATE USING (
    (SELECT auth.uid()) = user_id OR public.is_team_admin(team_id)
  );
DROP POLICY IF EXISTS join_requests_delete ON public.team_join_requests;
CREATE POLICY join_requests_delete ON public.team_join_requests
  FOR DELETE USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS profiles_insert ON public.profiles;
CREATE POLICY profiles_insert ON public.profiles
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = id);
DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update ON public.profiles
  FOR UPDATE USING ((SELECT auth.uid()) = id)
  WITH CHECK ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS sectors_update ON public.sectors;
CREATE POLICY sectors_update ON public.sectors
  FOR UPDATE USING ((SELECT auth.uid()) = created_by);
DROP POLICY IF EXISTS sectors_delete ON public.sectors;
CREATE POLICY sectors_delete ON public.sectors
  FOR DELETE USING ((SELECT auth.uid()) = created_by);

DROP POLICY IF EXISTS circuits_insert ON public.circuits;
CREATE POLICY circuits_insert ON public.circuits
  FOR INSERT WITH CHECK (
    (SELECT auth.uid()) IS NOT NULL AND (SELECT auth.uid()) = created_by
  );
DROP POLICY IF EXISTS circuits_update ON public.circuits;
CREATE POLICY circuits_update ON public.circuits
  FOR UPDATE USING ((SELECT auth.uid()) = created_by);

-- ── 3. Cars: replace the owner FOR ALL policy + public read overlap with
-- one policy per command (no duplicate permissive SELECT policies). ──

DROP POLICY IF EXISTS cars_all ON public.cars;
DROP POLICY IF EXISTS cars_public_read ON public.cars;
DROP POLICY IF EXISTS cars_select ON public.cars;
DROP POLICY IF EXISTS cars_insert ON public.cars;
DROP POLICY IF EXISTS cars_update ON public.cars;
DROP POLICY IF EXISTS cars_delete ON public.cars;
CREATE POLICY cars_select ON public.cars FOR SELECT USING (true);
CREATE POLICY cars_insert ON public.cars
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY cars_update ON public.cars
  FOR UPDATE USING ((SELECT auth.uid()) = user_id);
CREATE POLICY cars_delete ON public.cars
  FOR DELETE USING ((SELECT auth.uid()) = user_id);

-- ── 4. Index hygiene: cover the new circuits FK; drop the hand-created
-- duplicates of the indexes the v2 migration (repo source of truth) added. ──

CREATE INDEX IF NOT EXISTS circuits_created_by ON public.circuits(created_by);

DROP INDEX IF EXISTS public.idx_cars_user_id;
DROP INDEX IF EXISTS public.idx_disclaimer_acceptances_user_id;
DROP INDEX IF EXISTS public.idx_follows_following_id;
DROP INDEX IF EXISTS public.idx_lap_sensor_data_lap_id;
DROP INDEX IF EXISTS public.idx_sector_times_lap_id;
DROP INDEX IF EXISTS public.idx_sector_times_sector_id;
DROP INDEX IF EXISTS public.idx_sector_times_user_id;
DROP INDEX IF EXISTS public.idx_sectors_circuit_id;
DROP INDEX IF EXISTS public.idx_session_comments_session_id;
DROP INDEX IF EXISTS public.idx_sessions_circuit_id;
DROP INDEX IF EXISTS public.idx_sessions_user_id;
DROP INDEX IF EXISTS public.idx_team_members_user_id;

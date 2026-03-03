-- Team System V2: Crews, Join Requests, Team Metadata
-- Replicates UTX Club/Squad architecture for race car teams

-- ── Expand teams table ──
ALTER TABLE public.teams
  ADD COLUMN IF NOT EXISTS location TEXT,
  ADD COLUMN IF NOT EXISTS logo_url TEXT,
  ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT false;

-- Migrate 'owner' role to 'admin'
UPDATE public.team_members SET role = 'admin' WHERE role = 'owner';

-- ── Crews (sub-groups within teams) ──
CREATE TABLE IF NOT EXISTS public.crews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  invite_code TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS crews_team_id ON public.crews(team_id);

-- ── Crew members ──
CREATE TABLE IF NOT EXISTS public.crew_members (
  crew_id UUID NOT NULL REFERENCES public.crews(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (crew_id, user_id)
);
CREATE INDEX IF NOT EXISTS crew_members_user ON public.crew_members(user_id);

-- ── Team join requests ──
CREATE TABLE IF NOT EXISTS public.team_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  message TEXT,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  UNIQUE(team_id, user_id)
);
CREATE INDEX IF NOT EXISTS team_join_requests_team ON public.team_join_requests(team_id);
CREATE INDEX IF NOT EXISTS team_join_requests_status ON public.team_join_requests(team_id, status);

-- ── RLS for new tables ──
ALTER TABLE public.crews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crew_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_join_requests ENABLE ROW LEVEL SECURITY;

-- Crews: team members can read, team admins can manage
CREATE POLICY crews_read ON public.crews FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.team_id = crews.team_id AND tm.user_id = auth.uid())
);
CREATE POLICY crews_admin ON public.crews FOR ALL USING (
  EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.team_id = crews.team_id AND tm.user_id = auth.uid() AND tm.role = 'admin')
);

-- Crew members: team members can read, self can manage own membership
CREATE POLICY crew_members_read ON public.crew_members FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.crews c
    JOIN public.team_members tm ON tm.team_id = c.team_id
    WHERE c.id = crew_members.crew_id AND tm.user_id = auth.uid()
  )
);
CREATE POLICY crew_members_self ON public.crew_members FOR ALL USING (auth.uid() = user_id);

-- Join requests: requesters see own, admins see all for their team
CREATE POLICY join_requests_own ON public.team_join_requests FOR ALL USING (auth.uid() = user_id);
CREATE POLICY join_requests_admin ON public.team_join_requests FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.team_id = team_join_requests.team_id AND tm.user_id = auth.uid() AND tm.role = 'admin')
);
CREATE POLICY join_requests_admin_update ON public.team_join_requests FOR UPDATE USING (
  EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.team_id = team_join_requests.team_id AND tm.user_id = auth.uid() AND tm.role = 'admin')
);

-- Update teams policy: admins can manage (not just creator)
DROP POLICY IF EXISTS teams_own ON public.teams;
CREATE POLICY teams_admin ON public.teams FOR ALL USING (
  EXISTS (SELECT 1 FROM public.team_members tm WHERE tm.team_id = teams.id AND tm.user_id = auth.uid() AND tm.role = 'admin')
);

-- Update team_members policy: self can insert/leave, admins can manage all
DROP POLICY IF EXISTS team_members_own ON public.team_members;
CREATE POLICY team_members_self_insert ON public.team_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY team_members_self_delete ON public.team_members FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY team_members_admin ON public.team_members FOR ALL USING (
  EXISTS (SELECT 1 FROM public.team_members tm2 WHERE tm2.team_id = team_members.team_id AND tm2.user_id = auth.uid() AND tm2.role = 'admin')
);

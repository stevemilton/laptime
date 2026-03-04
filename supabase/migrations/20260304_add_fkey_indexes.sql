-- Add covering indexes for all unindexed foreign keys
-- Fixes 20 Supabase linter warnings (unindexed_foreign_keys)
-- These improve JOIN, ON DELETE CASCADE, and WHERE performance

-- cars
CREATE INDEX IF NOT EXISTS idx_cars_user_id ON public.cars(user_id);

-- disclaimer_acceptances
CREATE INDEX IF NOT EXISTS idx_disclaimer_acceptances_user_id ON public.disclaimer_acceptances(user_id);

-- follows (follower_id is in PK, but following_id is not)
CREATE INDEX IF NOT EXISTS idx_follows_following_id ON public.follows(following_id);

-- lap_sensor_data
CREATE INDEX IF NOT EXISTS idx_lap_sensor_data_lap_id ON public.lap_sensor_data(lap_id);

-- sector_times (4 foreign keys, none indexed)
CREATE INDEX IF NOT EXISTS idx_sector_times_sector_id ON public.sector_times(sector_id);
CREATE INDEX IF NOT EXISTS idx_sector_times_lap_id ON public.sector_times(lap_id);
CREATE INDEX IF NOT EXISTS idx_sector_times_session_id ON public.sector_times(session_id);
CREATE INDEX IF NOT EXISTS idx_sector_times_user_id ON public.sector_times(user_id);

-- sectors
CREATE INDEX IF NOT EXISTS idx_sectors_circuit_id ON public.sectors(circuit_id);
CREATE INDEX IF NOT EXISTS idx_sectors_created_by ON public.sectors(created_by);

-- session_comments
CREATE INDEX IF NOT EXISTS idx_session_comments_session_id ON public.session_comments(session_id);
CREATE INDEX IF NOT EXISTS idx_session_comments_user_id ON public.session_comments(user_id);

-- session_likes (session_id is in PK, but user_id is not)
CREATE INDEX IF NOT EXISTS idx_session_likes_user_id ON public.session_likes(user_id);

-- sessions
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON public.sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_car_id ON public.sessions(car_id);
CREATE INDEX IF NOT EXISTS idx_sessions_circuit_id ON public.sessions(circuit_id);

-- team_join_requests
CREATE INDEX IF NOT EXISTS idx_team_join_requests_user_id ON public.team_join_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_team_join_requests_reviewed_by ON public.team_join_requests(reviewed_by);

-- team_members (team_id is in PK, but user_id is not)
CREATE INDEX IF NOT EXISTS idx_team_members_user_id ON public.team_members(user_id);

-- teams
CREATE INDEX IF NOT EXISTS idx_teams_created_by ON public.teams(created_by);

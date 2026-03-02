-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Profiles (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT 'Driver',
  handle TEXT UNIQUE,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Cars
CREATE TABLE IF NOT EXISTS public.cars (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  make TEXT NOT NULL,
  model TEXT NOT NULL,
  year INTEGER,
  class TEXT,
  colour TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Circuits
CREATE TABLE IF NOT EXISTS public.circuits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  country TEXT NOT NULL DEFAULT 'GB',
  gps_lat DOUBLE PRECISION NOT NULL,
  gps_lng DOUBLE PRECISION NOT NULL,
  start_finish_line GEOMETRY(LINESTRING, 4326),
  length_m INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS circuits_geo ON public.circuits USING GIST (start_finish_line);

-- Sessions
CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  car_id UUID REFERENCES public.cars(id),
  circuit_id UUID REFERENCES public.circuits(id),
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  track_condition TEXT CHECK (track_condition IN ('dry','damp','wet','mixed')),
  tyre_brand TEXT,
  tyre_compound TEXT,
  tyre_age_laps INTEGER,
  setup_notes TEXT,
  session_notes TEXT,
  weather_json JSONB,
  is_public BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Laps
CREATE TABLE IF NOT EXISTS public.laps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lap_number INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  is_personal_best BOOLEAN DEFAULT false,
  trace GEOMETRY(LINESTRING, 4326),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS laps_session ON public.laps(session_id);
CREATE INDEX IF NOT EXISTS laps_trace ON public.laps USING GIST (trace);

-- Lap sensor data
CREATE TABLE IF NOT EXISTS public.lap_sensor_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lap_id UUID NOT NULL REFERENCES public.laps(id) ON DELETE CASCADE,
  timestamps DOUBLE PRECISION[] NOT NULL,
  accel_x REAL[],
  accel_y REAL[],
  accel_z REAL[],
  gyro_x REAL[],
  gyro_y REAL[],
  gyro_z REAL[],
  baro_pressure REAL[],
  mag_heading REAL[]
);

-- Sectors (user-defined)
CREATE TABLE IF NOT EXISTS public.sectors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circuit_id UUID NOT NULL REFERENCES public.circuits(id),
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  name TEXT NOT NULL,
  start_point GEOMETRY(POINT, 4326),
  end_point GEOMETRY(POINT, 4326),
  line GEOMETRY(LINESTRING, 4326),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sector times
CREATE TABLE IF NOT EXISTS public.sector_times (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sector_id UUID NOT NULL REFERENCES public.sectors(id) ON DELETE CASCADE,
  lap_id UUID NOT NULL REFERENCES public.laps(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id),
  user_id UUID NOT NULL REFERENCES public.profiles(id),
  duration_ms INTEGER NOT NULL,
  computed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Follows
CREATE TABLE IF NOT EXISTS public.follows (
  follower_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id)
);

-- Teams
CREATE TABLE IF NOT EXISTS public.teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT UNIQUE NOT NULL,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.team_members (
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (team_id, user_id)
);

-- Disclaimer acceptances (legal record)
CREATE TABLE IF NOT EXISTS public.disclaimer_acceptances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id),
  accepted_at TIMESTAMPTZ DEFAULT NOW(),
  app_version TEXT NOT NULL,
  disclaimer_version TEXT NOT NULL
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', 'Driver'));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- RLS Policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cars ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.laps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lap_sensor_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sector_times ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disclaimer_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circuits ENABLE ROW LEVEL SECURITY;

-- Profiles: own = full, others = read
CREATE POLICY profiles_read ON public.profiles FOR SELECT USING (true);
CREATE POLICY profiles_update ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Cars: own only
CREATE POLICY cars_all ON public.cars FOR ALL USING (auth.uid() = user_id);

-- Circuits: anyone can read
CREATE POLICY circuits_read ON public.circuits FOR SELECT USING (true);

-- Sessions: own = full, public = readable
CREATE POLICY sessions_own ON public.sessions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY sessions_public_read ON public.sessions FOR SELECT USING (is_public = true);

-- Laps: inherit from session
CREATE POLICY laps_own ON public.laps FOR ALL
  USING (EXISTS (SELECT 1 FROM public.sessions s WHERE s.id = session_id AND s.user_id = auth.uid()));
CREATE POLICY laps_public_read ON public.laps FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.sessions s WHERE s.id = session_id AND s.is_public = true));

-- Sensor data: own only
CREATE POLICY sensor_own ON public.lap_sensor_data FOR ALL
  USING (EXISTS (
    SELECT 1 FROM public.laps l JOIN public.sessions s ON s.id = l.session_id
    WHERE l.id = lap_id AND s.user_id = auth.uid()
  ));

-- Sectors: anyone reads, own creates
CREATE POLICY sectors_read ON public.sectors FOR SELECT USING (true);
CREATE POLICY sectors_insert ON public.sectors FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Sector times
CREATE POLICY sector_times_read ON public.sector_times FOR SELECT USING (true);
CREATE POLICY sector_times_own ON public.sector_times FOR ALL USING (auth.uid() = user_id);

-- Follows
CREATE POLICY follows_own ON public.follows FOR ALL USING (auth.uid() = follower_id);
CREATE POLICY follows_read ON public.follows FOR SELECT USING (true);

-- Teams: read all, own team management
CREATE POLICY teams_read ON public.teams FOR SELECT USING (true);
CREATE POLICY teams_own ON public.teams FOR ALL USING (auth.uid() = created_by);

-- Team members
CREATE POLICY team_members_read ON public.team_members FOR SELECT USING (true);
CREATE POLICY team_members_own ON public.team_members FOR ALL USING (auth.uid() = user_id);

-- Disclaimer: own only
CREATE POLICY disclaimer_own ON public.disclaimer_acceptances FOR ALL USING (auth.uid() = user_id);

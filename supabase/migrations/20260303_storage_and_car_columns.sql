-- Storage & Car Columns Migration
-- Adds missing car columns (from Drift v2) and creates storage buckets for images

-- ── Add missing columns to cars table ──
ALTER TABLE public.cars
  ADD COLUMN IF NOT EXISTS image_url TEXT,
  ADD COLUMN IF NOT EXISTS power_hp INTEGER,
  ADD COLUMN IF NOT EXISTS weight_kg INTEGER,
  ADD COLUMN IF NOT EXISTS drivetrain TEXT,
  ADD COLUMN IF NOT EXISTS engine_capacity TEXT,
  ADD COLUMN IF NOT EXISTS modifications TEXT,
  ADD COLUMN IF NOT EXISTS tyre_setup TEXT;

-- ── Create storage buckets ──
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('car-images', 'car-images', true, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('team-logos', 'team-logos', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- ── Storage RLS policies ──
-- Public read access for all three buckets
CREATE POLICY "Public read avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Public read car-images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'car-images');

CREATE POLICY "Public read team-logos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'team-logos');

-- Authenticated users can upload/update/delete within their own {userId}/ folder
CREATE POLICY "Auth upload avatars"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth update avatars"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth delete avatars"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth upload car-images"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'car-images'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth update car-images"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'car-images'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth delete car-images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'car-images'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth upload team-logos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'team-logos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth update team-logos"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'team-logos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Auth delete team-logos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'team-logos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

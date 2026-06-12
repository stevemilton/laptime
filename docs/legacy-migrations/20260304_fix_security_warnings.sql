-- Fix security warnings from Supabase linter
--
-- 1. handle_new_user function has mutable search_path - pin it
--
-- NOTE: spatial_ref_sys RLS warning is a known Supabase/PostGIS issue.
-- The table is owned by the postgres superuser and cannot be altered via
-- the SQL editor. This is safe to ignore — it's a read-only reference
-- table of coordinate system definitions.

-- ══════════════════════════════════════════════════════════════
-- handle_new_user: recreate with immutable search_path
-- Using fully-qualified names and SET search_path = '' to prevent
-- search_path manipulation attacks.
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', 'Driver'));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

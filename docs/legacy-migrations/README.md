# Legacy migrations — ALREADY APPLIED, DO NOT RE-RUN

These three files were applied to the production database **by hand via the
SQL editor** (around build 23, without being committed or registered in the
migration history). They are kept here as the historical record of how the
live policy set came to differ from the committed migrations.

They MUST NOT be run again and MUST NOT live in `supabase/migrations/`:

1. **Re-running them reverts security fixes.** They were superseded by
   `20260612_v2_schema_alignment.sql` and `20260612_v2_advisor_hardening.sql`
   (both applied to production on 2026-06-12). For example,
   `fix_rls_performance.sql` recreates `teams_insert` as
   `WITH CHECK (auth.uid() IS NOT NULL)`, which would re-allow inserting a
   team with an arbitrary `created_by` — the v2 hardening tightened this to
   `(SELECT auth.uid()) = created_by`, and replaced the inline admin-check
   subqueries with SECURITY DEFINER helpers.

2. **They break fresh environments and `supabase db push`.** Their
   `20260304` date prefix sorts BEFORE `20260304_social_feed.sql` /
   `20260304_team_system_v2.sql` lexicographically resolves wrong (`a`/`f`
   sort before `s`/`t`), so a clean database aborts on missing tables —
   and the CLI refuses versions older than the already-applied `20260612`
   migrations with a history mismatch.

The committed files in `supabase/migrations/` plus the two `20260612` v2
migrations are the source of truth for the live schema.

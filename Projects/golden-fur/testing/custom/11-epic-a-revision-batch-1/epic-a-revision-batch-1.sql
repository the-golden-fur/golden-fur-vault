-- Epic A — Revision Batch 1 (Issues #71-#78) — Supabase SQL Editor
-- verification queries.
-- Type: Custom epic implementation (temp/context Epic A Guide + Design
-- workbook), not a single-issue bug fix.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. Sections 1-4 are read-only. Section 5 is
-- self-rolling-back (wrapped in begin/rollback) — nothing here permanently
-- changes your data unless explicitly noted.
--
-- Prerequisite: migrations 20260725041 through 20260725045 applied
-- (supabase db push, or `supabase db reset` for a fresh local database).
-- Do NOT apply 20260725046 yet - see that migration's header and the
-- "Migration strategy: add-then-drop" section of the .md in this folder.
-- 041/042 are additive-only: species/breed/health_conditions are
-- deliberately still present (deprecated) at this point, not dropped.

-- =========================================================================
-- SECTION 1 (Issue #71): breeds table seeded, pets.pet_type/breed_id/
-- photo_url exist alongside the still-present (deprecated) species/breed
-- =========================================================================

select pet_type, count(*) as breed_count
from public.breeds
group by pet_type
order by pet_type;
-- Expected: two rows, Dog and Cat, each with several seeded breeds.

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'pets'
order by ordinal_position;
-- Expected: pet_type (not null), breed_id (nullable, uuid), photo_url
-- (nullable, text) present - AND species/breed/health_conditions are
-- still present too (deprecated, not dropped until migration
-- 20260725046_m02_drop_deprecated_pet_columns.sql is applied - see that
-- migration's header for why it's deferred).

-- =========================================================================
-- SECTION 2 (Issue #71 AC-4): backfill correctness — at least one exact
-- match resolved, unmatched legacy values left NULL (not silently dropped)
-- =========================================================================
-- The migration's own RAISE NOTICE output (visible in the migration run
-- log, not a query result) lists every unmatched legacy breed value. This
-- query cross-checks from the data side: any pet with a NULL breed_id is a
-- pet whose original free-text breed either didn't match a seeded breed
-- name (case-insensitively) or had no breed at all originally.

select id, name, pet_type, breed_id
from public.pets
where breed_id is null;
-- Cross-reference against the migration run log's RAISE NOTICE lines to
-- confirm every id listed here also appears there (or simply never had a
-- breed value to begin with).

-- =========================================================================
-- SECTION 3 (Issue #72): pet_health_conditions table + RLS
-- =========================================================================

select conrelid::regclass, conname, contype
from pg_constraint
where conrelid = 'public.pet_health_conditions'::regclass and contype = 'u';
-- Expected: a UNIQUE constraint on pet_id.

select polname, polcmd, roles
from pg_policy
where polrelid = 'public.pet_health_conditions'::regclass
order by polname;
-- Expected 4 policies: Veterinarians can insert / Veterinarians can update /
-- Any staff can read / Customers can read their own pet's health conditions.

-- =========================================================================
-- SECTION 4 (Issue #73): staff-creation RLS already grants Admin branch_id
-- write (confirms the policy statement, not a behavior change at this layer
-- — see epic-a-revision-batch-1.md for where the real gap was)
-- =========================================================================

select polname, polcmd, qual, with_check
from pg_policy
where polrelid = 'public.staff_profiles'::regclass
  and polname = 'Admins and superadmins can manage staff profile metadata';
-- Expected: with_check references current_staff_role() in ('Admin', 'Superadmin').

-- =========================================================================
-- SECTION 5 (Issue #78): a Veterinarian can upsert pet_health_conditions;
-- a non-Veterinarian cannot (demonstrated via direct SQL role-switch is not
-- practical here — RLS is keyed off auth.uid() via current_staff_role(),
-- which requires a real authenticated session. Use the Postman collection's
-- role-token requests for the authoritative RLS check. This section instead
-- confirms the upsert shape works end-to-end as the service-role client
-- would perform it.)
-- =========================================================================

begin;

  -- Replace both uuids with a real pets.id and a real Veterinarian
  -- staff_profiles.id from your database before running.
  insert into public.pet_health_conditions (pet_id, conditions_text, updated_by_staff_id)
  values (
    '00000000-0000-0000-0000-000000000000', -- <-- replace with a real pets.id
    'SQL verification — seasonal allergies',
    '00000000-0000-0000-0000-000000000000'  -- <-- replace with a real Veterinarian staff_profiles.id
  )
  on conflict (pet_id) do update
    set conditions_text = excluded.conditions_text,
        updated_by_staff_id = excluded.updated_by_staff_id,
        updated_at = now()
  returning id, pet_id, conditions_text, updated_at;
  -- Expected: one row back, upserted (insert if none existed, update if one did).

rollback; -- nothing is persisted; safe to run against a live project

-- =========================================================================
-- SECTION 6 (deferred cleanup, NOT part of this batch's "done" state):
-- confirm species/breed/health_conditions are still present, and preview
-- what migration 20260725046_m02_drop_deprecated_pet_columns.sql will do
-- =========================================================================
-- Read-only preview - do not apply 046 until you've confirmed nothing else
-- (another service, a report/export job, a BI tool) still reads these
-- three columns directly.

select
  count(*) filter (where species is not null) as pets_with_species,
  count(*) filter (where breed is not null) as pets_with_breed,
  count(*) filter (where health_conditions is not null) as pets_with_health_conditions
from public.pets;
-- Expected right now: species count matches your total pet count (it was
-- NOT NULL and backfilled into pet_type, but the original column is
-- untouched); breed/health_conditions counts reflect however many pets
-- actually had those free-text values. Once you're ready, apply
-- 20260725046_m02_drop_deprecated_pet_columns.sql to drop all three.

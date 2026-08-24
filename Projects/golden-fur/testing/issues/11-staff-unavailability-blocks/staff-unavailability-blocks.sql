-- Issue #11 Verification SQL Queries
-- Staff Unavailability Blocks: Table Structure, Constraints, and RLS

-- ============================================================
-- 1. Verify Column Drops (AC-1, AC-2)
-- ============================================================

-- Check branches table no longer has break_window
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'branches'
  AND column_name = 'break_window';
-- Expected: 0 rows

-- Check staff_profiles table no longer has is_busy or busy_until
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'staff_profiles'
  AND column_name IN ('is_busy', 'busy_until');
-- Expected: 0 rows

-- ============================================================
-- 2. Verify Table Creation (AC-3)
-- ============================================================

-- Check table exists and has required columns
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'staff_unavailability_blocks'
ORDER BY ordinal_position;
-- Expected columns:
--   id (uuid, not null)
--   staff_id (uuid, not null)
--   start_time (timestamp with time zone, not null)
--   end_time (timestamp with time zone, not null)
--   reason (text, nullable)
--   created_by (uuid, not null)
--   created_at (timestamp with time zone, not null)

-- ============================================================
-- 3. Verify Foreign Key Constraints (AC-4)
-- ============================================================

-- Check foreign key constraints
SELECT
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS referenced_table_name,
  ccu.column_name AS referenced_column_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.table_name = 'staff_unavailability_blocks'
  AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY kcu.column_name;
-- Expected:
--   staff_id -> staff_profiles(id) ON DELETE CASCADE
--   created_by -> auth.users(id) ON DELETE CASCADE

-- ============================================================
-- 4. Verify Indices (Performance)
-- ============================================================

SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'staff_unavailability_blocks'
ORDER BY indexname;
-- Expected indices:
--   idx_staff_unavailability_blocks_staff_id
--   idx_staff_unavailability_blocks_created_by
--   idx_staff_unavailability_blocks_time_range

-- ============================================================
-- 5. Verify RLS is Enabled (AC-5)
-- ============================================================

SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'staff_unavailability_blocks';
-- Expected: rowsecurity = true

-- ============================================================
-- 6. Verify RLS Policies (AC-5)
-- ============================================================

SELECT
  policyname,
  permissive,
  roles,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'staff_unavailability_blocks'
ORDER BY policyname;
-- Expected policies (8 total):
--   Staff can read/create/update/delete their own blocks (4)
--   Admins and superadmins can read/insert/update/delete all unavailability blocks (4)
-- Note: the insert/update/delete admin policies were originally named "...for any staff"
-- but that exceeded Postgres's 63-char identifier limit and got silently truncated;
-- renamed to match the "read all unavailability blocks" pattern instead.

-- ============================================================
-- 7. Smoke Test: Insert Sample Data
-- ============================================================
-- The Supabase SQL Editor runs queries as the `postgres` role, not as a
-- signed-in user via a client SDK — there's no JWT session, so auth.uid()
-- is NULL here and RLS is bypassed entirely (postgres owns the tables).
-- That means this section can only smoke-test the table/FK constraints,
-- not the RLS policies themselves — see the "Testing RLS as a real user"
-- note after section 9 for how to verify the policies for real.
--
-- Uses an existing staff_profiles row for both staff_id and created_by
-- (self-created block) so the FK constraints are satisfied without a
-- real auth session.

WITH test_staff AS (
  SELECT id FROM public.staff_profiles LIMIT 1
)
INSERT INTO public.staff_unavailability_blocks
  (staff_id, start_time, end_time, reason, created_by)
SELECT id, now() + interval '1 day', now() + interval '2 days', 'Smoke test block (issue #11)', id
FROM test_staff
RETURNING *;
-- Expected: 1 row inserted (requires at least one row in staff_profiles)

-- ============================================================
-- 8. Smoke Test: Query the Inserted Row
-- ============================================================

SELECT *
FROM public.staff_unavailability_blocks
WHERE reason = 'Smoke test block (issue #11)';
-- Expected: 1 row (the row inserted above)

-- ============================================================
-- 9. Smoke Test: Row Count
-- ============================================================

SELECT COUNT(*) as total_blocks
FROM public.staff_unavailability_blocks;
-- Expected: count includes the smoke-test row above (RLS doesn't apply
-- to the `postgres` role used by the SQL Editor, so this always sees
-- every row regardless of staff/admin scoping)

-- ============================================================
-- Cleanup: remove the smoke-test row
-- ============================================================

DELETE FROM public.staff_unavailability_blocks
WHERE reason = 'Smoke test block (issue #11)';
-- Run this so the script can be re-run without accumulating test data

-- ============================================================
-- Testing RLS as a real user (optional, not part of this script)
-- ============================================================
-- The SQL Editor can't exercise RLS as a specific staff/admin user. To
-- verify AC-5 for real, either:
--   a) Supabase Dashboard > Authentication > Policies > use the policy
--      tester against a real user, or
--   b) call the table through the client SDK (supabase-js) while signed
--      in as a staff member, then again as an Admin/Superadmin, and
--      confirm the staff account only sees/edits its own rows while the
--      admin account sees/edits all of them.

-- ============================================================
-- 10. Verify No Unintended Tables (AC-6)
-- ============================================================

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('staff_availability_templates', 'staff_availability_overrides');
-- Expected: 0 rows

-- ============================================================
-- 11. List All Tables in Public Schema (Sanity Check)
-- ============================================================

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
-- Verify expected tables are present and no unexpected ones

-- Issue #28 Verification SQL
-- Confirms the "manage all" RLS policies on staff_unavailability_blocks now
-- include Supervisor (migration 20260711020_...add_supervisor_rls.sql).
--
-- Note: the Supabase SQL Editor runs as the `postgres` role, which bypasses
-- RLS entirely (no auth.uid() / no JWT session) — this script can confirm
-- the policies exist with the right definition, but cannot exercise them as
-- a signed-in Supervisor. That's what the Postman collection in this folder
-- is for, exercised through the actual API.

-- ============================================================
-- 1. Confirm the four "manage all" policies now list Supervisor
-- ============================================================

select
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where tablename = 'staff_unavailability_blocks'
  and policyname like 'Admins, supervisors, and superadmins%'
order by policyname;
-- Expected: 4 rows (read/insert/update/delete), each with
-- qual/with_check containing "current_staff_role() = ANY (ARRAY['Admin'::staff_role, 'Supervisor'::staff_role, 'Superadmin'::staff_role])"
-- (Postgres renders the IN (...) list this way once persisted)

-- ============================================================
-- 2. Confirm the old Admin/Superadmin-only policies are gone
-- ============================================================

select policyname
from pg_policies
where tablename = 'staff_unavailability_blocks'
  and policyname like 'Admins and superadmins can%';
-- Expected: 0 rows — ...020 drops all four before recreating them

-- ============================================================
-- 3. Confirm the "manage own" policies are untouched (AC-4)
-- ============================================================

select policyname, cmd
from pg_policies
where tablename = 'staff_unavailability_blocks'
  and policyname like 'Staff can%'
order by policyname;
-- Expected: "Staff can read/create/delete their own unavailability blocks"
-- (3 rows — the "own" UPDATE policy was already dropped by migration
-- ...019 as part of Issue #29's schema prerequisite, unrelated to this issue)

-- ============================================================
-- 4. Full policy list sanity check
-- ============================================================

select count(*) as total_policies
from pg_policies
where tablename = 'staff_unavailability_blocks';
-- Expected: 7 (3 "manage own" + 4 "manage all") — see note in section 3
-- on why "manage own" is 3 rather than the original 4.

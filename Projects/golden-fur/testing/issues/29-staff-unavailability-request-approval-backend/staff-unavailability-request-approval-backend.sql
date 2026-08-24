-- Issue #29 Verification SQL
-- Covers the part of #29 that's actually new in this branch: the "no
-- self-review" RLS restriction (migration
-- 20260711021_...no_self_review.sql). The status enum/columns/trigger
-- (migration 20260711019_...add_status.sql) already landed as Issue #27's
-- prerequisite — see testing/docs/issues/27-staff-availability-service/
-- staff-availability-service.sql for that verification.
--
-- Note: the Supabase SQL Editor runs as the `postgres` role and bypasses RLS
-- entirely, so this script can confirm the policy's definition but not
-- exercise it as a signed-in user — that's what the Postman collection in
-- this folder does through the actual API (which itself uses the
-- service-role client and enforces "no self-review" at the application
-- layer in reviewUnavailabilityBlock(), matching AC-9's "both at the
-- endpoint and at the RLS layer" requirement).

-- ============================================================
-- 1. Confirm the update policy now excludes the requester
-- ============================================================

select
  policyname,
  cmd,
  qual,
  with_check
from pg_policies
where tablename = 'staff_unavailability_blocks'
  and cmd = 'UPDATE';
-- Expected: exactly 1 row —
-- "Admins, supervisors, and superadmins can update others' unavailability blocks"
-- qual/with_check both contain "staff_id <> auth.uid()" alongside the
-- current_staff_role() check. This is now the ONLY update policy on the
-- table (the staff "own" UPDATE policy was dropped by ...019).

-- ============================================================
-- 2. Confirm the enforcement trigger and status columns exist
-- (prerequisite landed by #27's migration ...019 — sanity check only)
-- ============================================================

select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'staff_unavailability_blocks'
  and column_name in ('status', 'is_quick_action', 'reviewed_by', 'reviewed_at', 'denial_reason')
order by column_name;
-- Expected: all 5 columns present

select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.staff_unavailability_blocks'::regclass
  and tgname = 'trg_enforce_unavailability_block_status';
-- Expected: 1 row, tgenabled = 'O' (enabled)

-- ============================================================
-- 3. Full policy count sanity check
-- ============================================================

select cmd, count(*) as policy_count
from pg_policies
where tablename = 'staff_unavailability_blocks'
group by cmd
order by cmd;
-- Expected: DELETE 2 (own + manage-all), INSERT 2, SELECT 2, UPDATE 1
-- (own UPDATE was dropped in ...019; manage-all UPDATE now carries the
-- "staff_id <> auth.uid()" restriction from ...021)

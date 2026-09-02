-- Staff Booking Overhaul -- Supabase SQL Editor verification queries.
-- Type: Custom cross-cutting batch (merged Date/Time+Staff step, staff
-- days-off rename + Entire Day option, Superadmin System Configuration,
-- Care Instructions catalog wiring, bookings queue search/sort).
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only EXCEPT Section 5, which
-- is a real insert/update sequence - it cleans up after itself inside a
-- begin/rollback block, so nothing is left behind.
--
-- Prerequisite: migrations 20260728063 and 20260728064 applied
-- (supabase db push, or `supabase db reset` for a fresh local database,
-- which also re-runs the seeds). These come after 20260728062 (the prior
-- "Booking Status Automation" batch).

-- =========================================================================
-- SECTION 1: staff_unavailability_blocks.is_full_day exists (Entire Day
-- option)
-- =========================================================================

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'staff_unavailability_blocks'
  and column_name = 'is_full_day';
-- Expected: one row - boolean, is_nullable = NO, column_default = false.

-- =========================================================================
-- SECTION 2: branches has a write (UPDATE) RLS policy now, Superadmin-only
-- =========================================================================

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'branches'
order by policyname;
-- Expected: two policies - the pre-existing "Authenticated users can view
-- branches" (SELECT, using true) and the new "Superadmins can manage
-- branches" (UPDATE), whose qual/with_check both reference
-- current_staff_role() = 'Superadmin'.

-- =========================================================================
-- SECTION 3: branches table still has the full config surface
-- (name/address/contact_number/is_vet_branch/operating_hours/timezone)
-- =========================================================================

select id, name, address, contact_number, is_vet_branch, operating_hours, timezone
from public.branches
order by name;
-- Expected: your seeded branches (Makati, Southwoods), each with a
-- non-empty operating_hours jsonb object.

-- =========================================================================
-- SECTION 4: the enforce_unavailability_block_status trigger from migration
-- ...019 is untouched - Entire Day requests still follow the same
-- pending-vs-auto-approved rule as any custom range
-- =========================================================================

select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.staff_unavailability_blocks'::regclass
  and tgname = 'trg_enforce_unavailability_block_status';
-- Expected: one row, tgenabled = 'O' (enabled) - the trigger from ...019
-- still exists and was not replaced/dropped by ...063.

-- =========================================================================
-- SECTION 5: Entire Day round-trip - a self-requested full-day block lands
-- pending; an on-behalf-of one lands approved. Self-cleaning via rollback.
-- =========================================================================

begin;

with sample as (
  select
    (select id from public.staff_profiles where role = 'Groomer' limit 1) as self_staff_id,
    (select id from public.staff_profiles where role = 'Admin' limit 1) as admin_id
),
self_requested as (
  -- Mirrors a staff member requesting their own Entire Day off - created_by
  -- = staff_id, so the ...019 trigger assigns status = 'pending'.
  insert into public.staff_unavailability_blocks (
    staff_id, start_time, end_time, is_full_day, created_by, reason
  )
  select
    self_staff_id,
    now() + interval '10 days',
    now() + interval '10 days 8 hours',
    true,
    self_staff_id,
    'Self-requested day off'
  from sample
  returning id, staff_id, created_by, is_full_day, status
),
on_behalf_of as (
  -- Mirrors an Admin requesting an Entire Day off for someone else -
  -- created_by <> staff_id, so the trigger auto-approves it.
  insert into public.staff_unavailability_blocks (
    staff_id, start_time, end_time, is_full_day, created_by, reason
  )
  select
    self_staff_id,
    now() + interval '17 days',
    now() + interval '17 days 8 hours',
    true,
    admin_id,
    'Approved by Admin'
  from sample
  returning id, staff_id, created_by, is_full_day, status
)
select
  self_requested.status as self_requested_status,
  self_requested.is_full_day as self_requested_is_full_day,
  on_behalf_of.status as on_behalf_of_status,
  on_behalf_of.is_full_day as on_behalf_of_is_full_day
from self_requested, on_behalf_of;
-- Expected: self_requested_status = 'pending', on_behalf_of_status =
-- 'approved', both is_full_day columns = true.

rollback;
-- Confirm nothing was left behind:
select count(*) as leftover_test_blocks
from public.staff_unavailability_blocks
where reason in ('Self-requested day off', 'Approved by Admin');
-- Expected: 0.

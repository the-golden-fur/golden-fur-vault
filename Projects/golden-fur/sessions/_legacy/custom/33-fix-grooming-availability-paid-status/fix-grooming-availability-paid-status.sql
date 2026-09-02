-- Fix Grooming Availability (stale 'Paid' status) -- Supabase SQL Editor
-- verification queries.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only.
--
-- Prerequisite: migration 20260808109_m03_get_staff_availability_fix_paid_
-- status.sql applied (supabase db push, or `supabase db reset` for a fresh
-- local database, which re-runs everything in order).

-- =========================================================================
-- SECTION 1: get_staff_availability()'s definition no longer references the
-- retired 'Paid' status value anywhere
-- =========================================================================

select pg_get_functiondef(oid) as definition
from pg_proc
where proname = 'get_staff_availability';
-- Expected: Check 2 reads "bk.status in ('Pending', 'In Progress',
-- 'Completed')" - search the returned definition text for 'Paid' and
-- confirm the only matches are inside comments, not the status list itself.

-- =========================================================================
-- SECTION 2: booking_status enum still has no 'Paid' member (unchanged by
-- this fix - confirms 20260803083 is still in effect)
-- =========================================================================

select enumlabel
from pg_enum
where enumtypid = 'public.booking_status'::regtype
order by enumsortorder;
-- Expected: Pending, In Progress, Completed, Cancelled, No-show - no 'Paid'.

-- =========================================================================
-- SECTION 3: the RPC runs without error against real data (this is exactly
-- what GET /bookings/availability triggers for a staffed service category)
-- =========================================================================

select *
from public.get_staff_availability(
  p_role := 'Groomer',
  p_branch_id := (select id from public.branches limit 1),
  p_requested_start := (current_date + interval '1 day' + interval '10 hour'),
  p_requested_end := (current_date + interval '1 day' + interval '11 hour')
);
-- Expected: succeeds with zero or more rows - no
-- "invalid input value for enum booking_status" error. Prior to this fix,
-- this call would throw that error whenever any staff member at the branch
-- had a Pending/In Progress/Completed booking overlapping the requested
-- window (i.e. as soon as the status IN list was evaluated against real
-- rows) - depending on data it could also throw immediately since the
-- literal 'Paid' itself fails to parse as a booking_status value regardless
-- of whether any row actually has that status.

-- =========================================================================
-- SECTION 4: lunch-break behavior (added by 20260804092) still works after
-- this fix - not a regression
-- =========================================================================

select branch_id, lunch_break_enabled, lunch_break_start, lunch_break_end
from public.policy_configurations
order by branch_id nulls last;
-- Note the branch-specific or default row's lunch window, then re-run
-- Section 3's query with p_requested_start/p_requested_end set inside that
-- window for a branch where lunch_break_enabled = true.
-- Expected: zero rows returned (every staff member is excluded during the
-- lunch break), still with no enum error.

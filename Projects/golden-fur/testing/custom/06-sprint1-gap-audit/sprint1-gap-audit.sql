-- Sprint 1 gap audit & fix — Supabase SQL Editor verification queries
-- Type: Custom audit + fix (not tracked against a specific epic/issue backlog item)
--
-- Run these one section at a time in Supabase Studio: your project -> SQL Editor -> New query.
-- Every section is read-only or self-rolling-back (see Section 1) — nothing here
-- permanently changes your data.
--
-- NOTE: these queries were originally written to demonstrate two gaps/bugs
-- found during the audit. Both have since been fixed in code (see
-- sprint1-gap-audit.md, "Fixes implemented" #3 and #4). Sections 1-2 below
-- now demonstrate the FIXED behavior instead of the original bug — apply
-- migration 20260714031_m01_get_staff_availability_approved_only.sql before
-- running Section 2, and make sure your server is running the current
-- unavailabilityBlock.service.ts before running Section 1's application-level
-- equivalent (Postman request 6 in this folder) — Section 1 itself talks
-- directly to the trigger, not the Node service, so it demonstrates the
-- trigger's own (unchanged, already-correct) logic in isolation.

-- =========================================================================
-- SECTION 1: Confirm the quick-action trigger logic (unchanged, was never
-- the bug) — the bug was the Node service never SETTING is_quick_action
-- =========================================================================
-- Expected per spec (Modules-Features + M01 Process 7): a staff member's own
-- "now until end of shift" quick action must be created with status =
-- 'approved' immediately. This was never broken at the trigger/DB level —
-- the bug was that unavailabilityBlock.service.ts's createUnavailabilityBlock()
-- never included `is_quick_action: true` in its insert payload, so the
-- column silently defaulted to false and the trigger fell through to its
-- "pending" branch. That's now fixed (one line:
-- `is_quick_action: Boolean(quickAction)` in the insert call).
--
-- This block proves the trigger itself has always handled is_quick_action
-- correctly when it IS set — i.e. confirms the fix's assumption. Replace the
-- uuid below with any real staff_profiles.id.

begin;

  insert into public.staff_unavailability_blocks
    (staff_id, start_time, end_time, reason, created_by, is_quick_action)
  values (
    '00000000-0000-0000-0000-000000000000', -- <-- replace with a real staff_profiles.id
    now(),
    now() + interval '2 hours',
    'SQL audit repro — quick action self-request, fix verification',
    '00000000-0000-0000-0000-000000000000', -- <-- same id as above (created_by = staff_id = "self")
    true
  )
  returning id, staff_id, created_by, is_quick_action, status;

  -- Expected now: status = approved (this always worked when is_quick_action
  -- was actually passed in — confirming the fixed service now does so too)

rollback; -- nothing is persisted; safe to run against a live project


-- =========================================================================
-- SECTION 2: Confirm get_staff_availability() now filters by status
-- =========================================================================
-- Requires migration 20260714031_m01_get_staff_availability_approved_only.sql
-- to have been applied. Prints the live function body — confirm the
-- unavailability-overlap subquery now includes "sub.status = 'approved'"
-- alongside the staff_id/time-range conditions.

select pg_get_functiondef('public.get_staff_availability(uuid, timestamptz, timestamptz)'::regprocedure);


-- =========================================================================
-- SECTION 3: Any pre-fix stuck-pending quick-action rows?
-- =========================================================================
-- Lists any quick-action blocks that are NOT approved. On a project that had
-- staff using the quick action before this fix shipped, this may show
-- historical rows stuck in 'pending' from the bug. These are safe to
-- manually approve via Supabase Studio (Table Editor -> staff_unavailability_blocks
-- -> edit the row's status to 'approved') since they were always meant to be
-- immediate/auto-approved.

select id, staff_id, created_by, is_quick_action, status, start_time, end_time, created_at
from public.staff_unavailability_blocks
where is_quick_action = true
  and status <> 'approved'
order by created_at desc;


-- =========================================================================
-- SECTION 4: Confirm staff_profiles.is_active / role / branch_id are now
-- writable through the app (post-fix)
-- =========================================================================
-- Before the fix, all rows would show is_active = true (never written by the
-- app) and role/branch_id would only ever match their originally-seeded
-- values. After using the new "Manage account" UI (or PATCH /staff/:id/manage
-- directly — see the Postman collection), you should see updated_at move
-- forward and the corresponding column(s) reflect your change.

select id, username, role, branch_id, is_active, created_at, updated_at
from public.staff_profiles
order by updated_at desc;

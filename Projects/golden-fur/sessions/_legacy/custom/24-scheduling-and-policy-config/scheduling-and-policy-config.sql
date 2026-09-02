-- Scheduling & policy config addendum (#24) - bundled migrations for manual
-- review/reference. Source of truth is supabase/migrations/; this file
-- mirrors those four files, in application order.

-- =============================================================================
-- 20260804090_m01_branches_insert_rls.sql
-- =============================================================================
-- Superadmin System Configuration addendum: lets Superadmin add a brand new
-- branch. ...064 added the UPDATE policy for editing existing branches but
-- never an INSERT policy, and no route ever called for one until now.
-- Mirrors that same migration's role check exactly (Superadmin-only, not the
-- Admin+Superadmin pattern used elsewhere) - branch identity is still
-- system-level config, not day-to-day admin work.

create policy "Superadmins can create branches"
  on public.branches
  for insert
  to authenticated
  with check (public.current_staff_role() = 'Superadmin');


-- =============================================================================
-- 20260804091_m09_policy_configurations_lunch_break.sql
-- =============================================================================
-- Scheduling addendum: fixed daily lunch break (default 12:00-13:00) during
-- which nothing may be booked. Reuses policy_configurations' existing
-- default-row + per-branch-override pattern (...037) rather than resurrecting
-- branches.break_window (dropped by ...010 because it was dead, unwired
-- schema - this time the columns are actually read, by
-- get_staff_availability() and getDaySlots()).

alter table public.policy_configurations
  add column lunch_break_enabled boolean not null default true,
  add column lunch_break_start time not null default '12:00',
  add column lunch_break_end time not null default '13:00';


-- =============================================================================
-- 20260804092_m03_get_staff_availability_lunch_break.sql
-- =============================================================================
-- Scheduling addendum: get_staff_availability() gains a branch-level lunch
-- break check, the same shape as the existing operating-hours Check 1 (a
-- failure returns an empty set regardless of staff schedules) - not a
-- per-staff staff_unavailability_blocks row, since the break applies to
-- every staff member at the branch uniformly.
--
-- CREATE OR REPLACE against the identical signature (same rationale as
-- ...036/...062's own header notes) - no caller changes. Everything else in
-- the function body is unchanged from 20260728062.

create or replace function public.get_staff_availability(
  p_role public.staff_role,
  p_branch_id uuid,
  p_requested_start timestamptz,
  p_requested_end timestamptz,
  p_staff_id uuid default null,
  p_exclude_booking_id uuid default null
)
returns table (
  staff_id uuid,
  display_name text,
  profile_photo_url text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch_timezone text;
  v_day_name text;
  v_requested_start_local time;
  v_requested_end_local time;
  v_open_time time;
  v_close_time time;
  v_lunch_break_enabled boolean;
  v_lunch_break_start time;
  v_lunch_break_end time;
begin
  if p_requested_end <= p_requested_start then
    return;
  end if;

  select b.timezone
    into v_branch_timezone
  from public.branches b
  where b.id = p_branch_id;

  if v_branch_timezone is null then
    return;
  end if;

  v_day_name :=
    lower(trim(to_char(p_requested_start at time zone v_branch_timezone, 'day')));
  v_requested_start_local :=
    (p_requested_start at time zone v_branch_timezone)::time;
  v_requested_end_local :=
    (p_requested_end at time zone v_branch_timezone)::time;

  -- Check 1: within branch operating hours for that day. Branch-level, so a
  -- failure returns an empty set regardless of staff schedules (#49 AC-4).
  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.operating_hours ? v_day_name
  ) then
    return;
  end if;

  select
    make_time(
      split_part((b.operating_hours -> v_day_name ->> 'open'), ':', 1)::int,
      split_part((b.operating_hours -> v_day_name ->> 'open'), ':', 2)::int,
      0
    ),
    make_time(
      split_part((b.operating_hours -> v_day_name ->> 'close'), ':', 1)::int,
      split_part((b.operating_hours -> v_day_name ->> 'close'), ':', 2)::int,
      0
    )
    into v_open_time, v_close_time
  from public.branches b
  where b.id = p_branch_id;

  if v_open_time is null or v_close_time is null then
    return;
  end if;

  if v_requested_start_local < v_open_time
     or v_requested_end_local > v_close_time
     or v_requested_start_local >= v_requested_end_local
  then
    return;
  end if;

  -- Lunch break check: the branch-specific policy_configurations row wins
  -- whole-row if one exists, else the system-wide default (branch_id null)
  -- row - same whole-row precedence resolveEffectivePolicy() uses
  -- server-side, mirrored here so the RPC agrees with the TS resolution.
  select pc.lunch_break_enabled, pc.lunch_break_start, pc.lunch_break_end
    into v_lunch_break_enabled, v_lunch_break_start, v_lunch_break_end
  from public.policy_configurations pc
  where pc.branch_id = p_branch_id
  limit 1;

  if not found then
    select pc.lunch_break_enabled, pc.lunch_break_start, pc.lunch_break_end
      into v_lunch_break_enabled, v_lunch_break_start, v_lunch_break_end
    from public.policy_configurations pc
    where pc.branch_id is null
    limit 1;
  end if;

  if v_lunch_break_enabled
     and v_requested_start_local < v_lunch_break_end
     and v_requested_end_local > v_lunch_break_start
  then
    return;
  end if;

  return query
  select sp.id, sp.display_name, sp.profile_photo_url
  from public.staff_profiles sp
  where sp.branch_id = p_branch_id
    and sp.role = p_role
    and sp.is_active
    and (p_staff_id is null or sp.id = p_staff_id)
    and not exists (
      select 1
      from public.bookings bk
      where bk.assigned_staff_id = sp.id
        and bk.status in ('Pending', 'In Progress', 'Completed', 'Paid')
        and (p_exclude_booking_id is null or bk.id <> p_exclude_booking_id)
        and bk.scheduled_start < p_requested_end
        and bk.scheduled_end > p_requested_start
    )
    and not exists (
      select 1
      from public.staff_unavailability_blocks sub
      where sub.staff_id = sp.id
        and sub.status = 'approved'
        and sub.start_time < p_requested_end
        and sub.end_time > p_requested_start
    )
  order by sp.display_name, sp.id;
end;
$$;


-- =============================================================================
-- 20260804093_m01_staff_unavailability_blocks_leave_type.sql
-- =============================================================================
-- Monthly schedule addendum: "days off" remastered into typed leave so the
-- new Monthly Schedule calendar can distinguish Rest Day (fixed, set only by
-- Admin/Supervisor/Superadmin on a staff member's behalf) from Vacation
-- Leave / Sick Leave (self-requestable, same approval flow as today) and the
-- pre-existing free-form "Other" entries. Reuses staff_unavailability_blocks
-- end-to-end - no new table; every existing approval/quick-action/full-day
-- mechanism (and get_staff_availability()'s Check 3) already works
-- unmodified against any leave_type.

create type public.unavailability_leave_type as enum (
  'Rest Day',
  'Vacation Leave',
  'Sick Leave',
  'Other'
);

alter table public.staff_unavailability_blocks
  add column leave_type public.unavailability_leave_type not null default 'Other';

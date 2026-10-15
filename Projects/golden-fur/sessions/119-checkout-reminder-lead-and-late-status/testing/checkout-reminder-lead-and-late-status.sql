-- Reference copy. Source of truth:
--   golden-fur/supabase/migrations/20261015266_custom_booking_status_add_late.sql
--   golden-fur/supabase/migrations/20261015267_custom_policy_configurations_no_show_threshold.sql
--   golden-fur/supabase/migrations/20261015268_custom_booking_status_late_rpcs.sql

-- ===== supabase/migrations/20261015266_custom_booking_status_add_late.sql =====
-- Custom change (Late booking status): a booking whose start time has passed
-- but whose customer may still show up. Sits between 'Pending' and
-- 'No-show' - a Pending booking flips to 'Late' once scheduled_start passes,
-- and only to 'No-show' after the admin-configured threshold
-- (policy_configurations.no_show_after_minutes / no_show_at_closing,
-- 20261015267). Applied lazily on read by applyLateAndNoShowTransition in
-- booking.service.ts, same as No-show always was. A Late booking is still
-- "not started": it can be started, checked in, rescheduled or cancelled and
-- still holds its slot (20261015268).
--
-- Must be its own migration: Postgres forbids using a value added by ADD
-- VALUE in the same transaction it was added in - same isolation as
-- 20261008254's notification_event_type addition.

alter type public.booking_status add value 'Late' after 'Pending';

-- ===== supabase/migrations/20261015267_custom_policy_configurations_no_show_threshold.sql =====
-- Custom change (Late booking status): how long a booking stays 'Late'
-- (start time passed, still startable) before it becomes 'No-show'.
-- Previously a Pending booking became No-show the instant scheduled_start
-- passed, with no grace period.
--
-- Two knobs, set together from Config > Policy Configuration's "Mark as
-- no-show after" dropdown (15 min / 30 min / 1 h / 2 h / End of operating
-- hours):
--   * no_show_after_minutes - minutes after scheduled_start. Default 30.
--   * no_show_at_closing    - when true, wait until the branch's closing
--     time (branches.operating_hours, branch timezone) on the booking's day
--     instead; no_show_after_minutes is then ignored.
--
-- Reuses policy_configurations' default-row + per-branch-override pattern
-- (...037). Resolved by resolveEffectivePolicy in staffPicker.service.ts; read
-- by applyLateAndNoShowTransition in booking.service.ts.

alter table public.policy_configurations
  add column no_show_after_minutes integer not null default 30
    check (no_show_after_minutes >= 0),
  add column no_show_at_closing boolean not null default false;

comment on column public.policy_configurations.no_show_after_minutes is
  'Minutes after scheduled_start that a booking stays Late before becoming No-show. Ignored when no_show_at_closing is true. Resolved by resolveEffectivePolicy in staffPicker.service.ts.';

comment on column public.policy_configurations.no_show_at_closing is
  'When true, a Late booking becomes No-show at the branch''s closing time on the booking''s day (branches.operating_hours, branch timezone) instead of no_show_after_minutes after its start.';

-- ===== supabase/migrations/20261015268_custom_booking_status_late_rpcs.sql =====
-- Custom change (Late booking status, 20261015266): a 'Late' booking (start
-- time passed, customer may still show up) still holds its slot exactly like
-- a 'Pending' one, until it becomes 'No-show'.
--
-- 1) get_staff_availability(): Check 2's status list gains 'Late'. Body is
--    20260908179's verbatim otherwise (no other migration redefines it
--    since), and the signature is unchanged, so this is a plain
--    `create or replace` that keeps 20260904172's revoke/grant state.
-- 2) bookings_staff_active_idx: the partial index Check 2 relies on is
--    recreated with the same predicate (20260803083) plus 'Late'.

drop index if exists public.bookings_staff_active_idx;

create index bookings_staff_active_idx
  on public.bookings(assigned_staff_id, scheduled_start)
  where status in ('Pending', 'Late', 'In Progress', 'Completed');

create or replace function public.get_staff_availability(
  p_roles public.staff_role[],
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
  v_max_concurrent integer;
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

  -- Staff concurrency limit: same branch-row-wins-else-system-default
  -- precedence as the lunch break above. Defaults to 1 (one pet at a time)
  -- when no policy row exists at all.
  select pc.max_concurrent_bookings_per_staff
    into v_max_concurrent
  from public.policy_configurations pc
  where pc.branch_id = p_branch_id
  limit 1;

  if not found then
    select pc.max_concurrent_bookings_per_staff
      into v_max_concurrent
    from public.policy_configurations pc
    where pc.branch_id is null
    limit 1;
  end if;

  v_max_concurrent := coalesce(v_max_concurrent, 1);

  return query
  select sp.id, sp.display_name, sp.profile_photo_url
  from public.staff_profiles sp
  where sp.branch_id = p_branch_id
    and sp.role = any(p_roles)
    and sp.is_active
    and (p_staff_id is null or sp.id = p_staff_id)
    -- Check 2: fewer than max_concurrent_bookings_per_staff overlapping
    -- bookings that still hold a real slot - Pending/Late/In Progress/Completed,
    -- EXCEPT a down-payment-required booking that hasn't paid any of its down
    -- payment yet (down-payment slot gate, 20260829146/147): that one sits
    -- Pending without reserving anything until payment_status leaves
    -- 'Pending'. Mirrors the downpayment_required/payment_status filter
    -- grooming.service.ts and consultation.service.ts already apply to their
    -- queues.
    and (
      select count(*)
      from public.bookings bk
      where bk.assigned_staff_id = sp.id
        and bk.status in ('Pending', 'Late', 'In Progress', 'Completed')
        and not (bk.downpayment_required and bk.payment_status = 'Pending')
        and (p_exclude_booking_id is null or bk.id <> p_exclude_booking_id)
        and bk.scheduled_start < p_requested_end
        and bk.scheduled_end > p_requested_start
    ) < v_max_concurrent
    -- Check 3: no overlapping APPROVED unavailability block (#49 AC-3);
    -- pending/denied rows are ignored per the Jul 11, 2026 redesign.
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

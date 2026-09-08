-- Reference copies of the migrations added in session 76.
-- Source of truth (never edit these copies):
--   golden-fur/supabase/migrations/20260908178_m03_policy_configurations_max_concurrent_staff.sql
--   golden-fur/supabase/migrations/20260908179_m03_get_staff_availability_staff_capacity.sql
--   golden-fur/supabase/migrations/20260908180_m13_backfill_branch_availability.sql
--
-- 178 + 179: configurable staff concurrency (new
--   policy_configurations.max_concurrent_bookings_per_staff column, default 1,
--   CHECK >= 1; get_staff_availability() Check 2 changes from a hardcoded
--   capacity of 1 to "< max_concurrent_bookings_per_staff", resolved with the
--   same branch-row-wins-else-system-default precedence used for the lunch
--   break).
-- 180: data recovery. On the dev DB, service_branch_availability /
--   service_type_branch_availability were empty (the m13 seed only runs on
--   `db reset`, not `db push`), so listServices({ branchId }) returned nothing
--   and the customer booking flow showed "No <category> services available at
--   this branch". Idempotent backfill; ON CONFLICT DO NOTHING preserves any
--   deliberate is_available = false opt-out and makes it a no-op on a fresh
--   reset. Already applied directly to the dev Supabase project.
--
-- Handy checks (run against the target DB):
--
--   -- concurrency knob: system default row + any branch overrides
--   select branch_id, max_concurrent_bookings_per_staff
--   from public.policy_configurations
--   order by branch_id nulls first;
--
--   -- availability coverage: should be 0 after 180 for every active service
--   select b.name as branch, count(*) as active_services_without_availability
--   from public.branches b
--   cross join public.services s
--   left join public.service_branch_availability sba
--     on sba.service_id = s.id and sba.branch_id = b.id
--   where s.is_active and sba.service_id is null
--   group by b.name;
--
--   select b.name as branch, count(*) as service_types_without_availability
--   from public.branches b
--   cross join public.service_types st
--   left join public.service_type_branch_availability stba
--     on stba.service_type_id = st.id and stba.branch_id = b.id
--   where stba.service_type_id is null
--   group by b.name;

-- ===========================================================================
-- 20260908178_m03_policy_configurations_max_concurrent_staff.sql
-- ===========================================================================

alter table public.policy_configurations
  add column max_concurrent_bookings_per_staff integer not null default 1
    check (max_concurrent_bookings_per_staff >= 1);

comment on column public.policy_configurations.max_concurrent_bookings_per_staff is
  'How many overlapping Grooming/Veterinary bookings one staff member may be assigned at once. 1 = one pet at a time (default). Read by get_staff_availability() and confirmCapacityAfterInsert.';

-- ===========================================================================
-- 20260908179_m03_get_staff_availability_staff_capacity.sql
-- ===========================================================================
-- Signature UNCHANGED from 20260904169, so this is a plain create-or-replace
-- (keeps the revoke/grant state from 169 + 172). Body is 169's verbatim
-- except: new v_max_concurrent read (branch-row-wins-else-system-default,
-- mirroring resolveEffectivePolicy) and Check 2's `not exists (...)` becomes
-- `(select count(*) ...) < v_max_concurrent`.

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

  -- Check 1: within branch operating hours for that day.
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

  -- Lunch break check: branch row wins whole-row, else the system-wide default.
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
  -- precedence as the lunch break above. Defaults to 1 when no policy row
  -- exists at all.
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
    -- bookings that still hold a real slot (Pending/In Progress/Completed,
    -- minus an unpaid down-payment-required booking).
    and (
      select count(*)
      from public.bookings bk
      where bk.assigned_staff_id = sp.id
        and bk.status in ('Pending', 'In Progress', 'Completed')
        and not (bk.downpayment_required and bk.payment_status = 'Pending')
        and (p_exclude_booking_id is null or bk.id <> p_exclude_booking_id)
        and bk.scheduled_start < p_requested_end
        and bk.scheduled_end > p_requested_start
    ) < v_max_concurrent
    -- Check 3: no overlapping APPROVED unavailability block.
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

-- ===========================================================================
-- 20260908180_m13_backfill_branch_availability.sql
-- ===========================================================================

insert into public.service_branch_availability (service_id, branch_id, is_available)
select s.id, b.id, true
from public.services as s
cross join public.branches as b
where s.is_active = true
on conflict (service_id, branch_id) do nothing;

insert into public.service_type_branch_availability (service_type_id, branch_id, is_available)
select st.id, b.id, true
from public.service_types as st
cross join public.branches as b
on conflict (service_type_id, branch_id) do nothing;

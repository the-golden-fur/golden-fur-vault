-- Reference copy of the 3 migrations added in session 68.
-- Canonical files:
--   golden-fur/supabase/migrations/20260904168_custom_service_types_eligible_staff_roles.sql
--   golden-fur/supabase/migrations/20260904169_m03_get_staff_availability_multi_roles.sql
--   golden-fur/supabase/migrations/20260904170_custom_drop_policy_staff_picker_toggle.sql
--
-- NOTE: all three are now applied to the linked Supabase project (via
-- `npm run supabase:push` - see testing.md's Open items).

-- ============================================================================
-- 20260904168_custom_service_types_eligible_staff_roles.sql
-- ============================================================================

-- Custom change: Staff Picker role eligibility becomes per-service-type
-- configurable (admin backlog: "staff picker doesn't specify what roles").
-- Adds an array column alongside the existing staff_picker_enabled toggle -
-- WHICH roles are eligible, on top of WHETHER the picker is offered at all.
-- Precedent for a Postgres array-of-enum column in this schema:
-- p_branch_ids uuid[] (20260902159_m10_policy_credit_expiry_mode.sql).
--
-- Backfills the 4 seeded rows to match today's hardcoded
-- CATEGORY_STAFF_ROLE map in staffPicker.service.ts/availability.service.ts
-- (Grooming -> Groomer, Veterinary -> Veterinarian) so existing behavior is
-- unchanged until an admin edits a row. Hotel/Daycare stay {} - staff picker
-- is off for both today; an admin fills roles in via the new admin-page
-- multi-select if either is ever turned on.
--
-- Companion migrations: 20260904169 makes get_staff_availability() accept
-- multiple roles; 20260904170 drops the now-redundant
-- policy_configurations.staff_picker_enabled_grooming/_veterinary columns,
-- since service_types.staff_picker_enabled becomes the one live gate for
-- every category (previously it sat unused - only the policy toggle was
-- actually consulted).

alter table public.service_types
  add column eligible_staff_roles public.staff_role[] not null default '{}';

update public.service_types set eligible_staff_roles = '{Groomer}' where key = 'Grooming';
update public.service_types set eligible_staff_roles = '{Veterinarian}' where key = 'Veterinary';

-- ============================================================================
-- 20260904169_m03_get_staff_availability_multi_roles.sql
-- ============================================================================

-- Staff-role multi-select on Service Types, 2/3.
--
-- WHY: get_staff_availability() took a single p_role, matching the old
-- hardcoded CATEGORY_STAFF_ROLE map (Grooming -> Groomer, Veterinary ->
-- Veterinarian) in staffPicker.service.ts/availability.service.ts. Those
-- eligible roles are now a real, admin-editable array column
-- (service_types.eligible_staff_roles, added 20260904168), so the RPC needs
-- to match against a set of roles, not one.
--
-- The parameter list changes (p_role staff_role -> p_roles staff_role[]), so
-- a plain `create or replace` would create a stale second overload instead
-- of replacing the original - drop the exact old signature first.
--
-- Body is 20260901156's verbatim except: the parameter itself, and Check 3's
-- `sp.role = p_role` -> `sp.role = any(p_roles)`. Cautionary note carried
-- over from every prior redefinition: this function has repeatedly been
-- clobbered by parallel same-day migrations branching off a stale copy -
-- confirm no other migration redefines it between 20260901156 and here
-- before basing a future change on this one.

drop function public.get_staff_availability(
  public.staff_role, uuid, timestamptz, timestamptz, uuid, uuid
);

create function public.get_staff_availability(
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
    and sp.role = any(p_roles)
    and sp.is_active
    and (p_staff_id is null or sp.id = p_staff_id)
    -- Check 2: no overlapping booking that still holds a real slot -
    -- Pending/In Progress/Completed, EXCEPT a down-payment-required booking
    -- that hasn't paid any of its down payment yet (down-payment slot gate,
    -- 20260829146/147): that one sits Pending without reserving anything
    -- until payment_status leaves 'Pending'. Mirrors the
    -- downpayment_required/payment_status filter grooming.service.ts and
    -- consultation.service.ts already apply to their queues.
    and not exists (
      select 1
      from public.bookings bk
      where bk.assigned_staff_id = sp.id
        and bk.status in ('Pending', 'In Progress', 'Completed')
        and not (bk.downpayment_required and bk.payment_status = 'Pending')
        and (p_exclude_booking_id is null or bk.id <> p_exclude_booking_id)
        and bk.scheduled_start < p_requested_end
        and bk.scheduled_end > p_requested_start
    )
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

-- ============================================================================
-- 20260904170_custom_drop_policy_staff_picker_toggle.sql
-- ============================================================================

-- Staff-role multi-select on Service Types, 3/3.
--
-- WHY: policy_configurations.staff_picker_enabled_grooming/_veterinary
-- (20260718037) duplicated service_types.staff_picker_enabled for exactly
-- two categories, and until this change was actually the ONLY one of the
-- two ever consulted by isStaffPickerEnabled() - service_types'
-- staff_picker_enabled sat unread. Now that service_types is the real,
-- admin-editable source of truth for every category (including its new
-- eligible_staff_roles column, 20260904168), this pair of booleans is dead
-- weight - one config surface (Admin Settings > Service Types) beats two
-- disagreeing ones (Admin Settings > Policies vs. Service Types).

alter table public.policy_configurations
  drop column staff_picker_enabled_grooming,
  drop column staff_picker_enabled_veterinary;

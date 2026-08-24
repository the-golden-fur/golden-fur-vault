-- Issue #49 Verification SQL — get_staff_availability() set-returning RPC
-- Paste the WHOLE file into Supabase Studio -> SQL Editor and Run.
-- Creates issue49-* test data, checks every AC, returns one pass/fail table.
-- The CLEANUP section at the bottom is commented out - run it afterwards.

-- ---------------------------------------------------------------------------
-- Setup: two Groomers at the first branch, one Confirmed + one Cancelled
-- booking for groomer B, and approved/pending/denied blocks for groomer A.
-- Idempotent: re-running reuses the same issue49-* rows.
-- ---------------------------------------------------------------------------

do $$
declare
  v_branch_id uuid;
  v_tz text;
  v_customer_id uuid;
  v_pet_id uuid;
  v_service_id uuid;
  v_groomer_a uuid;
  v_groomer_b uuid;
  v_day date;
  v_open timestamptz;
  i int;
  v_email text;
  v_user uuid;
begin
  select id, timezone into v_branch_id, v_tz
  from public.branches order by created_at limit 1;

  if v_branch_id is null then
    raise exception 'No branches found - seed data (#38) must be applied first';
  end if;

  -- Next Monday, 10:00 branch-local (assumes seeded operating hours cover
  -- Monday 10:00-12:00; adjust v_open below if your branch opens later).
  v_day := (current_date + ((8 - extract(isodow from current_date))::int % 7 + 7));
  v_open := (v_day::text || ' 10:00')::timestamp at time zone v_tz;

  -- Two test groomers (auth.users + staff_profiles)
  for i in 1..2 loop
    v_email := 'issue49-groomer-' || (case i when 1 then 'a' else 'b' end) || '@example.com';

    select id into v_user from auth.users where email = v_email;

    if v_user is null then
      insert into auth.users (
        id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
      ) values (
        gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', v_email,
        crypt('password123', gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Issue 49 Groomer"}'::jsonb, now(), now()
      ) returning id into v_user;
    end if;

    insert into public.staff_profiles (
      id, branch_id, role, username, registered_email, display_name
    ) values (
      v_user, v_branch_id, 'Groomer',
      'issue49-groomer-' || (case i when 1 then 'a' else 'b' end),
      v_email,
      'Issue49 Groomer ' || (case i when 1 then 'A' else 'B' end)
    ) on conflict (id) do update set branch_id = excluded.branch_id, role = 'Groomer';

    if i = 1 then v_groomer_a := v_user; else v_groomer_b := v_user; end if;
  end loop;

  -- A customer + pet + Grooming service for the conflicting bookings
  select id into v_customer_id from public.customer_profiles limit 1;
  if v_customer_id is null then
    raise exception 'No customer_profiles found - seed data (#38) must be applied first';
  end if;

  select id into v_pet_id from public.pets where customer_id = v_customer_id limit 1;
  if v_pet_id is null then
    insert into public.pets (customer_id, name, species, weight_class, coat_type)
    values (v_customer_id, 'Issue49 Pet', 'Dog', 'S', 'SC')
    returning id into v_pet_id;
  end if;

  select id into v_service_id from public.services where category = 'Grooming' limit 1;
  if v_service_id is null then
    raise exception 'No Grooming service found - Epic A seed (#44) must be applied first';
  end if;

  -- Reset any previous issue49 bookings/blocks, then create fresh ones
  delete from public.bookings
  where assigned_staff_id in (v_groomer_a, v_groomer_b)
    and special_instructions = 'issue49-test';
  delete from public.staff_unavailability_blocks
  where staff_id in (v_groomer_a, v_groomer_b) and reason like 'issue49%';

  -- Groomer B: Confirmed booking 10:00-11:00 (excludes B in that window, AC-2)
  insert into public.bookings (
    customer_id, pet_id, branch_id, service_category, service_id,
    scheduled_start, scheduled_end, assigned_staff_id, status,
    total_price, payment_confirmed, special_instructions
  ) values (
    v_customer_id, v_pet_id, v_branch_id, 'Grooming', v_service_id,
    v_open, v_open + interval '1 hour', v_groomer_b, 'Confirmed',
    100, true, 'issue49-test'
  );

  -- Groomer B: Cancelled booking 11:00-12:00 (must NOT exclude, AC-2)
  insert into public.bookings (
    customer_id, pet_id, branch_id, service_category, service_id,
    scheduled_start, scheduled_end, assigned_staff_id, status,
    total_price, payment_confirmed, special_instructions
  ) values (
    v_customer_id, v_pet_id, v_branch_id, 'Grooming', v_service_id,
    v_open + interval '1 hour', v_open + interval '2 hours', v_groomer_b, 'Cancelled',
    100, true, 'issue49-test'
  );

  -- Groomer A: approved block 11:00-12:00 (excludes A there, AC-3),
  -- pending + denied blocks 10:00-11:00 (must NOT exclude, AC-3).
  -- Note: the ...019 BEFORE INSERT trigger assigns status itself - a
  -- self-created custom-range row always lands as 'pending'. So the
  -- 'approved' row is created on-behalf-of (created_by = groomer B, which
  -- the trigger auto-approves) and the 'denied' row is UPDATEd after insert
  -- (the trigger only fires on INSERT).
  insert into public.staff_unavailability_blocks
    (staff_id, start_time, end_time, reason, created_by)
  values
    (v_groomer_a, v_open + interval '1 hour', v_open + interval '2 hours',
     'issue49-approved', v_groomer_b),
    (v_groomer_a, v_open, v_open + interval '1 hour',
     'issue49-pending', v_groomer_a),
    (v_groomer_a, v_open, v_open + interval '1 hour',
     'issue49-denied', v_groomer_a);

  update public.staff_unavailability_blocks
  set status = 'denied'
  where reason = 'issue49-denied';
end $$;

-- ---------------------------------------------------------------------------
-- Checks: every row must show pass = true
-- ---------------------------------------------------------------------------

with env as (
  select
    b.id as branch_id,
    b.timezone as tz,
    (select id from public.staff_profiles where username = 'issue49-groomer-a') as groomer_a,
    (select id from public.staff_profiles where username = 'issue49-groomer-b') as groomer_b,
    (((current_date + ((8 - extract(isodow from current_date))::int % 7 + 7))::text || ' 10:00')::timestamp
       at time zone b.timezone) as t1000
  from public.branches b
  order by b.created_at limit 1
)
select 'ac1_both_groomers_eligible_in_clear_window' as check_name,
  -- 10:00-11:00: A has only pending/denied blocks (ignored); B has the
  -- Confirmed booking, so "everyone eligible" is checked at 11:00-12:00 for B
  -- and 10:00-11:00 for A -> here: A eligible at 10:00-11:00.
  exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id, env.t1000, env.t1000 + interval '1 hour'
    ) r where r.staff_id = env.groomer_a
  ) as pass
union all
select 'ac2_groomer_b_excluded_by_confirmed_booking',
  not exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id, env.t1000, env.t1000 + interval '1 hour'
    ) r where r.staff_id = env.groomer_b
  )
union all
select 'ac2_cancelled_booking_does_not_exclude',
  exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id,
      env.t1000 + interval '1 hour', env.t1000 + interval '2 hours'
    ) r where r.staff_id = env.groomer_b
  )
union all
select 'ac3_approved_block_excludes_groomer_a',
  not exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id,
      env.t1000 + interval '1 hour', env.t1000 + interval '2 hours'
    ) r where r.staff_id = env.groomer_a
  )
union all
select 'ac3_pending_or_denied_block_does_not_exclude',
  exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id, env.t1000, env.t1000 + interval '1 hour'
    ) r where r.staff_id = env.groomer_a
  )
union all
select 'ac4_outside_operating_hours_empty_set',
  not exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id,
      env.t1000 - interval '8 hours', env.t1000 - interval '7 hours'
    ) r
  )
union all
select 'ac5_specific_staff_pass_returns_exactly_one',
  (select count(*) from env, public.get_staff_availability(
     'Groomer', env.branch_id, env.t1000, env.t1000 + interval '1 hour',
     (select groomer_a from env)
   ) r) = 1
union all
select 'ac5_specific_staff_fail_returns_empty',
  not exists (
    select 1 from env, public.get_staff_availability(
      'Groomer', env.branch_id, env.t1000, env.t1000 + interval '1 hour',
      (select groomer_b from env)
    ) r
  )
union all
select 'old_boolean_overload_dropped',
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_staff_availability'
      and p.prorettype = 'boolean'::regtype
  );

-- ---------------------------------------------------------------------------
-- CLEANUP (run after reviewing the results - select the lines, Ctrl+/, Run)
-- ---------------------------------------------------------------------------
-- delete from public.bookings where special_instructions = 'issue49-test';
-- delete from public.staff_unavailability_blocks where reason like 'issue49%';
-- delete from public.staff_profiles where username like 'issue49-%';
-- delete from auth.users where email like 'issue49-%';

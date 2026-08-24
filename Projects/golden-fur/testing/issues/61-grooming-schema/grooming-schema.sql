-- Issue #61 Verification SQL — grooming schema
-- Paste the WHOLE file (down to the EXPECTED-ERROR TEST section) into
-- Supabase Studio -> SQL Editor and Run. Every row must show pass = true.

with checks as (
  -- 1. Enum -------------------------------------------------------------------
  select 'grooming_status enum has exactly Waiting/In Progress/Completed' as check_name,
    (select array_agg(enumlabel order by enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'grooming_status')
    = array['Waiting','In Progress','Completed'] as pass

  -- 2. Table + columns ----------------------------------------------------------
  union all
  select 'grooming_sessions exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'grooming_sessions'
       and column_name in (
         'id','booking_id','assigned_groomer_id','status','queue_position',
         'started_at','completed_at','created_at','updated_at')) = 9

  union all
  select 'grooming_sessions.status uses grooming_status and defaults to Waiting',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'grooming_sessions'
        and column_name = 'status' and udt_name = 'grooming_status'
        and column_default like '%Waiting%'
    )

  union all
  select 'grooming_sessions.booking_id is UNIQUE',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.grooming_sessions'::regclass and contype = 'u'
    )

  union all
  select 'grooming_sessions.booking_id references bookings',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.grooming_sessions'::regclass and contype = 'f'
        and confrelid = 'public.bookings'::regclass
    )

  union all
  select 'grooming_sessions.assigned_groomer_id references staff_profiles',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.grooming_sessions'::regclass and contype = 'f'
        and confrelid = 'public.staff_profiles'::regclass
    )

  union all
  select 'groomer index exists on assigned_groomer_id',
    exists (
      select 1 from pg_indexes
      where schemaname = 'public' and tablename = 'grooming_sessions'
        and indexname = 'grooming_sessions_groomer_idx'
    )

  -- 3. RLS ----------------------------------------------------------------------
  union all
  select 'RLS enabled on grooming_sessions',
    (select relrowsecurity from pg_class
     where oid = 'public.grooming_sessions'::regclass)

  union all
  select 'grooming_sessions has 6 policies (2 groomer + 2 admin/supervisor + 2 superadmin)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'grooming_sessions') = 6

  union all
  select 'no INSERT policy exists (writes go through the service-role client)',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'grooming_sessions'
        and cmd = 'INSERT'
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- EXPECTED-ERROR TEST (AC-4) - run individually; must FAIL
-- ---------------------------------------------------------------------------
-- Needs one existing grooming_sessions row (create one via #64's Postman
-- collection first, or any confirmed Grooming booking's queue listing).
-- Expected: ERROR ... violates unique constraint "grooming_sessions_booking_id_key" (or similar)
-- insert into public.grooming_sessions (booking_id, assigned_groomer_id)
-- select booking_id, assigned_groomer_id from public.grooming_sessions limit 1;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-3) - uncomment the block and fill the UUIDs from
-- Authentication -> Users (two Groomers at the SAME branch, one Admin or
-- Supervisor at that same branch). Run the whole block at once; read the
-- NOTICEs in the Results pane.
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   groomer_a uuid := '<GROOMER-A-USER-UUID>';
--   groomer_b uuid := '<GROOMER-B-USER-UUID>';
--   manager_user uuid := '<ADMIN-OR-SUPERVISOR-USER-UUID>';
--   v_booking uuid;
--   v_session uuid;
--   v_count int;
-- begin
--   -- Seed a Confirmed Grooming booking assigned to Groomer A, then a session
--   -- (as service role, bypasses RLS).
--   select b.id into v_booking
--   from public.bookings b
--   where b.assigned_staff_id = groomer_a and b.service_category = 'Grooming'
--   limit 1;
--
--   if v_booking is null then
--     raise exception 'No Confirmed Grooming booking assigned to groomer_a - create one via the booking API first';
--   end if;
--
--   insert into public.grooming_sessions (booking_id, assigned_groomer_id)
--   values (v_booking, groomer_a)
--   on conflict (booking_id) do nothing
--   returning id into v_session;
--
--   if v_session is null then
--     select id into v_session from public.grooming_sessions where booking_id = v_booking;
--   end if;
--
--   -- Impersonate Groomer B: must NOT see Groomer A's session
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', groomer_b, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.grooming_sessions where id = v_session;
--   reset role;
--   if v_count = 0 then
--     raise notice 'PASS: groomer B cannot see groomer A''s session';
--   else
--     raise exception 'FAIL: cross-groomer read leaked';
--   end if;
--
--   -- Impersonate Groomer A: MUST see own session
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', groomer_a, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.grooming_sessions where id = v_session;
--   reset role;
--   if v_count = 1 then
--     raise notice 'PASS: groomer A can see their own session';
--   else
--     raise exception 'FAIL: groomer self-read missing';
--   end if;
--
--   -- Impersonate Admin/Supervisor at the same branch: MUST see it
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', manager_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.grooming_sessions where id = v_session;
--   reset role;
--   if v_count = 1 then
--     raise notice 'PASS: Admin/Supervisor can read all sessions at their branch';
--   else
--     raise exception 'FAIL: Admin/Supervisor branch-scoped read missing';
--   end if;
-- end $$;

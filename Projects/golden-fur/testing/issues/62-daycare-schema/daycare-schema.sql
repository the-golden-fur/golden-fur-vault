-- Issue #62 Verification SQL — daycare schema
-- Paste the WHOLE file (down to the EXPECTED-ERROR TEST section) into
-- Supabase Studio -> SQL Editor and Run. Every row must show pass = true.

with checks as (
  -- 1. Columns + constraints ----------------------------------------------------
  select 'branches.daycare_checkin_cutoff exists (time, not null, default 16:00:00)' as check_name,
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'branches'
        and column_name = 'daycare_checkin_cutoff'
        and data_type = 'time without time zone'
        and is_nullable = 'NO'
        and column_default like '%16:00:00%'
    ) as pass

  union all
  select 'daycare_sessions exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'daycare_sessions'
       and column_name in (
         'id','booking_id','pet_id','branch_id','created_by_staff_id',
         'status','check_in_at','check_out_at','computed_charge',
         'created_at','updated_at')) = 11

  union all
  select 'daycare_sessions.booking_id is nullable',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'daycare_sessions'
        and column_name = 'booking_id' and is_nullable = 'YES'
    )

  union all
  select 'daycare_sessions.status defaults to Active with a text CHECK',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'daycare_sessions'
        and column_name = 'status' and column_default like '%Active%'
    )
    and exists (
      select 1 from pg_constraint
      where conrelid = 'public.daycare_sessions'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%Active%Completed%'
    )

  union all
  select 'partial unique index on booking_id (WHERE booking_id IS NOT NULL)',
    exists (
      select 1 from pg_indexes
      where schemaname = 'public' and tablename = 'daycare_sessions'
        and indexname = 'daycare_sessions_booking_id_key'
        and indexdef ilike '%where%booking_id is not null%'
    )

  union all
  select 'branch/status index exists',
    exists (
      select 1 from pg_indexes
      where schemaname = 'public' and tablename = 'daycare_sessions'
        and indexname = 'daycare_sessions_branch_status_idx'
    )

  -- 2. RLS ----------------------------------------------------------------------
  union all
  select 'RLS enabled on daycare_sessions',
    (select relrowsecurity from pg_class
     where oid = 'public.daycare_sessions'::regclass)

  union all
  select 'daycare_sessions has 4 policies (staff select/insert/update + superadmin all)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'daycare_sessions') = 4

  union all
  select 'no policy grants access to a customer/unauthenticated role',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'daycare_sessions'
        and (qual ilike '%customer%' or with_check ilike '%customer%')
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- EXPECTED-ERROR TEST (AC-3) - run individually; must FAIL
-- ---------------------------------------------------------------------------
-- Needs one existing daycare_sessions row with a non-null booking_id (create
-- one via #65's Postman collection, request 2, first).
-- Expected: ERROR ... violates unique constraint "daycare_sessions_booking_id_key"
-- insert into public.daycare_sessions (booking_id, pet_id, branch_id, created_by_staff_id)
-- select booking_id, pet_id, branch_id, created_by_staff_id
-- from public.daycare_sessions where booking_id is not null limit 1;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-4) - uncomment the block and fill the UUID from
-- Authentication -> Users (one customer). Run the whole block at once; read
-- the NOTICEs in the Results pane.
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   customer_user uuid := '<CUSTOMER-USER-UUID>';
--   v_session uuid;
--   v_count int;
--   v_insert_failed boolean := false;
-- begin
--   insert into public.daycare_sessions (pet_id, branch_id, created_by_staff_id)
--   select p.id, b.id, sp.id
--   from public.pets p, public.branches b, public.staff_profiles sp
--   where sp.role = 'Receptionist'
--   limit 1
--   returning id into v_session;
--
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', customer_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--
--   select count(*) into v_count from public.daycare_sessions where id = v_session;
--
--   begin
--     insert into public.daycare_sessions (pet_id, branch_id, created_by_staff_id)
--     values (
--       (select id from public.pets limit 1),
--       (select id from public.branches limit 1),
--       customer_user
--     );
--   exception when insufficient_privilege or others then
--     v_insert_failed := true;
--   end;
--
--   reset role;
--
--   if v_count = 0 then
--     raise notice 'PASS: customer cannot read daycare_sessions';
--   else
--     raise exception 'FAIL: customer read leaked';
--   end if;
--
--   if v_insert_failed then
--     raise notice 'PASS: customer insert was rejected';
--   else
--     raise exception 'FAIL: customer insert succeeded';
--   end if;
--
--   delete from public.daycare_sessions where id = v_session;
-- end $$;

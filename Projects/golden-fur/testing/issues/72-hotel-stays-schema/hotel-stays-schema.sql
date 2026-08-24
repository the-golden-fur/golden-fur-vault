-- Issue #72 Verification SQL — hotel_stays schema
-- Paste the WHOLE first statement into Supabase Studio -> SQL Editor and
-- Run. Every row must show pass = true.

with checks as (
  select 'hotel_stays exists with all DB-Design columns' as check_name,
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'hotel_stays'
       and column_name in (
         'id','booking_id','pet_id','cage_id','status','check_in_at',
         'scheduled_check_out_date','actual_check_out_at','downpayment_amount',
         'extension_fee','notify_opt_in','created_by_staff_id',
         'created_at','updated_at')) = 14

  union all
  select 'hotel_stays.booking_id is UNIQUE',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.hotel_stays'::regclass and contype = 'u'
    )

  union all
  select 'hotel_stays.booking_id references bookings',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.hotel_stays'::regclass and contype = 'f'
        and confrelid = 'public.bookings'::regclass
    )

  union all
  select 'hotel_stays.cage_id references cages',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.hotel_stays'::regclass and contype = 'f'
        and confrelid = 'public.cages'::regclass
    )

  union all
  select 'hotel_stays.status defaults to Active',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'hotel_stays'
        and column_name = 'status' and column_default like '%Active%'
    )

  union all
  select 'hotel_stays.notify_opt_in defaults to false',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'hotel_stays'
        and column_name = 'notify_opt_in' and column_default = 'false'
    )

  union all
  select 'RLS enabled on hotel_stays',
    (select relrowsecurity from pg_class where oid = 'public.hotel_stays'::regclass)

  union all
  select 'hotel_stays has 5 policies (staff read/insert/update + superadmin all, no customer policy)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'hotel_stays') = 5
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- EXPECTED-ERROR TEST (AC-3) - run individually; must FAIL
-- ---------------------------------------------------------------------------
-- Needs one existing hotel_stays row (create one via #75's Postman collection).
-- Expected: ERROR ... violates unique constraint "hotel_stays_booking_id_key"
-- insert into public.hotel_stays
--   (booking_id, pet_id, cage_id, scheduled_check_out_date, downpayment_amount, created_by_staff_id)
-- select booking_id, pet_id, cage_id, scheduled_check_out_date, downpayment_amount, created_by_staff_id
-- from public.hotel_stays limit 1;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-4) - uncomment and fill the UUIDs (one Customer,
-- one Receptionist at the branch of an existing hotel_stays row).
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   customer_user uuid := '<CUSTOMER-USER-UUID>';
--   receptionist_user uuid := '<RECEPTIONIST-USER-UUID>';
--   v_stay uuid;
--   v_count int;
-- begin
--   select id into v_stay from public.hotel_stays limit 1;
--   if v_stay is null then
--     raise exception 'No hotel_stays row exists - create one via #75 first';
--   end if;
--
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', customer_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.hotel_stays where id = v_stay;
--   reset role;
--   if v_count = 0 then
--     raise notice 'PASS: customer cannot read hotel_stays';
--   else
--     raise exception 'FAIL: customer read hotel_stays';
--   end if;
--
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', receptionist_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.hotel_stays where id = v_stay;
--   reset role;
--   if v_count = 1 then
--     raise notice 'PASS: Receptionist at the same branch can read hotel_stays';
--   else
--     raise exception 'FAIL: Receptionist branch-scoped read missing';
--   end if;
-- end $$;

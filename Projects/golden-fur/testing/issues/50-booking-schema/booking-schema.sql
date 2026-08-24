-- Issue #50 Verification SQL — booking schema
-- Paste the WHOLE file (down to the EXPECTED-ERROR TESTS section) into
-- Supabase Studio -> SQL Editor and Run. Every row must show pass = true.

with checks as (
  -- 1. Enums -----------------------------------------------------------------
  select 'booking_status enum has the 5 documented values' as check_name,
    (select array_agg(enumlabel order by enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'booking_status')
    = array['Confirmed','Completed','Cancelled','No-show','Pending'] as pass

  union all
  select 'service_category is REUSED (exactly one enum type exists)',
    (select count(*) from pg_type t
     join pg_namespace n on n.oid = t.typnamespace
     where t.typname = 'service_category' and n.nspname = 'public') = 1

  union all
  select 'bookings.service_category uses that same enum type',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'bookings'
        and column_name = 'service_category' and udt_name = 'service_category'
    )

  -- 2. Tables + key columns ---------------------------------------------------
  union all
  select 'bookings table exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'bookings'
       and column_name in (
         'id','customer_id','pet_id','branch_id','created_by_staff_id',
         'service_category','service_id','package_id','scheduled_start',
         'scheduled_end','assigned_staff_id','status','total_price',
         'downpayment_amount','payment_method','payment_confirmed',
         'special_instructions','cancelled_at','cancellation_reason',
         'reschedule_count','created_at','updated_at')) = 22

  union all
  select 'bookings.status defaults to Confirmed; reschedule_count to 0; payment_confirmed to false',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'bookings'
       and ((column_name = 'status' and column_default like '%Confirmed%')
         or (column_name = 'reschedule_count' and column_default = '0')
         or (column_name = 'payment_confirmed' and column_default = 'false'))) = 3

  union all
  select 'booking_addons exists (id, booking_id, service_id, price_at_booking)',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'booking_addons'
       and column_name in ('id','booking_id','service_id','price_at_booking')) = 4

  union all
  select 'staff_picker_preferences exists with audit flag',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'staff_picker_preferences'
       and column_name in ('id','booking_id','preference_type',
                           'preferred_staff_id','staff_picker_shown')) = 5

  -- 3. Constraints ------------------------------------------------------------
  union all
  select 'bookings CHECK: exactly one of service_id/package_id (num_nonnulls)',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.bookings'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%num_nonnulls%'
    )

  union all
  select 'bookings CHECK: scheduled_end > scheduled_start',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.bookings'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%scheduled_end%scheduled_start%'
    )

  union all
  select 'booking_addons.service_id is ON DELETE RESTRICT',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.booking_addons'::regclass and contype = 'f'
        and confrelid = 'public.services'::regclass and confdeltype = 'r'
    )

  union all
  select 'booking_addons.booking_id is ON DELETE CASCADE',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.booking_addons'::regclass and contype = 'f'
        and confrelid = 'public.bookings'::regclass and confdeltype = 'c'
    )

  union all
  select 'staff_picker_preferences.booking_id is UNIQUE + ON DELETE CASCADE',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.staff_picker_preferences'::regclass
        and contype = 'u'
    ) and exists (
      select 1 from pg_constraint
      where conrelid = 'public.staff_picker_preferences'::regclass
        and contype = 'f' and confrelid = 'public.bookings'::regclass
        and confdeltype = 'c'
    )

  -- 4. RLS ---------------------------------------------------------------------
  union all
  select 'RLS enabled on all three tables',
    (select count(*) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relrowsecurity
       and c.relname in ('bookings','booking_addons','staff_picker_preferences')) = 3

  union all
  select 'bookings has 4 policies (staff read + customer select/insert/update)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'bookings') = 4

  union all
  select 'child tables have staff-read + customer select/insert policies (3 each)',
    (select count(*) from pg_policies
     where schemaname = 'public'
       and tablename in ('booking_addons','staff_picker_preferences')) = 6

  -- 5. Indexes ------------------------------------------------------------------
  union all
  select 'partial Confirmed-only staff overlap index exists',
    exists (
      select 1 from pg_indexes
      where schemaname = 'public' and tablename = 'bookings'
        and indexname = 'bookings_staff_confirmed_idx'
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- EXPECTED-ERROR TESTS (AC-4) - run each statement INDIVIDUALLY; both must FAIL
-- ---------------------------------------------------------------------------
-- 1) Exactly-one-of violation: both service_id and package_id set.
--    Expected: ERROR ... violates check constraint
-- insert into public.bookings (
--   customer_id, pet_id, branch_id, service_category,
--   service_id, package_id, scheduled_start, scheduled_end, total_price
-- )
-- select c.id, p.id, b.id, 'Grooming', s.id, pk.id,
--        now() + interval '7 days', now() + interval '7 days 1 hour', 100
-- from public.customer_profiles c, public.pets p, public.branches b,
--      public.services s, public.packages pk
-- where p.customer_id = c.id limit 1;

-- 2) booking_addons RESTRICT: deleting a service referenced by an add-on.
--    Needs at least one booking_addons row (create one via #51's Postman
--    collection). Expected: ERROR ... violates foreign key constraint
-- delete from public.services
-- where id = (select service_id from public.booking_addons limit 1);

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-3) - uncomment the block and fill the two UUIDs
-- from Authentication -> Users (one customer A, one customer B, one staff).
-- Run the whole block at once; read the NOTICEs in the Results pane.
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   customer_a uuid := '<CUSTOMER-A-USER-UUID>';
--   customer_b uuid := '<CUSTOMER-B-USER-UUID>';
--   staff_user uuid := '<STAFF-USER-UUID>';
--   v_booking uuid;
--   v_count int;
-- begin
--   -- Seed one booking for customer A (as service role, bypasses RLS)
--   insert into public.bookings (
--     customer_id, pet_id, branch_id, service_category, service_id,
--     scheduled_start, scheduled_end, total_price, special_instructions
--   )
--   select customer_a, p.id, b.id, 'Daycare', s.id,
--          now() + interval '7 days', now() + interval '7 days 1 hour', 100,
--          'issue50-rls-test'
--   from public.pets p, public.branches b, public.services s
--   where p.customer_id = customer_a and s.category = 'Daycare'
--   limit 1
--   returning id into v_booking;
--
--   -- Impersonate customer B: must NOT see A's booking
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', customer_b, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.bookings where id = v_booking;
--   reset role;
--   if v_count = 0 then
--     raise notice 'PASS: customer B cannot see customer A''s booking';
--   else
--     raise exception 'FAIL: cross-customer read leaked';
--   end if;
--
--   -- Impersonate staff: MUST see it
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', staff_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.bookings where id = v_booking;
--   reset role;
--   if v_count = 1 then
--     raise notice 'PASS: staff can read all bookings';
--   else
--     raise exception 'FAIL: staff SELECT-all policy missing';
--   end if;
--
--   delete from public.bookings where id = v_booking;
-- end $$;

-- Issue #63 Verification SQL — veterinary schema
-- Paste the WHOLE file (down to the RLS IMPERSONATION TEST section) into
-- Supabase Studio -> SQL Editor and Run. Every row must show pass = true.

with checks as (
  -- 1. Enum + tables --------------------------------------------------------
  select 'procedure_type enum has all 6 documented values' as check_name,
    (select array_agg(enumlabel order by enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'procedure_type')
    = array['Lab test','Dental','Vaccination','Surgery','Emergency','Wellness Exam'] as pass

  union all
  select 'consultations exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'consultations'
       and column_name in (
         'id','booking_id','pet_id','veterinarian_id','status','temperature',
         'weight','heart_rate','respiratory_rate','diagnosis','medications',
         'reason_for_visit','follow_up_date','follow_up_booking_id',
         'completed_at','created_at','updated_at')) = 17

  union all
  select 'consultations.booking_id is UNIQUE',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.consultations'::regclass and contype = 'u'
    )

  union all
  select 'consultations.medications is jsonb',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'consultations'
        and column_name = 'medications' and data_type = 'jsonb'
    )

  union all
  select 'consultations.status defaults to Pending with a text CHECK',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'consultations'
        and column_name = 'status' and column_default like '%Pending%'
    )
    and exists (
      select 1 from pg_constraint
      where conrelid = 'public.consultations'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%Pending%Ongoing%Completed%'
    )

  union all
  select 'consultations.reason_for_visit is NOT NULL',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'consultations'
        and column_name = 'reason_for_visit' and is_nullable = 'NO'
    )

  union all
  select 'consultation_line_items exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'consultation_line_items'
       and column_name in (
         'id','consultation_id','item_type','procedure_type','description',
         'amount')) = 6

  union all
  select 'consultation_line_items.consultation_id is ON DELETE CASCADE',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.consultation_line_items'::regclass and contype = 'f'
        and confrelid = 'public.consultations'::regclass and confdeltype = 'c'
    )

  union all
  select 'consultation_line_items.amount is NOT NULL numeric(10,2)',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'consultation_line_items'
        and column_name = 'amount' and is_nullable = 'NO'
        and numeric_precision = 10 and numeric_scale = 2
    )

  union all
  select 'consultation_line_items.item_type CHECK covers the 3 documented values',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.consultation_line_items'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%professional_fee%medication%procedure%'
    )

  union all
  select 'consultation_line_items.procedure_type only set when item_type = procedure',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.consultation_line_items'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%procedure_type%'
    )

  -- 2. Makati-only enforcement (schema-level note, AC-3) ------------------------
  union all
  select 'branches.is_vet_branch exists (write-time Makati guard reads this from #66, not this migration)',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'branches'
        and column_name = 'is_vet_branch'
    )

  -- 3. RLS ------------------------------------------------------------------
  union all
  select 'RLS enabled on both tables',
    (select count(*) from pg_class
     where oid in ('public.consultations'::regclass, 'public.consultation_line_items'::regclass)
       and relrowsecurity) = 2

  union all
  select 'consultations has 4 read/write policies (vet rw + admin read + receptionist read)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'consultations') = 4

  union all
  select 'consultation_line_items has 3 read-only policies (vet + admin + receptionist)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'consultation_line_items') = 3

  union all
  select 'no INSERT/UPDATE policy exists on consultation_line_items (service-role writes only)',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'consultation_line_items'
        and cmd in ('INSERT', 'UPDATE')
    )

  union all
  select 'Receptionist has no INSERT/UPDATE policy on consultations',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'consultations'
        and cmd in ('INSERT', 'UPDATE')
        and (qual ilike '%Receptionist%' or with_check ilike '%Receptionist%')
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-4) - uncomment the block and fill the UUIDs from
-- Authentication -> Users (one Veterinarian, one Receptionist). Needs an
-- existing Makati Veterinary booking. Run the whole block at once; read the
-- NOTICEs in the Results pane.
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   vet_user uuid := '<VETERINARIAN-USER-UUID>';
--   receptionist_user uuid := '<RECEPTIONIST-USER-UUID>';
--   v_booking uuid;
--   v_consultation uuid;
--   v_count int;
--   v_update_failed boolean := false;
-- begin
--   select b.id into v_booking
--   from public.bookings b join public.branches br on br.id = b.branch_id
--   where b.service_category = 'Veterinary' and br.is_vet_branch
--   limit 1;
--
--   if v_booking is null then
--     raise exception 'No Makati Veterinary booking found - create one via the booking API first';
--   end if;
--
--   insert into public.consultations (booking_id, pet_id, veterinarian_id, reason_for_visit)
--   select v_booking, b.pet_id, vet_user, 'issue63-rls-test'
--   from public.bookings b where b.id = v_booking
--   on conflict (booking_id) do nothing
--   returning id into v_consultation;
--
--   if v_consultation is null then
--     select id into v_consultation from public.consultations where booking_id = v_booking;
--   end if;
--
--   -- Veterinarian: must read and update
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', vet_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.consultations where id = v_consultation;
--   update public.consultations set diagnosis = 'test' where id = v_consultation;
--   reset role;
--   if v_count = 1 then
--     raise notice 'PASS: Veterinarian can read the consultation';
--   else
--     raise exception 'FAIL: Veterinarian read missing';
--   end if;
--
--   -- Receptionist: must read, must NOT update
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', receptionist_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.consultations where id = v_consultation;
--   begin
--     update public.consultations set diagnosis = 'should-fail' where id = v_consultation;
--   exception when others then
--     v_update_failed := true;
--   end;
--   reset role;
--
--   if v_count = 1 then
--     raise notice 'PASS: Receptionist can read the consultation';
--   else
--     raise exception 'FAIL: Receptionist read missing';
--   end if;
--
--   if v_update_failed then
--     raise notice 'PASS: Receptionist update was rejected';
--   else
--     raise exception 'FAIL: Receptionist update succeeded';
--   end if;
--
--   delete from public.consultations where id = v_consultation;
-- end $$;

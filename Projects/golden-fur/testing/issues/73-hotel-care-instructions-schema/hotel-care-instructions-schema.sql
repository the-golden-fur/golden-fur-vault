-- Issue #73 Verification SQL — care instructions schema
-- Paste the WHOLE first statement into Supabase Studio -> SQL Editor and
-- Run. Every row must show pass = true.

with checks as (
  select 'care_feeding_instructions exists with all DB-Design columns' as check_name,
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'care_feeding_instructions'
       and column_name in (
         'id','hotel_stay_id','meal_time','food_type','quantity','special_instructions')) = 6

  union all
  select 'care_walking_instructions exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'care_walking_instructions'
       and column_name in (
         'id','hotel_stay_id','time_block','duration_minutes','notes')) = 5

  union all
  select 'care_medication_instructions exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'care_medication_instructions'
       and column_name in (
         'id','hotel_stay_id','medication_name','dose','scheduled_times',
         'administration_notes','source_prescription_note')) = 7

  union all
  select 'care_medication_instructions.scheduled_times is jsonb, not null, defaults to []',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'care_medication_instructions'
        and column_name = 'scheduled_times' and data_type = 'jsonb'
        and is_nullable = 'NO' and column_default like '%[]%'
    )

  union all
  select 'all three tables have RLS enabled',
    (select bool_and(relrowsecurity) from pg_class
     where oid in (
       'public.care_feeding_instructions'::regclass,
       'public.care_walking_instructions'::regclass,
       'public.care_medication_instructions'::regclass
     ))

  union all
  select 'Pet Assistant has SELECT-only access (no write policy names Pet Assistant)',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename in ('care_feeding_instructions','care_walking_instructions','care_medication_instructions')
        and cmd in ('INSERT','UPDATE','DELETE','ALL')
        and qual ilike '%Pet Assistant%'
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-3/AC-4) - uncomment and fill the UUIDs (one Pet
-- Assistant, one Receptionist, both at the branch of an existing
-- hotel_stays row - create one via #75's Postman collection first).
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   pet_assistant_user uuid := '<PET-ASSISTANT-USER-UUID>';
--   receptionist_user uuid := '<RECEPTIONIST-USER-UUID>';
--   v_stay uuid;
--   v_count int;
--   v_rows int;
-- begin
--   select id into v_stay from public.hotel_stays limit 1;
--   if v_stay is null then
--     raise exception 'No hotel_stays row exists - create one via #75 first';
--   end if;
--
--   insert into public.care_feeding_instructions (hotel_stay_id, meal_time, food_type, quantity)
--   values (v_stay, 'Morning', 'Dry kibble', '1 cup');
--
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', pet_assistant_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   select count(*) into v_count from public.care_feeding_instructions where hotel_stay_id = v_stay;
--   update public.care_feeding_instructions set food_type = 'Wet food' where hotel_stay_id = v_stay;
--   get diagnostics v_rows = row_count;
--   reset role;
--   if v_count > 0 and v_rows = 0 then
--     raise notice 'PASS: Pet Assistant can read but not update care instructions';
--   else
--     raise exception 'FAIL: Pet Assistant read=% update_rows=%', v_count, v_rows;
--   end if;
--
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', receptionist_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   update public.care_feeding_instructions set food_type = 'Wet food' where hotel_stay_id = v_stay;
--   get diagnostics v_rows = row_count;
--   reset role;
--   if v_rows > 0 then
--     raise notice 'PASS: Receptionist can update care instructions';
--   else
--     raise exception 'FAIL: Receptionist update did not apply';
--   end if;
-- end $$;

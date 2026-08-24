-- Issue #74 Verification SQL — care_log_entries schema
-- Paste the WHOLE first statement into Supabase Studio -> SQL Editor and
-- Run. Every row must show pass = true.

with checks as (
  select 'care_log_entries exists with all DB-Design columns' as check_name,
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'care_log_entries'
       and column_name in (
         'id','hotel_stay_id','care_type','scheduled_date','description',
         'completed_at','completed_by','created_at')) = 8

  union all
  select 'care_log_entries.completed_by references staff_profiles',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.care_log_entries'::regclass and contype = 'f'
        and confrelid = 'public.staff_profiles'::regclass
    )

  union all
  select 'partial index exists for uncompleted entries (backs #77 flagging)',
    exists (
      select 1 from pg_indexes
      where schemaname = 'public' and tablename = 'care_log_entries'
        and indexname = 'care_log_entries_uncompleted_idx'
    )

  union all
  select 'RLS enabled on care_log_entries',
    (select relrowsecurity from pg_class where oid = 'public.care_log_entries'::regclass)

  union all
  select 'no UPDATE/INSERT/DELETE policy exists for any role (writes are service-role only)',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'care_log_entries'
        and cmd in ('UPDATE','INSERT','DELETE','ALL')
    )

  union all
  select 'Pet Assistant has a SELECT policy scoped to their branch',
    exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'care_log_entries'
        and cmd = 'SELECT' and qual ilike '%Pet Assistant%'
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-3) - uncomment and fill the UUID (one Pet
-- Assistant at the branch of an existing care_log_entries row - generated
-- automatically by #75's check-in Postman request).
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   pet_assistant_user uuid := '<PET-ASSISTANT-USER-UUID>';
--   v_entry uuid;
--   v_rows int;
-- begin
--   select id into v_entry from public.care_log_entries limit 1;
--   if v_entry is null then
--     raise exception 'No care_log_entries row exists - run #75 check-in first';
--   end if;
--
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', pet_assistant_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   update public.care_log_entries set completed_at = now() where id = v_entry;
--   get diagnostics v_rows = row_count;
--   reset role;
--   if v_rows = 0 then
--     raise notice 'PASS: Pet Assistant cannot mark an entry complete via a raw UPDATE - only #76''s completion endpoint can';
--   else
--     raise exception 'FAIL: raw UPDATE succeeded, bypassing the completion RPC design';
--   end if;
-- end $$;

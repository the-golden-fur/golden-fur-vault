-- Issue #71 Verification SQL — cages schema
-- Paste the WHOLE first statement into Supabase Studio -> SQL Editor and
-- Run. Every row must show pass = true.

with checks as (
  -- 1. Enums --------------------------------------------------------------
  select 'cage_size enum has exactly S/M/L/XL' as check_name,
    (select array_agg(enumlabel order by enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'cage_size')
    = array['S','M','L','XL'] as pass

  union all
  select 'cage_status enum has exactly Available/Occupied/Reserved/Under Maintenance',
    (select array_agg(enumlabel order by enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'cage_status')
    = array['Available','Occupied','Reserved','Under Maintenance']

  -- 2. Table + columns ------------------------------------------------------
  union all
  select 'cages exists with all DB-Design columns',
    (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'cages'
       and column_name in (
         'id','branch_id','cage_label','size','status','created_at','updated_at')) = 7

  union all
  select 'cages.status uses cage_status and defaults to Available',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'cages'
        and column_name = 'status' and udt_name = 'cage_status'
        and column_default like '%Available%'
    )

  union all
  select 'cages.branch_id references branches',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.cages'::regclass and contype = 'f'
        and confrelid = 'public.branches'::regclass
    )

  union all
  select 'index exists on (branch_id, size, status)',
    exists (
      select 1 from pg_indexes
      where schemaname = 'public' and tablename = 'cages'
        and indexname = 'cages_branch_size_status_idx'
    )

  -- 3. RLS --------------------------------------------------------------------
  union all
  select 'RLS enabled on cages',
    (select relrowsecurity from pg_class where oid = 'public.cages'::regclass)

  union all
  select 'cages has 3 policies (staff read + admin update + superadmin all)',
    (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'cages') = 3

  union all
  select 'no staff INSERT policy exists (seed/service-role only)',
    not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'cages'
        and cmd = 'INSERT'
    )
)
select * from checks order by check_name;

-- ---------------------------------------------------------------------------
-- RLS IMPERSONATION TEST (AC-3) - uncomment and fill the UUIDs from
-- Authentication -> Users (one Receptionist, one Admin, same branch). Run
-- the whole block at once; read the NOTICEs in the Results pane.
-- ---------------------------------------------------------------------------
-- do $$
-- declare
--   receptionist_user uuid := '<RECEPTIONIST-USER-UUID>';
--   admin_user uuid := '<ADMIN-USER-UUID>';
--   v_cage uuid;
--   v_rows int;
-- begin
--   select c.id into v_cage
--   from public.cages c
--   join public.staff_profiles sp on sp.branch_id = c.branch_id
--   where sp.id = admin_user and c.status = 'Available'
--   limit 1;
--
--   if v_cage is null then
--     raise exception 'No Available cage found at the admin_user branch - reseed first';
--   end if;
--
--   -- Impersonate Receptionist: attempt to set Under Maintenance must fail (0 rows)
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', receptionist_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   update public.cages set status = 'Under Maintenance' where id = v_cage;
--   get diagnostics v_rows = row_count;
--   reset role;
--   if v_rows = 0 then
--     raise notice 'PASS: Receptionist cannot set Under Maintenance';
--   else
--     raise exception 'FAIL: Receptionist was able to set Under Maintenance';
--   end if;
--
--   -- Impersonate Admin: must succeed (1 row)
--   perform set_config('request.jwt.claims',
--     json_build_object('sub', admin_user, 'role', 'authenticated')::text, true);
--   set local role authenticated;
--   update public.cages set status = 'Under Maintenance' where id = v_cage;
--   get diagnostics v_rows = row_count;
--   reset role;
--   if v_rows = 1 then
--     raise notice 'PASS: Admin can set Under Maintenance';
--   else
--     raise exception 'FAIL: Admin update did not apply';
--   end if;
--
--   -- Reset the cage back to Available (service role bypasses RLS here).
--   update public.cages set status = 'Available' where id = v_cage;
-- end $$;

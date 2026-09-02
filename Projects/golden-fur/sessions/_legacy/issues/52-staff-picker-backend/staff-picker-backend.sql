-- Issue #52 Verification SQL — policy_configurations stub
-- Paste the whole file into Supabase Studio -> SQL Editor and Run.
-- Every row must show pass = true.

with checks as (
  select 'enforcement_mode enum exists with Strict/Soft' as check_name,
    (select array_agg(enumlabel order by enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
     where t.typname = 'enforcement_mode') = array['Strict','Soft'] as pass

  union all
  select 'policy_configurations has ONLY the stub columns (no Sprint 5 columns yet)',
    (select array_agg(column_name order by column_name)
     from information_schema.columns
     where table_schema = 'public' and table_name = 'policy_configurations')
    = array['branch_id','created_at','id','notice_enforcement_enabled',
            'notice_enforcement_mode','notice_period_days',
            'staff_picker_enabled_grooming','staff_picker_enabled_veterinary',
            'updated_at']

  union all
  select 'exactly one system-wide default row (branch_id IS NULL) is seeded',
    (select count(*) from public.policy_configurations where branch_id is null) = 1

  union all
  select 'seeded default row carries the documented defaults (3 / Strict / all true)',
    exists (
      select 1 from public.policy_configurations
      where branch_id is null
        and notice_period_days = 3
        and notice_enforcement_mode = 'Strict'
        and notice_enforcement_enabled = true
        and staff_picker_enabled_grooming = true
        and staff_picker_enabled_veterinary = true
    )

  union all
  select 'unique index: one row per branch',
    exists (select 1 from pg_indexes
            where schemaname = 'public'
              and indexname = 'policy_configurations_branch_uniq')

  union all
  select 'unique index: at most one default row',
    exists (select 1 from pg_indexes
            where schemaname = 'public'
              and indexname = 'policy_configurations_default_uniq')

  union all
  select 'RLS enabled with staff-read + admin-manage policies',
    (select relrowsecurity from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'policy_configurations')
    and (select count(*) from pg_policies
         where schemaname = 'public'
           and tablename = 'policy_configurations') = 2

  union all
  select 'notice_period_days rejects negatives (CHECK present)',
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.policy_configurations'::regclass
        and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%notice_period_days%'
    )
)
select * from checks order by check_name;

-- After running the Postman flow, re-run this SELECT to see the Makati
-- override row created by the Admin PATCH (AC-2):
-- select branch_id, staff_picker_enabled_grooming, staff_picker_enabled_veterinary,
--        notice_period_days, notice_enforcement_mode, notice_enforcement_enabled
-- from public.policy_configurations order by branch_id nulls first;

-- Issue #17 verification helper.
-- Confirms theme_preference was added to staff_profiles and customer_profiles
-- with the correct type, default, and CHECK constraint.

select
  table_name,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('staff_profiles', 'customer_profiles')
  and column_name = 'theme_preference'
order by table_name;

-- Expected (both rows):
-- data_type = text, is_nullable = NO, column_default = 'system'::text

select
  tc.table_name,
  tc.constraint_name,
  cc.check_clause
from information_schema.table_constraints tc
join information_schema.check_constraints cc
  on tc.constraint_name = cc.constraint_name
  and tc.constraint_schema = cc.constraint_schema
where tc.table_schema = 'public'
  and tc.table_name in ('staff_profiles', 'customer_profiles')
  and tc.constraint_name in (
    'staff_profiles_theme_preference_check',
    'customer_profiles_theme_preference_check'
  )
order by tc.table_name;

-- Expected: check_clause references theme_preference IN ('light', 'dark', 'system')

-- Sanity check: a bad value must be rejected by the CHECK constraint.
-- Run this against a throwaway/test row only - it is expected to error.
-- update public.staff_profiles set theme_preference = 'neon' where id = '<some staff id>';

select
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('staff_profiles', 'customer_profiles')
order by tablename, policyname;

-- Expected: no new policies were added by this migration - the existing
-- "can update their own profile" UPDATE policies (auth.uid() = id) already
-- cover the new theme_preference column since RLS is row-level, not column-level.

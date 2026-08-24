-- Issue #15 verification helper.
-- Confirms the helper used by staff/unavailability RLS policies exists.

select
  p.proname as function_name,
  p.prosecdef as is_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'current_staff_role';

-- Expected:
-- function_name       | is_security_definer
-- current_staff_role  | true

select
  tablename,
  policyname,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('staff_profiles', 'staff_unavailability_blocks')
  and (
    qual like '%current_staff_role%'
    or with_check like '%current_staff_role%'
  )
order by tablename, policyname;

-- Expected:
-- Admin/Superadmin policies reference public.current_staff_role()
-- instead of directly querying public.staff_profiles from inside policy bodies.

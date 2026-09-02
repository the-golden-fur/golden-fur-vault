-- Issue #16 verification helper.
-- Confirms shared MFA lockout storage and RLS policy are installed.

select
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'mfa_lockouts'
order by ordinal_position;

-- Expected columns:
-- id, user_id, failed_attempts, locked_until, last_attempt_at, created_at

select
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_schema as foreign_table_schema,
  ccu.table_name as foreign_table_name,
  ccu.column_name as foreign_column_name
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
  and tc.table_schema = kcu.table_schema
left join information_schema.constraint_column_usage ccu
  on tc.constraint_name = ccu.constraint_name
  and tc.table_schema = ccu.table_schema
where tc.table_schema = 'public'
  and tc.table_name = 'mfa_lockouts'
  and tc.constraint_type in ('PRIMARY KEY', 'UNIQUE', 'FOREIGN KEY')
order by tc.constraint_type, tc.constraint_name;

-- Expected:
-- user_id is UNIQUE.
-- user_id references auth.users(id).

select
  schemaname,
  tablename,
  rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename = 'mfa_lockouts';

-- Expected rowsecurity: true

select
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'mfa_lockouts'
order by policyname;

-- Expected:
-- One SELECT policy for authenticated users with auth.uid() = user_id.
-- No INSERT or UPDATE policies for normal authenticated clients.

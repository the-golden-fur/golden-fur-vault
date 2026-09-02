-- Custom change: promo cap "count" type + service type branch availability —
-- Supabase SQL Editor verification queries.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only.
--
-- Prerequisite: migrations 20260818132 and 20260818133 applied
-- (supabase db push, or `supabase db reset` for a fresh local database).

-- =========================================================================
-- SECTION 1: promo_cap_configuration.cap_type gains 'count'
-- =========================================================================

select enum_range(null::public.cap_type_enum);
-- Expected: {percentage,flat,count}

-- =========================================================================
-- SECTION 2: service_type_branch_availability exists, seeded true for
-- every existing (service type, branch) pair
-- =========================================================================

select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name = 'service_type_branch_availability';
-- Expected: one row.

select st.name as service_type, b.name as branch, stba.is_available
from public.service_type_branch_availability stba
join public.service_types st on st.id = stba.service_type_id
join public.branches b on b.id = stba.branch_id
order by st.name, b.name;
-- Expected: one row per (service type, branch) pair that existed when the
-- migration ran, every is_available = true.

select count(*) as service_type_count
from public.service_types;

select count(*) as branch_count
from public.branches;

select count(*) as availability_row_count
from public.service_type_branch_availability;
-- Expected: availability_row_count = service_type_count * branch_count
-- (every type x every branch, seeded by the migration's cross join).

-- =========================================================================
-- SECTION 3: RLS - same "any authenticated user can read, only Admin/
-- Superadmin can write" shape as service_types itself
-- =========================================================================

select policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename = 'service_type_branch_availability'
order by policyname;
-- Expected: two policies - a `for select` open-read policy and a `for all`
-- Admin/Superadmin-only policy, matching service_types' own RLS shape.

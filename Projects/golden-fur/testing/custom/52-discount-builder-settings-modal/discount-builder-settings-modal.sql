-- Custom change: discount builder branch multiselect + settings modal —
-- Supabase SQL Editor verification queries.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only.
--
-- Prerequisite: migration 20260820140_custom_discount_branch_availability.sql
-- applied (supabase db push, or `supabase db reset` for a fresh local
-- database, which also re-runs the module-3-maintenance seed).

-- =========================================================================
-- SECTION 1: discounts.branch_id is gone, discount_branch_availability
-- exists in its place
-- =========================================================================

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'discounts'
  and column_name = 'branch_id';
-- Expected: zero rows (the column was dropped).

select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name = 'discount_branch_availability';
-- Expected: one row.

-- =========================================================================
-- SECTION 2: every pre-existing discount was backfilled 1:1 (one
-- availability row per discount, at its old branch)
-- =========================================================================

select d.name, b.name as branch, dba.is_available
from public.discount_branch_availability dba
join public.discounts d on d.id = dba.discount_id
join public.branches b on b.id = dba.branch_id
order by d.name, b.name;

-- =========================================================================
-- SECTION 3: mandated seed (Senior Citizen / PWD) is now 8 rows (2 names x
-- 4 categories), not 16 (2 x 2 branches x 4 categories) - each available at
-- every branch
-- =========================================================================

select count(*) as mandated_discount_count
from public.discounts
where is_mandated;
-- Expected: 8 (was 16 before this change).

select d.name, d.scope_category, count(dba.branch_id) as branch_count
from public.discounts d
join public.discount_branch_availability dba on dba.discount_id = d.id
where d.is_mandated
group by d.name, d.scope_category
order by d.name, d.scope_category;
-- Expected: 8 rows, branch_count = number of branches in public.branches
-- for every one of them (each mandated discount is available everywhere).

-- =========================================================================
-- SECTION 4: RLS - same "staff can read, only Admin/Superadmin can write"
-- shape as discounts itself
-- =========================================================================

select policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename = 'discount_branch_availability'
order by policyname;
-- Expected: two policies - a `for select` staff-read policy and a `for all`
-- Admin/Superadmin-only policy, matching discounts' own RLS shape.

-- =========================================================================
-- SECTION 5 (Revision 4): promos.branch_scope is gone, promo_branch_availability
-- exists in its place, backfilled from the old scope
--
-- Prerequisite: migration 20260820141_custom_promo_branch_availability.sql
-- applied.
-- =========================================================================

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'promos'
  and column_name = 'branch_scope';
-- Expected: zero rows (the column was dropped).

select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name = 'promo_branch_availability';
-- Expected: one row.

select p.name, b.name as branch, pba.is_available
from public.promo_branch_availability pba
join public.promos p on p.id = pba.promo_id
join public.branches b on b.id = pba.branch_id
order by p.name, b.name;
-- Expected: every pre-existing promo backfilled - a row per branch for a
-- promo that was 'both', a single row for one that was 'makati'/'southwoods'.

select policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename = 'promo_branch_availability'
order by policyname;
-- Expected: two policies, matching discount_branch_availability's own
-- "staff read, Admin/Superadmin write" shape.

-- =========================================================================
-- SECTION 6 (Revision 4): is_active is derived from branch availability for
-- discounts/services/packages/service_types - none of them should have a
-- row that's active with zero available branches, or inactive with at
-- least one available branch
-- =========================================================================

select d.id, d.name, d.is_active
from public.discounts d
where d.is_active <> exists (
  select 1 from public.discount_branch_availability dba
  where dba.discount_id = d.id and dba.is_available
);
-- Expected: zero rows.

select s.id, s.name, s.is_active
from public.services s
where s.is_active <> exists (
  select 1 from public.service_branch_availability sba
  where sba.service_id = s.id and sba.is_available
);
-- Expected: zero rows.

select pkg.id, pkg.name, pkg.is_active
from public.packages pkg
where pkg.is_active <> exists (
  select 1 from public.package_branch_availability pba
  where pba.package_id = pkg.id and pba.is_available
);
-- Expected: zero rows.

select st.id, st.name, st.is_active
from public.service_types st
where st.is_active <> exists (
  select 1 from public.service_type_branch_availability stba
  where stba.service_type_id = st.id and stba.is_available
);
-- Expected: zero rows.

-- Promos are NOT expected to satisfy this - is_active stays independent of
-- branch availability for them (date-based expiry), so no equivalent query
-- is included here on purpose.

-- Unified Product Catalog -- Supabase SQL Editor verification queries.
-- Type: Custom cross-cutting change (product_catalog unification).
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only.
--
-- Prerequisite: migration 20260731067 applied (supabase db reset, or
-- supabase db push for a linked project), and module-4's seed already run
-- (npm run seed:module-4) so product_catalog has real rows.

-- =========================================================================
-- SECTION 1: product_catalog exists, food_catalog/medication_catalog don't,
-- and the seeded rows carry the expected category/service_scope
-- =========================================================================

select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('product_catalog', 'food_catalog', 'medication_catalog');
-- Expected: exactly one row - product_catalog. food_catalog/medication_catalog
-- must NOT appear (dropped by migration 067).

select category, service_scope, count(*) as row_count
from public.product_catalog
group by category, service_scope
order by category;
-- Expected: at least ('food','hotel',7) and ('medication','hotel',6) from
-- module-4's seed (module-4-hotel.seed.sql / .seed.ts).

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.product_catalog'::regclass and contype = 'u';
-- Expected: a unique constraint over (name, category).

-- =========================================================================
-- SECTION 2: care_feeding_instructions/care_medication_instructions FKs
-- resolve against product_catalog, with the SAME ids the old catalog rows
-- had (no data migration needed on these two tables)
-- =========================================================================

select
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name as references_table
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu
  on tc.constraint_name = ccu.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_name in ('care_feeding_instructions', 'care_medication_instructions')
  and kcu.column_name in ('food_catalog_id', 'medication_catalog_id');
-- Expected: both rows show references_table = product_catalog (not
-- food_catalog/medication_catalog).

-- =========================================================================
-- SECTION 3: RLS is enabled and open-SELECT / Admin-Superadmin-write
-- policies exist
-- =========================================================================

select relrowsecurity
from pg_class
where relname = 'product_catalog';
-- Expected: true.

select polname, polcmd
from pg_policy
where polrelid = 'public.product_catalog'::regclass
order by polname;
-- Expected 4 policies: one SELECT (any authenticated), and INSERT/UPDATE/
-- DELETE each restricted to Admin/Superadmin.

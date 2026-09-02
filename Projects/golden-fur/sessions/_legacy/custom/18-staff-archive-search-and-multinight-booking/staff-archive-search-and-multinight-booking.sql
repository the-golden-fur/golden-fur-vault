-- Archive workflow -- Supabase SQL Editor verification queries.
-- Type: Custom cross-cutting change (deactivate-first CRUD safety + archive).
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only.
--
-- Prerequisite: migrations 20260731070 and 20260731071 applied
-- (supabase db reset, or supabase db push for a linked project).

-- =========================================================================
-- SECTION 1: new columns exist with the expected defaults
-- =========================================================================

select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'customer_profiles' and column_name in ('is_active', 'archived_at'))
    or (table_name = 'pets' and column_name in ('is_active', 'archived_at'))
    or (table_name = 'product_catalog' and column_name = 'archived_at')
    or (table_name = 'staff_profiles' and column_name = 'archived_at')
  )
order by table_name, column_name;
-- Expected: is_active columns are boolean, not null, default true.
-- archived_at columns are timestamptz, nullable, no default.

-- =========================================================================
-- SECTION 2: every existing row starts active and unarchived
-- =========================================================================

select 'customer_profiles' as table_name, count(*) filter (where is_active) as active_count,
       count(*) filter (where archived_at is not null) as archived_count
from public.customer_profiles
union all
select 'pets', count(*) filter (where is_active), count(*) filter (where archived_at is not null)
from public.pets
union all
select 'product_catalog', count(*) filter (where is_active), count(*) filter (where archived_at is not null)
from public.product_catalog
union all
select 'staff_profiles', count(*) filter (where is_active), count(*) filter (where archived_at is not null)
from public.staff_profiles;
-- Expected right after migration: archived_count = 0 everywhere (nothing has
-- been archived yet); active_count should equal (or be close to) each
-- table's total row count for pre-existing seed data.

-- =========================================================================
-- SECTION 3: partial indexes exist for the archive-list queries
-- =========================================================================

select indexname, tablename
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'product_catalog_archived_at_idx',
    'staff_profiles_archived_at_idx',
    'customer_profiles_archived_at_idx',
    'pets_archived_at_idx'
  )
order by tablename;
-- Expected: exactly 4 rows, one per table.

-- =========================================================================
-- SECTION 4: end-to-end archive-workflow check (after exercising the UI)
-- =========================================================================
-- After archiving a product/staff/customer/pet through the app, its
-- archived_at should be set and is_active should be false:

select id, name, is_active, archived_at
from public.product_catalog
where archived_at is not null
order by archived_at desc
limit 10;

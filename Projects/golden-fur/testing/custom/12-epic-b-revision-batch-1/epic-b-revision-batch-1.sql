-- Epic B — Revision Batch 1 (Issues #79-#85) — Supabase SQL Editor
-- verification queries.
-- Type: Custom epic implementation (temp/context Epic B Guide + Design
-- workbook), not a single-issue bug fix.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only EXCEPT Section 6, which
-- is a real insert used to satisfy Issue #84 AC-6 (there is no checkout UI
-- yet to exercise transaction_promo_selections end-to-end) - it cleans up
-- after itself inside a begin/rollback block, so nothing is left behind.
--
-- Prerequisite: migrations 20260726047 through 20260726049 applied
-- (supabase db push, or `supabase db reset` for a fresh local database).
-- Numbering note: this batch's migrations are 047-049, not the Guide's
-- assumed 032-035 - the actual last merged migration on dev was 20260725046,
-- not the Guide's assumed ...031. Confirm against your own
-- supabase/migrations/ folder if this differs.

-- =========================================================================
-- SECTION 1 (Issue #80): pricing_configuration singleton + the old
-- service_pricing_tiers table is gone (superseded, not just deprecated)
-- =========================================================================

select *
from public.pricing_configuration;
-- Expected: exactly one row (size_s/m/l/xl_multiplier, long_coat_addon).

select count(*) as row_count
from public.pricing_configuration;
-- Expected: 1 (singleton index enforces this can never be >1).

select table_name
from information_schema.tables
where table_schema = 'public' and table_name = 'service_pricing_tiers';
-- Expected: zero rows - the table no longer exists. The Grooming size/coat
-- matrix is now derived on read from services.base_price +
-- pricing_configuration (deriveGroomingMatrix), not stored per cell.
-- Check the migration 20260726047 run log for the RAISE NOTICE lines
-- listing every pre-migration tier value, if you need to confirm nothing
-- manually-tuned was silently lost.

-- =========================================================================
-- SECTION 2 (Issue #82): package_pricing_configuration singleton +
-- packages.bundled_price column is gone
-- =========================================================================

select *
from public.package_pricing_configuration;
-- Expected: exactly one row (bundle_discount_percentage, e.g. 0.1000).

select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'packages'
  and column_name = 'bundled_price';
-- Expected: zero rows - bundled_price no longer exists on packages. It is
-- now derived on read (deriveBundledPrice) from the included services'
-- base_price and package_pricing_configuration.

-- =========================================================================
-- SECTION 3 (Issue #84): promos.is_exclusive gone, promo_cap_configuration
-- seeded, cap_type_enum exists
-- =========================================================================

select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'promos'
  and column_name = 'is_exclusive';
-- Expected: zero rows - is_exclusive was dropped, not deprecated.

select enumlabel
from pg_enum
where enumtypid = 'public.cap_type_enum'::regtype
order by enumsortorder;
-- Expected: percentage, flat.

select branch_id, cap_type, cap_value
from public.promo_cap_configuration
order by branch_id nulls first;
-- Expected: at least one row with branch_id = NULL (the system-wide
-- default, seeded 'percentage' / 20.00 by the migration).

-- =========================================================================
-- SECTION 4 (Issue #84): transaction_promo_selections schema shape
-- =========================================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'transaction_promo_selections'
order by ordinal_position;
-- Expected: id, transaction_id (uuid, NOT NULL, no FK yet - see below),
-- promo_id (uuid, NOT NULL, FK to promos), is_activated (boolean, NOT
-- NULL, default false), activated_at (timestamptz, nullable).

select conname, contype
from pg_constraint
where conrelid = 'public.transaction_promo_selections'::regclass
  and contype = 'f';
-- Expected: exactly one foreign key (promo_id -> promos.id). transaction_id
-- deliberately has NO foreign key yet - public.transactions does not exist
-- until M08 ships (Sprint 5). Do not treat the absence of that FK as a bug.

-- =========================================================================
-- SECTION 5 (Issue #85): discounts.scope_type already supports 'category'
-- =========================================================================
-- Deviation from the Guide worth confirming here: the Guide's Issue #85
-- assumed a new migration was needed to add category scope to discounts.
-- The actual Sprint 2 schema (20260715033_m12_create_discounts_schema.sql)
-- already shipped scope_type = 'category' + discounts.category + the
-- discounts_scope_matches_type CHECK - so Epic B's #85 needed no new
-- migration, only the client-side card/search/filter UI overhaul.

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.discounts'::regclass
  and conname = 'discounts_scope_matches_type';
-- Expected: the CHECK definition includes the 'category' branch
-- (scope_category is not null and scope_service_id/scope_package_id null).

-- =========================================================================
-- SECTION 6 (Issue #84 AC-6): transaction_promo_selections.is_activated
-- defaults to false on insert - verified by a direct insert since no
-- checkout UI exists yet to exercise it end-to-end. Self-cleaning: wrapped
-- in begin/rollback, so this never actually persists a row.
-- =========================================================================

begin;

-- Swap in a real promo id from your own `select id from public.promos
-- limit 1;` before running this section.
insert into public.transaction_promo_selections (transaction_id, promo_id)
values (gen_random_uuid(), (select id from public.promos limit 1))
returning is_activated, activated_at;
-- Expected: is_activated = false, activated_at = NULL (the check
-- constraint requires activated_at to be NULL exactly when is_activated is
-- false).

rollback;

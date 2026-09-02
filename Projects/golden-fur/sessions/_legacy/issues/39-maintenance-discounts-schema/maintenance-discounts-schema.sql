-- Issue #39 SQL verification - run each block separately in Supabase Studio
-- SQL Editor (Dashboard -> SQL Editor -> New query). Expected results are
-- commented above each block.

-- ============================================================
-- Block 1 (AC-2): enums exist with the right values
-- Expected: 2 rows - service_category (Grooming, Hotel, Daycare, Veterinary)
-- and discount_type (Percentage, Flat).
-- ============================================================

select t.typname as enum_name,
       array_agg(e.enumlabel order by e.enumsortorder) as values
from pg_type t
join pg_enum e on e.enumtypid = t.oid
where t.typname in ('service_category', 'discount_type')
group by t.typname;

-- ============================================================
-- Block 2 (AC-2): all 8 tables exist with RLS enabled
-- Expected: 8 rows, rls_enabled = true on every one.
-- ============================================================

select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in (
    'services', 'service_pricing_tiers', 'service_branch_availability',
    'packages', 'package_services', 'promos', 'promo_scope', 'discounts'
  )
order by c.relname;

-- ============================================================
-- Block 3 (AC-3): two policies per table (staff read + admin manage)
-- Expected: 16 rows - each of the 8 tables appears twice, one SELECT
-- policy ("Staff can read ...") and one ALL policy ("Admins and
-- superadmins can manage ...").
-- ============================================================

select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in (
    'services', 'service_pricing_tiers', 'service_branch_availability',
    'packages', 'package_services', 'promos', 'promo_scope', 'discounts'
  )
order by tablename, policyname;

-- ============================================================
-- Block 4 (AC-4a): package_services ON DELETE RESTRICT
-- Runs inside a transaction and rolls back - nothing is persisted.
-- Expected: the DELETE statement FAILS with
--   'update or delete on table "services" violates foreign key constraint
--    "package_services_service_id_fkey" on table "package_services"'
-- and the final ROLLBACK cleans up. (In the SQL Editor the error aborts the
-- block, which is exactly the point - run Block 4b afterwards to confirm
-- nothing leaked.)
-- ============================================================

begin;

insert into public.services (id, category, name, base_price)
values ('99999999-9999-4999-a999-999999999901', 'Grooming', '__restrict_test_service', 100);

insert into public.packages (id, branch_id, name, bundled_price)
select '99999999-9999-4999-a999-999999999902', id, '__restrict_test_package', 100
from public.branches limit 1;

insert into public.package_services (package_id, service_id)
values ('99999999-9999-4999-a999-999999999902', '99999999-9999-4999-a999-999999999901');

-- This DELETE must FAIL (RESTRICT):
delete from public.services where id = '99999999-9999-4999-a999-999999999901';

rollback;

-- ============================================================
-- Block 4b: confirm the RESTRICT test left nothing behind
-- Expected: 0 rows.
-- ============================================================

rollback; -- clears the aborted transaction from Block 4, harmless if none

select * from public.services where name like '__restrict_test%';

-- ============================================================
-- Block 5 (AC-4b): promo_scope exactly-one-of CHECK
-- Expected: BOTH inserts fail with
--   'new row for relation "promo_scope" violates check constraint ...'
-- Run each insert separately; then run the rollback.
-- ============================================================

begin;

insert into public.promos (id, name, start_date, end_date, discount_type, value, scope_type, branch_scope)
values ('99999999-9999-4999-a999-999999999903', '__check_test_promo',
        '2026-08-01', '2026-08-31', 'Percentage', 10, 'specific', 'both');

-- Must FAIL - neither target set:
insert into public.promo_scope (promo_id, service_id, package_id)
values ('99999999-9999-4999-a999-999999999903', null, null);

rollback;

-- ============================================================
-- Block 6 (AC-3, optional deeper check): simulate a non-admin staff member.
-- Replace <GROOMER_UUID> with a real Groomer id from staff_profiles
-- (Table Editor -> staff_profiles -> copy an id where role = 'Groomer').
-- Expected: the SELECT returns rows; the INSERT fails with
-- 'new row violates row-level security policy for table "services"'.
-- ============================================================

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub": "<GROOMER_UUID>", "role": "authenticated"}';

select count(*) from public.services;      -- succeeds (possibly 0 rows, no error)

insert into public.services (category, name, base_price)
values ('Grooming', '__rls_test', 1);      -- must FAIL (RLS)

rollback;

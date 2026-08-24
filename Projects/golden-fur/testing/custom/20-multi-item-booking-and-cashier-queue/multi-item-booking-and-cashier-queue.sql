-- Multi-item bookings + booking-time discount/promo - Verification SQL
-- Confirms the schema changes from
-- ...077_m03_multi_item_bookings.sql and
-- ...078_m03_m08_booking_discount_promo.sql landed correctly:
-- booking_items exists and bookings.service_id/package_id/booking_addons
-- are gone, and bookings has the new selected_discount_id/selected_promo_id/
-- discount_amount/promo_amount columns.

-- ============================================================
-- 1. Confirm booking_items exists with the expected shape
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'booking_items'
order by ordinal_position;
-- Expected columns: id, booking_id, service_id, package_id,
-- price_at_booking, duration_minutes_at_booking, created_at.
-- service_id/package_id/price_at_booking should be nullable = YES for
-- service_id/package_id (exactly one is null per row), NO for
-- price_at_booking/duration_minutes_at_booking.

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.booking_items'::regclass
  and contype = 'c';
-- Expected: one check constraint whose definition contains
-- "num_nonnulls(service_id, package_id) = 1".

select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'booking_items'
order by indexname;
-- Expected: a plain index on booking_id, plus two partial UNIQUE indexes
-- (one on (booking_id, service_id) where service_id is not null, one on
-- (booking_id, package_id) where package_id is not null).

-- ============================================================
-- 2. Confirm bookings.service_id/package_id are gone, and
-- booking_addons was dropped
-- ============================================================

select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'bookings'
  and column_name in ('service_id', 'package_id');
-- Expected: 0 rows (both columns dropped).

select to_regclass('public.booking_addons');
-- Expected: NULL (table dropped).

-- ============================================================
-- 3. Confirm the new discount/promo columns on bookings
-- ============================================================

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'bookings'
  and column_name in (
    'selected_discount_id', 'selected_promo_id',
    'discount_amount', 'promo_amount'
  )
order by column_name;
-- Expected 4 rows: selected_discount_id (uuid, nullable), selected_promo_id
-- (uuid, nullable), discount_amount (numeric, not null, default 0),
-- promo_amount (numeric, not null, default 0).

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.bookings'::regclass
  and contype = 'f'
  and conname like '%selected%';
-- Expected: two FK constraints, selected_discount_id -> discounts(id) and
-- selected_promo_id -> promos(id).

-- ============================================================
-- 4. Spot-check an existing booking's items after a fresh backfill/reset
-- ============================================================

select b.id, b.service_category, b.status, count(bi.id) as item_count
from public.bookings b
left join public.booking_items bi on bi.booking_id = b.id
group by b.id, b.service_category, b.status
order by b.created_at desc
limit 10;
-- Expected: every booking has item_count >= 1 (no orphaned bookings with
-- zero items - the old exactly-one-of-service_id/package_id data should
-- have backfilled one booking_items row each, plus one more per prior
-- booking_addons row).

-- ============================================================
-- 5. After running through the Postman collection / manual UI test: spot-
-- check a booking that had a discount and/or promo applied at creation
-- ============================================================

select
  id, total_price, selected_discount_id, discount_amount,
  selected_promo_id, promo_amount, payment_method
from public.bookings
where selected_discount_id is not null or selected_promo_id is not null
order by created_at desc
limit 5;
-- Expected: discount_amount/promo_amount > 0 only where the matching
-- selected_*_id is set; any booking with selected_discount_id set should
-- have payment_method = 'Cash' (the server-side rule - this query is a
-- sanity check, not a substitute for the 400-on-GCash Postman request).

-- ============================================================
-- Round 3: confirm 'Misc' is a valid service_category value, and that
-- Initial Assessment/Reassessment moved there
-- ============================================================

select enumlabel
from pg_enum
where enumtypid = 'public.service_category'::regtype
order by enumsortorder;
-- Expected: Grooming, Hotel, Daycare, Veterinary, Misc (5 rows - Misc last,
-- since ADD VALUE appends).

select id, category, name, base_price, duration_minutes, requires_assessed_pet
from public.services
where id in (
  'a1300000-0000-4000-a000-000000000022', -- Initial Assessment
  'a1300000-0000-4000-a000-000000000023'  -- Reassessment
)
order by name;
-- Expected: both rows now have category = 'Misc' (was 'Grooming').
-- Initial Assessment: requires_assessed_pet = false.
-- Reassessment: requires_assessed_pet = true.

-- Round 3 also touches pricing, not schema - the "Hotel price = rate x
-- nights" behavior is exercised by the automated tests (booking.service.
-- spec.ts's "Hotel nights pricing" describe block) and the manual UI/
-- Postman steps in the .md doc, not a schema check here.

-- Session & Hotel Booking Fixes -- Supabase SQL Editor verification queries.
-- Type: Custom bug-fix batch (auth session lifetime + M03 booking-flow
-- revisions), not a single-issue feature.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only EXCEPT Section 2, which
-- is a real insert used to confirm bookings.hotel_preferences round-trips
-- correctly - it cleans up after itself inside a begin/rollback block, so
-- nothing is left behind.
--
-- Prerequisite: migration 20260728057_m03_bookings_hotel_preferences.sql
-- applied (supabase db push, or `supabase db reset` for a fresh local
-- database). Section 2 also assumes at least one row already exists in
-- customer_profiles, pets, branches, and a Hotel-category row in services
-- (true on any seeded dev database - module-2/module-3/module-4 seeds).

-- =========================================================================
-- SECTION 1: bookings.hotel_preferences column exists, jsonb, nullable
-- =========================================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'bookings'
  and column_name = 'hotel_preferences';
-- Expected: one row - hotel_preferences, jsonb, is_nullable = YES.

-- =========================================================================
-- SECTION 2: a Hotel booking's hotel_preferences round-trips through a
-- real insert exactly as written (self-cleaning - rolled back below)
-- =========================================================================

begin;

with sample as (
  select
    (select id from public.customer_profiles limit 1) as customer_id,
    (select id from public.pets limit 1) as pet_id,
    (select id from public.branches limit 1) as branch_id,
    (select id from public.services where category = 'Hotel' limit 1) as service_id
)
insert into public.bookings (
  customer_id, pet_id, branch_id, service_category, service_id,
  scheduled_start, scheduled_end, total_price, hotel_preferences
)
select
  customer_id, pet_id, branch_id, 'Hotel', service_id,
  now() + interval '1 day', now() + interval '2 days', 650.00,
  '{
    "feeding": [{"meal_time": "Morning", "food_type": "Kibble", "quantity": "1 cup"}],
    "walking": [{"time_block": "07:00", "duration_minutes": 15}],
    "medications": []
  }'::jsonb
from sample
returning id, hotel_preferences;
-- Expected: one row - hotel_preferences is exactly the jsonb object above
-- (feeding has one entry, walking has one entry, medications is an empty
-- array), not null and not stringified/escaped strangely.

rollback;
-- Confirm the row was NOT left behind:
select count(*) as leftover_test_bookings
from public.bookings
where total_price = 650.00
  and hotel_preferences->'feeding'->0->>'food_type' = 'Kibble';
-- Expected: 0.

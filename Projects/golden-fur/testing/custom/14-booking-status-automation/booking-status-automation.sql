-- Booking Status Automation -- Supabase SQL Editor verification queries.
-- Type: Custom cross-cutting refactor (booking-lifecycle unification +
-- date/time picker accuracy), not a single-issue bug fix.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. All sections are read-only EXCEPT Section 6, which
-- is a real insert/update sequence exercising the full Pending -> In
-- Progress -> Completed -> Paid lifecycle - it cleans up after itself
-- inside a begin/rollback block, so nothing is left behind.
--
-- Prerequisite: migrations 20260728058 through 20260728062 applied
-- (supabase db push, or `supabase db reset` for a fresh local database,
-- which also re-runs the seeds). These come after 20260728057
-- (bookings.hotel_preferences, from the prior "Session & Hotel Booking
-- Fixes" batch - see testing/docs/custom/13-session-and-hotel-booking-fixes)
-- and must be applied in order.

-- =========================================================================
-- SECTION 1: booking_status enum has exactly the 6 new values - 'Confirmed'
-- is gone
-- =========================================================================

select enumlabel
from pg_enum
where enumtypid = 'public.booking_status'::regtype
order by enumsortorder;
-- Expected: Pending, In Progress, Completed, Paid, Cancelled, No-show (in
-- this order) - no 'Confirmed'.

-- =========================================================================
-- SECTION 2: bookings.started_at / completed_at / paid_at exist (nullable)
-- =========================================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'bookings'
  and column_name in ('started_at', 'completed_at', 'paid_at')
order by column_name;
-- Expected: 3 rows, all timestamptz, all is_nullable = YES.

-- =========================================================================
-- SECTION 3: the four per-module status columns are gone
-- =========================================================================

select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'grooming_sessions' and column_name in ('status', 'started_at', 'completed_at'))
    or (table_name = 'consultations' and column_name in ('status', 'completed_at'))
    or (table_name = 'hotel_stays' and column_name = 'status')
  );
-- Expected: zero rows. grooming_status enum should also be gone:

select typname
from pg_type
where typname = 'grooming_status';
-- Expected: zero rows.

-- daycare_sessions.status is a DELIBERATE exception (walk-in sessions have
-- no booking_id to defer to) - confirm it's still there, unchanged:
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'daycare_sessions'
  and column_name = 'status';
-- Expected: one row - status, text. This one was never dropped.

-- =========================================================================
-- SECTION 4: the capacity-holding partial index was renamed/re-predicated,
-- not left pointing at the retired 'Confirmed' value
-- =========================================================================

select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'bookings'
  and indexname in ('bookings_staff_confirmed_idx', 'bookings_staff_active_idx');
-- Expected: only bookings_staff_active_idx exists, and its definition's
-- WHERE clause lists status in ('Pending','In Progress','Completed','Paid') -
-- bookings_staff_confirmed_idx must not exist.

-- =========================================================================
-- SECTION 5: get_staff_availability()'s booking-conflict check no longer
-- references 'Confirmed'
-- =========================================================================

select pg_get_functiondef(oid) as definition
from pg_proc
where proname = 'get_staff_availability';
-- Expected: the function body's Check 2 reads
-- "bk.status in ('Pending', 'In Progress', 'Completed', 'Paid')" - search
-- the returned definition text for 'Confirmed' and confirm there is no match
-- anywhere in it.

-- =========================================================================
-- SECTION 6: full lifecycle round-trip - Pending -> In Progress ->
-- Completed -> Paid, self-cleaning via rollback
-- =========================================================================

begin;

-- Chained data-modifying CTEs, standard Postgres (not psql \gset - each
-- step below depends on the prior one's `returning` output via a subquery,
-- which forces the correct sequential order) - runs the whole insert ->
-- start -> complete -> mark-paid lifecycle as one statement so there is no
-- id to manually copy between steps.
with sample as (
  select
    (select id from public.customer_profiles limit 1) as customer_id,
    (select id from public.pets limit 1) as pet_id,
    (select id from public.branches limit 1) as branch_id,
    (select id from public.services where category = 'Grooming' limit 1) as service_id
),
created as (
  insert into public.bookings (
    customer_id, pet_id, branch_id, service_category, service_id,
    scheduled_start, scheduled_end, total_price, payment_method, payment_confirmed
  )
  select
    customer_id, pet_id, branch_id, 'Grooming', service_id,
    now() + interval '1 day', now() + interval '1 day 1 hour', 500.00,
    'Cash', false
  from sample
  returning id, status, started_at, completed_at, paid_at
),
started as (
  -- Mirrors POST /bookings/:id/start.
  update public.bookings
  set status = 'In Progress', started_at = now()
  where id = (select id from created)
  returning id, status, started_at
),
completed as (
  -- Mirrors POST /bookings/:id/complete for a Cash booking - no online
  -- payment_confirmed, so it stops at Completed rather than auto-Paid.
  update public.bookings
  set status = 'Completed', completed_at = now()
  where id = (select id from started)
  returning id, status, completed_at
),
paid as (
  -- Mirrors POST /bookings/:id/mark-paid.
  update public.bookings
  set status = 'Paid', paid_at = now()
  where id = (select id from completed)
  returning id, status, paid_at
)
select
  created.id,
  created.status as created_status,
  started.status as started_status, started.started_at,
  completed.status as completed_status, completed.completed_at,
  paid.status as paid_status, paid.paid_at
from created, started, completed, paid;
-- Expected: one row - created_status = 'Pending', started_status =
-- 'In Progress' (started_at set), completed_status = 'Completed'
-- (completed_at set), paid_status = 'Paid' (paid_at set).

rollback;
-- Confirm nothing was left behind:
select count(*) as leftover_test_bookings
from public.bookings
where total_price = 500.00 and payment_method = 'Cash' and payment_confirmed = false
  and scheduled_start > now() and scheduled_start < now() + interval '2 days';
-- Expected: 0 (a false positive here is unlikely but possible if your
-- database already has an unrelated matching row - re-run with a distinct
-- total_price like 500.01 if so).

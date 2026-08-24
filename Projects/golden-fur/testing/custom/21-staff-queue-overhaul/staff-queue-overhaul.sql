-- Staff queue overhaul - Verification SQL
-- Confirms the schema changes from
-- ...081_m05_m06_hotel_daycare_advance_roles.sql and
-- ...082_m08_booking_payment_stage.sql landed correctly: hotel_stays/
-- daycare_sessions RLS now includes Groomer/Pet Assistant, and
-- bookings.payment_stage exists with the right enum/default.

-- ============================================================
-- 1. Confirm the payment_stage enum and column
-- ============================================================

select t.typname, e.enumlabel, e.enumsortorder
from pg_type t
join pg_enum e on t.oid = e.enumtypid
where t.typname = 'payment_stage'
order by e.enumsortorder;
-- Expected 3 rows in order: Unpaid, Paid in Advance, Paid.

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'bookings'
  and column_name = 'payment_stage';
-- Expected: one row, is_nullable = 'NO', column_default containing
-- 'Unpaid'::payment_stage (or similar).

select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'bookings'
  and indexname = 'bookings_payment_stage_idx';
-- Expected: one row.

-- Every existing booking should have defaulted to Unpaid.
select payment_stage, count(*)
from public.bookings
group by payment_stage
order by payment_stage;
-- Expected: at least one 'Unpaid' row group (pre-existing bookings);
-- 'Paid in Advance'/'Paid' rows only appear after the manual UI/Postman
-- steps below are run.

-- ============================================================
-- 2. Confirm hotel_stays RLS now includes Groomer/Pet Assistant
-- ============================================================

select policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename = 'hotel_stays'
order by policyname;
-- Expected: the "Staff can read/create/update hotel stays at their
-- branch" policies' `qual`/`with_check` text now lists 'Groomer' and
-- 'Pet Assistant' alongside 'Receptionist', 'Admin', 'Supervisor'. The
-- separate "Superadmins can manage all hotel stays" policy is unchanged.

-- ============================================================
-- 3. Confirm daycare_sessions RLS now includes Groomer/Pet Assistant
-- ============================================================

select policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename = 'daycare_sessions'
order by policyname;
-- Expected: same shape as hotel_stays above - the three "Staff can
-- read/create/update daycare sessions at their branch" policies now list
-- 'Groomer' and 'Pet Assistant' too.

-- ============================================================
-- 4. After running the Postman collection: spot-check a few
-- payment_stage transitions and an assigned_staff_id filter result
-- ============================================================

select id, status, payment_stage, assigned_staff_id, updated_at
from public.bookings
order by updated_at desc
limit 10;
-- Expected: the bookings advanced via Postman/manual UI show
-- payment_stage values of 'Paid in Advance' or 'Paid' as expected, and
-- status is unaffected by payment_stage changes (the two columns move
-- independently - see the .md's "Why" section on this being intentional).

select count(*) filter (where assigned_staff_id is null) as unassigned_count,
       count(*) filter (where assigned_staff_id is not null) as assigned_count
from public.bookings;
-- Sanity check backing the "No preference" / "Assigned to me" filter -
-- both counts should be > 0 in a normally-seeded database (Hotel/Daycare
-- bookings are typically unassigned; Grooming/Veterinary are typically
-- assigned).

-- ============================================================
-- Round 2: confirm 'Paid' is gone from booking_status, and any
-- previously-'Paid' row's payment info was preserved via payment_stage
-- (...083_m03_m08_remove_paid_booking_status.sql)
-- ============================================================

select t.typname, e.enumlabel, e.enumsortorder
from pg_type t
join pg_enum e on t.oid = e.enumtypid
where t.typname = 'booking_status'
order by e.enumsortorder;
-- Expected 5 rows: Pending, In Progress, Completed, Cancelled, No-show.
-- 'Paid' must NOT appear.

select status, count(*)
from public.bookings
group by status
order by status;
-- Expected: no 'Paid' group (query itself would error if the value still
-- existed in the enum and somehow matched, but more simply - this just
-- confirms every row's status is one of the 5 remaining values).

select status, payment_stage, count(*)
from public.bookings
group by status, payment_stage
order by status, payment_stage;
-- Any booking whose status used to be 'Paid' pre-migration should now show
-- status = 'Completed' AND payment_stage = 'Paid' in the same row - spot
-- check a few by id if you tracked any before running the migration.

select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'bookings'
  and indexname = 'bookings_staff_active_idx';
-- Expected: indexdef's predicate reads
-- "status = ANY (ARRAY['Pending'::booking_status, 'In Progress'::booking_status, 'Completed'::booking_status])"
-- (or equivalent) - no 'Paid' in the list.

select pg_get_functiondef('public.get_staff_availability'::regproc);
-- Expected: the function body's Check 2 status list also excludes 'Paid'
-- (search the output for "status in" - should show
-- ('Pending', 'In Progress', 'Completed') only).

-- Reference copies for session 83. Source of truth (both NEW, uncommitted
-- working-tree files in golden-fur, staged directly on `dev` as of session
-- close - no branch/commit yet, see testing.md "Branch:" line):
--   golden-fur/supabase/migrations/20260911188_m03_bookings_slot_conflict_columns.sql
--   golden-fur/supabase/migrations/20260911189_custom_notification_event_type_add_booking_slot_conflict.sql
-- Do not run these from here; they are already applied to the linked dev
-- Supabase project (hikgijuipymfghfuyrjv), confirmed via
-- `npm run supabase:status` this session - see testing.md "Test suites".
--
-- Handy checks for the manual test:
--   -- a customer's currently-flagged bookings (the dashboard popup's data):
--   select id, service_category, scheduled_start, slot_conflict_at, conflict_notice
--     from public.bookings
--     where customer_id = '<customer id>' and slot_conflict_at is not null;
--   -- the notification that should have fired alongside the flag above:
--   select event_type, title, message, related_booking_id, is_read, created_at
--     from public.notifications
--     where recipient_customer_id = '<customer id>'
--       and event_type = 'booking_slot_conflict'
--     order by created_at desc;


-- ===== NEW: 20260911188_m03_bookings_slot_conflict_columns.sql =====

-- Custom change (slot-conflict notification): a still-Pending, unpaid
-- down-payment-required "pencil booking" is deliberately allowed to share a
-- date/time/staff/cage slot with other pencil bookings (SLOT_HOLD_PAID_OR_FILTER,
-- 20260829146-148) - only an actual payment claims the slot for real. These
-- two columns record when a pencil booking has just lost that race, so the
-- customer can be told to pick a new slot instead of silently discovering it
-- only when their own payment later fails.
--
-- Set by a new step in applyFirstBookingPaymentSideEffects (booking.service.ts)
-- right after a DIFFERENT booking's payment settles and re-confirms it still
-- holds its own slot: every other still-Pending/unpaid/downpayment_required
-- booking that would now fail checkCapacity() for the same
-- branch/category/overlapping window gets flagged here.
--
-- Cleared back to NULL by a successful reschedule (reschedule.service.ts) -
-- once the customer has picked a new slot (which reschedule already
-- re-validates for capacity on its own), the warning no longer applies.
--
-- The booking's own `status` is left untouched (still 'Pending') - this is a
-- "please fix this" flag, not a cancellation. No RLS change: both columns are
-- plain fields on a row customers can already read via existing bookings
-- policies.

alter table public.bookings
  add column slot_conflict_at timestamptz,
  add column conflict_notice text;

comment on column public.bookings.slot_conflict_at is
  'When another customer''s downpayment claimed this still-unpaid pencil booking''s date/time/staff/cage slot first. NULL unless the booking currently needs the customer to pick a new slot. Set by applyFirstBookingPaymentSideEffects in booking.service.ts, cleared by a successful reschedule.';

comment on column public.bookings.conflict_notice is
  'Short, customer-facing explanation shown alongside slot_conflict_at (e.g. which staff/date/time is no longer available). NULL unless slot_conflict_at is set.';


-- ===== NEW: 20260911189_custom_notification_event_type_add_booking_slot_conflict.sql =====

-- Custom change (slot-conflict notification): adds the 11th
-- notification_event_type value, fired at the same moment
-- bookings.slot_conflict_at is set (see 20260911188) - tells a customer that
-- another customer's downpayment just claimed the date/time/staff/cage slot
-- their own still-unpaid "pencil booking" was sharing, and that they need to
-- pick a new one.
--
-- Must be its own migration: Postgres forbids using a value added by ADD
-- VALUE in the same transaction it was added in - same isolation already
-- used by 20260814124_custom_notification_event_type_add_message_received.sql
-- and 20260819137_custom_notification_event_type_add_staff_assigned.sql.

alter type public.notification_event_type add value 'booking_slot_conflict';

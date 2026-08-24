-- Bundled for reference only - source of truth is supabase/migrations/.
-- Adds the 10th notification_event_type value used by the new
-- "customer picked you as preferred staff" alert (see
-- notifications-modal-and-staff-assignment.md, section 2).
--
-- Must run in its own transaction/statement: Postgres forbids using a value
-- added by ADD VALUE in the same transaction it was added in.

alter type public.notification_event_type add value 'staff_assigned';

-- Reference copy of the migration added in session 67.
-- Canonical file: golden-fur/supabase/migrations/20260902166_m09_policy_configurations_booking_notice_period.sql

alter table public.policy_configurations
  add column booking_notice_period_days integer not null default 0
    check (booking_notice_period_days >= 0);

comment on column public.policy_configurations.booking_notice_period_days is
  'Minimum whole days ahead of "now" (branch timezone) that a NEW online booking must be scheduled. 0 = same-day allowed. Independent of notice_period_days, which is the reschedule/cancellation notice. Resolved by resolveEffectivePolicy in staffPicker.service.ts.';

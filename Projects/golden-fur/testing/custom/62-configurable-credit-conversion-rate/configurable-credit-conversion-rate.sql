-- Custom change (advisor MsMayuga-Aug27, "Cancellations & Credits" #10;
-- Refs GitHub #117) - migration for manual review/reference.
-- Source of truth is:
--   supabase/migrations/20260901149_m10_policy_cancellation_credit_conversion_rate.sql
--
-- Request, verbatim (advisor session, item 10):
-- "Cancellation always converts payment to a full (100%) credit, with no
-- configurable option. ... The advisor suggested this should be configurable
-- (e.g., an admin-defined percentage, such as 50%, returned as credit
-- instead of the full amount)."
--
-- Adds one column to the existing policy_configurations table (system-default
-- row + per-branch override rows, resolved by resolveEffectivePolicy). The
-- NOT NULL DEFAULT 100 backfills every existing row, so cancellations behave
-- exactly as before until an Admin lowers the rate on Settings > Config >
-- Policies. cancellation.service.ts multiplies the amount the customer
-- actually paid (derived from bookings.payment_stage) by this percentage.

alter table public.policy_configurations
  add column cancellation_credit_conversion_rate numeric(5, 2) not null default 100
    check (cancellation_credit_conversion_rate >= 0
       and cancellation_credit_conversion_rate <= 100);

comment on column public.policy_configurations.cancellation_credit_conversion_rate is
  'Percentage (0-100) of the amount a customer actually paid that is converted to account credit when a qualifying booking is cancelled. Default 100 (full). Resolved by resolveEffectivePolicy in staffPicker.service.ts, applied in cancellation.service.ts.';

-- Quick checks after `supabase db push`:
--   select branch_id, cancellation_credit_conversion_rate from public.policy_configurations;
--   -- every row should read 100.00

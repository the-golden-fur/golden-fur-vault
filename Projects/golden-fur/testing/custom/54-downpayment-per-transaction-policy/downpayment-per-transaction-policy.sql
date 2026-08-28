-- Custom change (#54) - migrations for manual review/reference.
-- Source of truth is:
--   supabase/migrations/20260828143_m09_policy_configurations_downpayment.sql
--   supabase/migrations/20260828144_m13_services_packages_downpayment_removal.sql
--
-- Request, verbatim (from the MsMayuga-URO-Aug27 advisor session):
-- "Move the down payment toggle/config so it applies per transaction (all
-- online bookings/services), not per individual service."
--
-- Reverses the per-catalog-item downpayment mechanism added by #34
-- (20260808110-20260808112): downpayment goes back to being a
-- policy_configurations field (system-default + per-branch override, same
-- resolution as every other policy field), this time actually wired into
-- createBooking (the earlier policy_configurations.downpayment_percentage
-- column, added by #88/20260805094, was dead code and got dropped by
-- 20260808112 for exactly that reason) and generalized to every service
-- category, computed once against the whole booking's total_price rather
-- than summed per selected item.

-- ---------------------------------------------------------------------------
-- 1. policy_configurations: the new per-transaction downpayment config
-- ---------------------------------------------------------------------------

alter table public.policy_configurations
  add column downpayment_enabled boolean not null default false,
  add column downpayment_type text
    check (downpayment_type is null or downpayment_type in ('Flat', 'Percentage')),
  add column downpayment_amount numeric(10, 2)
    check (downpayment_amount is null or downpayment_amount > 0);

comment on column public.policy_configurations.downpayment_enabled is
  'Whether an online booking transaction requires a downpayment. System-default + per-branch-override, resolved by resolveEffectivePolicy/resolveDownpaymentPolicy in staffPicker.service.ts.';
comment on column public.policy_configurations.downpayment_type is
  'Flat = downpayment_amount is a PHP figure; Percentage = downpayment_amount is a 0-100 percentage of the booking''s total_price. NULL unless downpayment_enabled is true.';
comment on column public.policy_configurations.downpayment_amount is
  'Flat PHP amount or percentage (see downpayment_type) applied to a booking''s total_price at creation time (createBooking in booking.service.ts). NULL unless downpayment_enabled is true.';

-- ---------------------------------------------------------------------------
-- 2. services/packages: remove the superseded per-catalog-item mechanism
-- ---------------------------------------------------------------------------

alter table public.services
  drop constraint services_downpayment_amount_check,
  drop column requires_downpayment,
  drop column downpayment_amount,
  drop column downpayment_type;

alter table public.packages
  drop constraint packages_downpayment_amount_check,
  drop column requires_downpayment,
  drop column downpayment_amount,
  drop column downpayment_type;

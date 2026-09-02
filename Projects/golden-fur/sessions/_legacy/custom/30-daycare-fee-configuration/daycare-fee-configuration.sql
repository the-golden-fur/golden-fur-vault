-- Custom change (#30) - migration for manual review/reference.
-- Source of truth is supabase/migrations/20260807107_m06_m09_daycare_fee_config.sql.

-- Custom change (Daycare fee configuration, P-1): "850 for daycare booking
-- if not picked up (overnight payment) + all 50 for succeeding hours...
-- Add a configuration in admin settings where that fixed 850 price can be
-- changed but default 850. This should be added to a policies page in
-- settings > config" + "When creating a daycare service, include this
-- initial hour + fee for subsequent hours. This fee itself is attached to
-- the service, not hardcoded to all daycare services."
--
-- Two independent fixes:
--
-- 1. daycare_overnight_fee already existed and was already admin-editable
--    (20260803088), but lived on `pricing_configuration` - the Grooming
--    size/coat matrix singleton - and was only ever surfaced on
--    PricingConfigurationPage ("Pricing Configuration"). Revision (live
--    follow-up feedback, before this migration shipped): rather than move
--    it to the Policies page as first drafted, it moves onto `services`
--    instead, alongside first_hour_fee/succeeding_hour_fee below - "each
--    Daycare-type service can have its own overnight fee," visible at
--    booking time on the service itself, same as the hourly fees.
--
-- 2. The ₱100 first-hour / ₱50 succeeding-hour figures were hardcoded
--    module constants in daycareBilling.service.ts, shared by every Daycare
--    service with no per-service override. Added to `services` instead
--    (Daycare-only meaning, same convention as Hotel's
--    min_nights_for_free_package/free_package_name).

-- ---------------------------------------------------------------------------
-- 1. Move daycare_overnight_fee: pricing_configuration -> services (per-service)
-- ---------------------------------------------------------------------------

alter table public.services
  add column daycare_overnight_fee numeric(10, 2) check (daycare_overnight_fee >= 0);

comment on column public.services.daycare_overnight_fee is
  'Daycare-only: charged per night when a pet on this service isn''t picked up before closing, on top of the hourly charge. NULL falls back to the documented ₱850 default (daycareBilling.service.ts).';

-- Matches the pre-existing pricing_configuration.daycare_overnight_fee
-- value (or the documented ₱850 default) exactly, so the seeded Daycare
-- service's billing behavior is unchanged by this migration.
update public.services
set daycare_overnight_fee = coalesce(
  (select daycare_overnight_fee from public.pricing_configuration limit 1),
  850.00
)
where id = 'a1300000-0000-4000-a000-000000000011';  -- Daycare (per hour)

alter table public.pricing_configuration
  drop column daycare_overnight_fee;

-- ---------------------------------------------------------------------------
-- 2. Per-service Daycare hourly fees
-- ---------------------------------------------------------------------------

alter table public.services
  add column first_hour_fee numeric(10, 2) check (first_hour_fee >= 0),
  add column succeeding_hour_fee numeric(10, 2) check (succeeding_hour_fee >= 0);

comment on column public.services.first_hour_fee is
  'Daycare-only: flat charge for the first hour (or less) of a session on this service. NULL falls back to the documented ₱100 default (daycareBilling.service.ts).';
comment on column public.services.succeeding_hour_fee is
  'Daycare-only: charge per additional billable hour (rounded up) beyond the first, on this service. NULL falls back to the documented ₱50 default.';

-- Matches the pre-existing hardcoded FIRST_HOUR_CHARGE/SUCCEEDING_HOUR_CHARGE
-- constants exactly, so the seeded Daycare service's billing behavior is
-- unchanged by this migration.
update public.services
set first_hour_fee = 100.00, succeeding_hour_fee = 50.00
where id = 'a1300000-0000-4000-a000-000000000011';  -- Daycare (per hour)

-- ---------------------------------------------------------------------------
-- 3. stays.service_id - which Daycare service this session's fee schedule
-- comes from (booking-linked: the booking's selected service; walk-in: an
-- explicit choice, or the branch's first active Daycare service).
-- ---------------------------------------------------------------------------

alter table public.stays
  add column service_id uuid references public.services(id);

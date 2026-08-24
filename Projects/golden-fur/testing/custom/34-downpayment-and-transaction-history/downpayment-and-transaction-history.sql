-- Custom change (#34) - migrations for manual review/reference.
-- Source of truth is:
--   supabase/migrations/20260808110_m13_services_packages_downpayment.sql
--   supabase/migrations/20260808111_m03_m08_bookings_downpayment_generalize.sql
--   supabase/migrations/20260808112_m03_m09_m13_downpayment_flat_or_percentage.sql
--
-- Request, verbatim:
-- - When creating services/packages, include requires downpayment checkbox
--   (specify downpayment amount).
-- - When paying for booking services that has downpayment, option for
--   customer/receptionist to pay downpayment or in full.
-- - Services that require downpayment and are unpaid should not show in
--   grooming, hotel and daycare, vet queues. Downpayment is required before
--   service can start. Usually applied on hotel services.
-- - Add a transactions history, visible to customer, cashier, supervisor,
--   admin and superadmin.
--
-- Live follow-up ("should we remove the branch wide hotel downpayment?
-- since it's already applied by service. instead, make it so... the
-- downpayment amount [can] be either flat PHP or percentage"): section 3
-- below drops policy_configurations.downpayment_percentage (the only
-- non-additive change in this file - see its own header comment for why
-- that's safe) and adds a Flat/Percentage type to the catalog downpayment.
-- Every other change here is additive - every new column defaults to
-- today's exact behavior for every existing row, so it is safe to run
-- against a database that already has bookings.

-- ---------------------------------------------------------------------------
-- 1. services/packages: the new "requires downpayment" checkbox + amount
-- ---------------------------------------------------------------------------

alter table public.services
  add column requires_downpayment boolean not null default false,
  add column downpayment_amount numeric(10, 2),
  add constraint services_downpayment_amount_check
    check (
      (requires_downpayment = false and downpayment_amount is null)
      or (requires_downpayment = true and downpayment_amount > 0)
    );

alter table public.packages
  add column requires_downpayment boolean not null default false,
  add column downpayment_amount numeric(10, 2),
  add constraint packages_downpayment_amount_check
    check (
      (requires_downpayment = false and downpayment_amount is null)
      or (requires_downpayment = true and downpayment_amount > 0)
    );

comment on column public.services.requires_downpayment is
  'Whether booking this service requires a downpayment before the service may start. Not category-gated - expected to be used mainly for Hotel services per the roadmap note, but not restricted to it. See resolveBookingItem in booking.service.ts.';
comment on column public.services.downpayment_amount is
  'Downpayment amount required for this service - a flat PHP figure or a percentage, per downpayment_type (section 3 below). NULL unless requires_downpayment is true.';
comment on column public.packages.requires_downpayment is
  'Whether booking this package requires a downpayment before the service may start. Same convention as services.requires_downpayment above.';
comment on column public.packages.downpayment_amount is
  'Flat PHP downpayment amount required for this package. NULL unless requires_downpayment is true.';

-- ---------------------------------------------------------------------------
-- 2. bookings: generalizing the existing Hotel-only downpayment_amount +
--    the new downpayment_required gating flag (queue visibility)
-- ---------------------------------------------------------------------------

alter table public.bookings
  add column downpayment_required boolean not null default false;

comment on column public.bookings.downpayment_required is
  'True when at least one selected service/package was flagged requires_downpayment at booking creation. Drives queue gating: a Pending/In Progress booking with downpayment_required = true and payment_stage = ''Unpaid'' is excluded from the Grooming/Hotel/Daycare/Veterinary staff queues until payment_stage advances.';

comment on column public.bookings.downpayment_amount is
  'The downpayment amount collected/expected for this booking, snapshotted at creation as the sum of the selected items'' catalog downpayment contribution (flat or percentage-of-price_at_booking, per section 3 below) when downpayment_required is true. NULL otherwise.';

create index bookings_downpayment_gate_idx
  on public.bookings (downpayment_required, payment_stage)
  where downpayment_required = true;

-- ---------------------------------------------------------------------------
-- 3. Design revision: drop the branch-wide Hotel percentage entirely (it
--    was already dead code - booking.service.ts/CustomerBookingFlowPage.tsx
--    both used a separate hardcoded HOTEL_DOWNPAYMENT_RATE = 0.5 constant
--    instead of ever reading this column); add flat-or-percentage typing to
--    the catalog downpayment; backfill the seeded Hotel service to keep its
--    real-world 50%-of-total behavior unchanged.
-- ---------------------------------------------------------------------------

alter table public.policy_configurations
  drop column downpayment_percentage;

alter table public.services
  drop constraint services_downpayment_amount_check,
  add column downpayment_type text,
  add constraint services_downpayment_amount_check
    check (
      (requires_downpayment = false
        and downpayment_amount is null and downpayment_type is null)
      or (requires_downpayment = true
        and downpayment_amount > 0
        and downpayment_type in ('Flat', 'Percentage')
        and (downpayment_type = 'Flat' or downpayment_amount <= 100))
    );

alter table public.packages
  drop constraint packages_downpayment_amount_check,
  add column downpayment_type text,
  add constraint packages_downpayment_amount_check
    check (
      (requires_downpayment = false
        and downpayment_amount is null and downpayment_type is null)
      or (requires_downpayment = true
        and downpayment_amount > 0
        and downpayment_type in ('Flat', 'Percentage')
        and (downpayment_type = 'Flat' or downpayment_amount <= 100))
    );

comment on column public.services.downpayment_type is
  'Flat = downpayment_amount is a PHP figure; Percentage = downpayment_amount is a 0-100 percentage of this item''s own price_at_booking. NULL unless requires_downpayment is true.';
comment on column public.packages.downpayment_type is
  'Same convention as services.downpayment_type above.';

update public.services
set requires_downpayment = true,
    downpayment_type = 'Percentage',
    downpayment_amount = 50
where id = 'a1300000-0000-4000-a000-000000000024';  -- Overnight Stay (Aircon Room)

-- ---------------------------------------------------------------------------
-- 4. Verification queries (paste after the above; expect zero errors and
--    the described results)
-- ---------------------------------------------------------------------------

-- Confirm the new columns exist:
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_name in ('services', 'packages')
  and column_name in ('requires_downpayment', 'downpayment_amount', 'downpayment_type')
order by table_name, column_name;

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_name = 'bookings' and column_name = 'downpayment_required';

-- Confirm the branch-wide Hotel percentage is gone:
select column_name from information_schema.columns
where table_name = 'policy_configurations' and column_name = 'downpayment_percentage';
-- Expect zero rows.

-- Confirm the seeded Hotel service was backfilled:
select requires_downpayment, downpayment_type, downpayment_amount
from public.services
where id = 'a1300000-0000-4000-a000-000000000024';
-- Expect true, 'Percentage', 50.00.

-- Every OTHER existing service/package/booking still defaults to "no
-- downpayment required" - unaffected:
select count(*) as flagged_services from public.services
where requires_downpayment = true
  and id != 'a1300000-0000-4000-a000-000000000024';
select count(*) as flagged_packages from public.packages where requires_downpayment = true;
select count(*) as gated_bookings from public.bookings where downpayment_required = true;
-- Expect 0/0/0 immediately after this migration runs, before any admin
-- flags a service/package via the Services/Packages admin pages.

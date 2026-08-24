-- Custom change (#28) - migration for manual review/reference.
-- Source of truth is supabase/migrations/; this file mirrors that one file.

-- =============================================================================
-- 20260807106_m13_optional_pricing_matrix.sql
-- =============================================================================
-- Custom change (Fix pricing matrix, P-1): "Cat has no weight class or
-- coat type, fixed [price] for golden package" / "Coat and weight doesn't
-- seem to influence individual service" - today EVERY Grooming service
-- (services.service.ts's attachPricingMatrix) derives a weight/coat matrix
-- price from base_price + pricing_configuration, with no way to turn that
-- off per service, and packages never vary by pet at all (bundled_price is
-- a single flat admin-configured figure). This adds an opt-in checkbox
-- ("Perhaps when creating a service/package, make the coat and weight
-- matrix optional by adding a checkbox") so a service/package's price can
-- be flat/fixed OR derived from weight/coat - see resolveServicePrice /
-- resolvePackagePrice in booking.service.ts.
--
-- Cat handling is not a schema change - pets.pet_type already exists
-- (20260725041) - it's purely an application-layer rule (booking.service.ts
-- always uses the flat base_price for a Cat pet, regardless of a matrix-
-- enabled service/package's flag), since the pricing board shows one flat
-- Cat figure with no size/coat cells at all.

alter table public.services
  add column use_pricing_matrix boolean not null default false;

alter table public.packages
  add column use_pricing_matrix boolean not null default false;

comment on column public.services.use_pricing_matrix is
  'Grooming-only: whether this service''s price varies by the pet''s weight_class/coat_type. Always ignored for a Cat pet (flat base_price), per the pricing board.';
comment on column public.packages.use_pricing_matrix is
  'Whether this package''s price is derived from the sum of its included services'' own per-pet price (bundle-discounted) instead of the flat bundled_price. Always ignored for a Cat pet (flat bundled_price).';

-- ---------------------------------------------------------------------------
-- Seeded services: only Bath/Blow-dry/Brushing (the three that make up the
-- seeded Golden Package, and the closest existing analog to the board's
-- "Basic Grooming" row, which is the one Basic-tier item that does vary by
-- size) opt in - every individual add-on service (Nail Trim, Teeth
-- Brushing, Ear Cleaning, Anal Drain, Face Trim, Dematting, Poodle Feet)
-- stays flat, matching the board's single-price-per-service columns.
-- ---------------------------------------------------------------------------

update public.services
set use_pricing_matrix = true
where id in (
  'a1300000-0000-4000-a000-000000000001',  -- Bath
  'a1300000-0000-4000-a000-000000000002',  -- Blow-dry
  'a1300000-0000-4000-a000-000000000003'   -- Brushing
);

-- The Golden Package (seeded per-branch by supabase/seeds/module-3-
-- maintenance/ after this migration runs on a fresh `supabase db reset`, so
-- this UPDATE is a no-op there and only takes effect against an
-- already-seeded environment; the seed files themselves are updated
-- separately to set this flag on insert going forward).
update public.packages
set use_pricing_matrix = true
where name = 'Golden Package';

-- Package pricing recommendations — Supabase SQL Editor verification query
-- Type: Custom analysis (recommendations only, no schema/data changes)
--
-- Run in Supabase Studio: your project -> SQL Editor -> New query.
-- Read-only — nothing here changes your data.
--
-- Purpose: package-pricing-recommendations.md §3 notes that
-- packages.use_pricing_matrix / requires_downpayment / downpayment_amount /
-- downpayment_type already exist as columns and are honored by
-- resolvePackagePrice() at booking time, but the package create/edit form
-- has no fields for them — today they can only be set via direct DB/seed
-- edits. This query surfaces which packages and services (if any) already
-- have these flags set from seed data, so you can find one in the
-- Maintenance > Packages list and confirm its read-only badges
-- ("(varies by weight/coat)" / "Requires ... downpayment") match what's
-- shown here — i.e. the data is real and used, just not editable in the UI.

-- Packages with matrix pricing and/or a downpayment configured
select
  id,
  name,
  is_active,
  use_pricing_matrix,
  requires_downpayment,
  downpayment_amount,
  downpayment_type
from public.packages
where use_pricing_matrix = true
   or requires_downpayment = true
order by name;

-- Services with matrix pricing and/or a downpayment configured, plus which
-- packages (if any) include them — useful for finding a package whose
-- own use_pricing_matrix is off but that contains a matrix-enabled member
-- service (the "two independently-settable flags can disagree" case from §3).
select
  s.id as service_id,
  s.name as service_name,
  s.category,
  s.use_pricing_matrix as service_use_pricing_matrix,
  s.requires_downpayment as service_requires_downpayment,
  s.downpayment_amount as service_downpayment_amount,
  s.downpayment_type as service_downpayment_type,
  p.id as package_id,
  p.name as package_name,
  p.use_pricing_matrix as package_use_pricing_matrix
from public.services s
left join public.package_services ps on ps.service_id = s.id
left join public.packages p on p.id = ps.package_id
where s.use_pricing_matrix = true
   or s.requires_downpayment = true
order by s.name;

-- Pricing tiers backing any matrix-enabled service above (the S/M/L/XL x
-- SC/LC grid resolveServicePrice() looks up at booking time)
select
  spt.service_id,
  s.name as service_name,
  spt.weight_class,
  spt.coat_type,
  spt.price
from public.service_pricing_tiers spt
join public.services s on s.id = spt.service_id
order by s.name, spt.weight_class, spt.coat_type;

-- Reference copies of the three migrations added by session 116 (already applied to the dev Supabase project).
-- Source of truth: golden-fur/supabase/migrations/.

-- ===== 20260928218_custom_config_entities_add_archive_columns.sql =====
-- Cages, pet types, breeds, services, and service types gain the same
-- "archived_at" soft-archive column already used by products, staff,
-- customers, pets, discounts, promos, packages, and branches
-- (20260731071/072, 20260922207). Until now these five could only be
-- hard-deleted (cages/pet types/breeds) or not removed at all (services,
-- service types), so the admin Config "..." menu could not offer a
-- consistent Archive action on every row.
--
-- Only archived_at is added, not is_active:
--   - pet_types, services, service_types already have is_active;
--   - cages carry their own lifecycle in `status`, and breeds have never had a
--     deactivate concept - archive is the only on/off switch for those two.
--
-- No RLS changes, same rationale as 20260731071/20260922207: every write path
-- that sets or filters on archived_at goes through the server's service-role
-- Supabase client, which bypasses RLS. The customer-facing direct reads of
-- pet_types / breeds / service_types (open `using (true)` select policies)
-- filter archived rows out client-side instead.
--
-- No new table, so the universal deleted-records-archive trigger
-- (20260913202) needs no new attachment - it already fires on the real
-- DELETE these tables' "Delete permanently" action performs.

alter table public.cages
  add column archived_at timestamptz;

alter table public.pet_types
  add column archived_at timestamptz;

alter table public.breeds
  add column archived_at timestamptz;

alter table public.services
  add column archived_at timestamptz;

alter table public.service_types
  add column archived_at timestamptz;

create index cages_archived_at_idx
  on public.cages (archived_at)
  where archived_at is not null;

create index pet_types_archived_at_idx
  on public.pet_types (archived_at)
  where archived_at is not null;

create index breeds_archived_at_idx
  on public.breeds (archived_at)
  where archived_at is not null;

create index services_archived_at_idx
  on public.services (archived_at)
  where archived_at is not null;

create index service_types_archived_at_idx
  on public.service_types (archived_at)
  where archived_at is not null;

-- ===== 20260928219_custom_cage_occupancy_report_exclude_archived.sql =====
-- Archived cages (20260928218) must not appear in the cage occupancy report.
-- Redefines get_cage_occupancy_report() from 20260805101, verbatim except for
-- the added `c.archived_at is null` filter.

create or replace function public.get_cage_occupancy_report(
  p_branch_id uuid
)
returns table (
  size public.cage_size,
  status public.cage_status,
  cage_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select c.size, c.status, count(*) as cage_count
  from public.cages c
  where c.archived_at is null
    and (p_branch_id is null or c.branch_id = p_branch_id)
  group by c.size, c.status
  order by c.size, c.status;
$$;

-- ===== 20260928220_custom_discounts_add_mandated_kind.sql =====
-- Government-mandated discounts (Senior Citizen / PWD) used to be recognised
-- by their exact NAME: checkout's eligibility gate did
-- `discount.name === 'Senior Citizen Discount'`. That made the name
-- untouchable, so the admin Discounts menu could not offer Rename on those
-- rows like it does everywhere else.
--
-- mandated_kind is the stable identity instead. The gate now reads it, so a
-- mandated discount can be renamed freely without silently dropping its
-- eligibility check (which would have applied it to every customer).
--
-- NULL for custom discounts. Backfilled from the seeded names.
--
-- No RLS changes: discounts is only written through the server's
-- service-role client, which bypasses RLS.

alter table public.discounts
  add column mandated_kind text
    check (mandated_kind in ('senior_citizen', 'pwd')),
  add constraint discounts_mandated_kind_requires_mandated
    check (mandated_kind is null or is_mandated);

update public.discounts
set mandated_kind = 'senior_citizen'
where is_mandated and name = 'Senior Citizen Discount';

update public.discounts
set mandated_kind = 'pwd'
where is_mandated and name = 'PWD Discount';

-- Service Types, Cage Picker & related config addendum - bundled migrations
-- for manual review/reference. Source of truth is supabase/migrations/;
-- this file mirrors those two files, in application order.

-- =============================================================================
-- 20260809113_custom_create_service_types.sql
-- =============================================================================
-- Custom change: Service Types admin CRUD + Staff/Cage Picker config
-- addendum. Admin-configurable display name/active flag for the service
-- lines a customer chooses between at booking time (Grooming/Hotel/Daycare/
-- Veterinary), plus a per-type toggle for whether the Staff Picker / Cage
-- Picker steps are offered on that type. `key` is fixed to the existing
-- hardcoded ServiceCategory value each seeded row represents
-- (booking.types.ts / maintenance.types.ts) - renaming a row's `name` only
-- changes its customer-facing label, the underlying booking/availability/
-- pricing logic for that category is still code-driven and unaffected by
-- this table. A brand-new row created via the admin UI is free-text on
-- `key` and will show up as selectable (if active) but won't have matching
-- category-specific behavior (availability, capacity, pricing, eligibility)
-- until that is separately implemented in code - documented, not hidden,
-- in the admin page's own copy.

create table public.service_types (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  is_active boolean not null default true,
  staff_picker_enabled boolean not null default false,
  cage_picker_enabled boolean not null default false,
  created_by uuid references public.staff_profiles(id),
  updated_by uuid references public.staff_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.service_types enable row level security;

create policy "Any authenticated user can read service types"
  on public.service_types
  for select
  to authenticated
  using (true);

create policy "Admins and superadmins can insert service types"
  on public.service_types
  for insert
  to authenticated
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

create policy "Admins and superadmins can update service types"
  on public.service_types
  for update
  to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

insert into public.service_types (key, name, staff_picker_enabled, cage_picker_enabled) values
  ('Grooming', 'Grooming', true, false),
  ('Hotel', 'Hotel', false, true),
  ('Daycare', 'Daycare', false, false),
  ('Veterinary', 'Veterinary', true, false);


-- =============================================================================
-- 20260809114_custom_bookings_preferred_cage_id.sql
-- =============================================================================
-- Custom change: Cage Picker addendum - lets a Hotel booking record the
-- customer/receptionist's preferred cage at booking time, mirroring the
-- role staff_preference already plays for Grooming/Veterinary bookings.
-- Unlike staff_preference this never hard-assigns anything by itself - a
-- cage's `status` is untouched here. Check-in's existing suggestCage/
-- assignCage flow (hotel/services/cageAssignment.service.ts) still performs
-- the real, concurrency-safe claim; this column only lets that flow
-- pre-select what the customer already asked for. NULL = no preference
-- (today's behavior, unchanged).

alter table public.bookings
  add column preferred_cage_id uuid references public.cages(id);

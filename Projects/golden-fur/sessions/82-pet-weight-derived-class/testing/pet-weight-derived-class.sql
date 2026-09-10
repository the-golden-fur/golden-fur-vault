-- Reference copies for session 82. Source of truth (all NEW, committed in golden-fur @ a97608d):
--   golden-fur/supabase/migrations/20260910184_shared_add_weight_unit_preference_columns.sql
--   golden-fur/supabase/migrations/20260910185_m02_pets_add_weight_kg.sql
--   golden-fur/supabase/migrations/20260910186_m13_create_pet_weight_class_configuration.sql
--   golden-fur/supabase/migrations/20260910187_m02_pets_assessment_lock_weight_kg.sql
-- Do not run these from here; they are already committed in golden-fur. As of
-- the session close they had NOT yet been pushed to the dev Supabase project
-- (Docker was not running locally) - see testing.md "Open items".
--
-- Handy checks for the manual test:
--   -- after test A (assessment saved):
--   select name, weight_kg, weight_class, assessed_at
--     from public.pets order by assessed_at desc nulls last limit 5;
--   -- the current cut-offs:
--   select m_min_kg, l_min_kg, xl_min_kg, updated_by_staff_id, updated_at
--     from public.pet_weight_class_configuration;
--   -- a user's unit preference:
--   select registered_email, weight_unit_preference from public.staff_profiles;
--   select email, weight_unit_preference from public.customer_profiles;


-- ===== NEW: 20260910184_shared_add_weight_unit_preference_columns.sql =====

-- Per-user "view pet weight as kg or lbs" preference - a display-only choice
-- that belongs to the individual, not the branch or an Admin toggle. Same
-- shape as ...018 (theme) / ...065 (font size): one scalar text column with a
-- NOT NULL DEFAULT + named CHECK on BOTH profile tables, so every signed-in
-- user (staff and customer) has it. The DEFAULT backfills existing rows, so
-- this applies cleanly on `db push` to an already-provisioned environment.

alter table public.staff_profiles
  add column weight_unit_preference text not null default 'kg'
    constraint staff_profiles_weight_unit_preference_check
    check (weight_unit_preference in ('kg', 'lbs'));

alter table public.customer_profiles
  add column weight_unit_preference text not null default 'kg'
    constraint customer_profiles_weight_unit_preference_check
    check (weight_unit_preference in ('kg', 'lbs'));


-- ===== NEW: 20260910185_m02_pets_add_weight_kg.sql =====

-- A pet's assessment now records its actual weight, measured on-site during an
-- assessment-type booking - the S/M/L/XL weight_class is derived from that
-- number, not picked by eye. weight_kg is the single canonical store, always
-- in kilograms. NULL = "no numeric weight recorded yet" - independent of
-- weight_class IS NULL ("not yet assessed"), since a legacy pet can have a
-- class but no number. numeric(5,2); the CHECK upper bound (500) is a sanity
-- guard, not a real limit.

alter table public.pets
  add column weight_kg numeric(5, 2)
    constraint pets_weight_kg_range_check
    check (weight_kg is null or (weight_kg > 0 and weight_kg < 500));

comment on column public.pets.weight_kg is
  'Canonical pet weight in kilograms, recorded on-site during assessment. '
  'NULL = no numeric weight yet. weight_class is derived from this on write '
  'unless staff override it. Staff-only writable (enforce_pet_assessment_writes).';


-- ===== NEW: 20260910186_m13_create_pet_weight_class_configuration.sql =====

-- The kg cut-offs that turn a pet's recorded weight_kg into an S/M/L/XL
-- weight_class. Same singleton pattern as pricing_configuration (...047) and
-- package_pricing_configuration (...048): one row, enforced by a
-- unique-on-(true) index, seeded here from the migration, edited in place,
-- never deleted. No branch_id: a 22 kg dog is a 22 kg dog at every branch.
--
-- Bands (lower bound inclusive):
--   S:  weight_kg <  m_min_kg
--   M:  m_min_kg  <= weight_kg < l_min_kg
--   L:  l_min_kg  <= weight_kg < xl_min_kg
--   XL: weight_kg >= xl_min_kg
--
-- Seeded starting values (9.5 / 22 / 41) are a deliberate, non-round starting
-- point for the client to review - not a confirmed rule.

create table public.pet_weight_class_configuration (
  id uuid primary key default gen_random_uuid(),
  m_min_kg numeric(5, 2) not null default 9.50,
  l_min_kg numeric(5, 2) not null default 22.00,
  xl_min_kg numeric(5, 2) not null default 41.00,
  updated_by_staff_id uuid references public.staff_profiles(id),
  updated_at timestamptz not null default now(),
  constraint pet_weight_class_configuration_ordered_check
    check (m_min_kg > 0 and m_min_kg < l_min_kg and l_min_kg < xl_min_kg)
);

create unique index pet_weight_class_configuration_singleton_uniq
  on public.pet_weight_class_configuration((true));

insert into public.pet_weight_class_configuration default values;

comment on table public.pet_weight_class_configuration is
  'Singleton (Admin/Superadmin editable): the kg cut-offs that derive a '
  'pet''s S/M/L/XL weight_class from its recorded weight_kg. Lower bound '
  'inclusive. Seeded values are a starting point for client review.';

alter table public.pet_weight_class_configuration enable row level security;

create policy "Staff can read pet weight class configuration"
  on public.pet_weight_class_configuration
  for select
  to authenticated
  using (public.current_staff_role() is not null);

create policy "Admins and superadmins can manage pet weight class configuration"
  on public.pet_weight_class_configuration
  for all
  to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));


-- ===== NEW: 20260910187_m02_pets_assessment_lock_weight_kg.sql =====

-- Extends enforce_pet_assessment_writes() (last defined in
-- ...20260802075_m02_pets_assessment_trigger_fix.sql) to cover the new
-- pets.weight_kg column. weight_kg drives the derived weight_class, which
-- drives Grooming price and Hotel/Daycare cage size - the exact manipulation
-- vector ...073_m02_pets_assessment_lock.sql closed for weight_class/coat_type.
-- Function body is otherwise a verbatim copy of ...075 - only the three
-- weight_kg clauses are new. The trigger itself is unchanged and not recreated.

create or replace function public.enforce_pet_assessment_writes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  is_assessor boolean := caller is not null and public.current_staff_role() in
    ('Receptionist', 'Admin', 'Supervisor', 'Superadmin');
  is_untrusted_direct_write boolean := caller is not null and not is_assessor;
begin
  if tg_op = 'INSERT' then
    if is_untrusted_direct_write and (
      new.weight_class is not null
      or new.coat_type is not null
      or new.weight_kg is not null
    ) then
      raise exception 'weight_class, coat_type and weight_kg may only be set by staff (Receptionist/Admin/Supervisor/Superadmin) - the pet must be assessed onsite first';
    end if;

    if is_assessor and new.weight_class is not null and new.coat_type is not null then
      new.assessed_by := coalesce(new.assessed_by, caller);
      new.assessed_at := coalesce(new.assessed_at, now());
    end if;

    return new;
  end if;

  -- UPDATE
  if is_untrusted_direct_write and (
    new.weight_class is distinct from old.weight_class
    or new.coat_type is distinct from old.coat_type
    or new.weight_kg is distinct from old.weight_kg
  ) then
    raise exception 'weight_class, coat_type and weight_kg may only be changed by staff (Receptionist/Admin/Supervisor/Superadmin)';
  end if;

  if is_assessor
    and new.weight_class is not null
    and new.coat_type is not null
    and (
      new.weight_class is distinct from old.weight_class
      or new.coat_type is distinct from old.coat_type
    )
  then
    new.assessed_by := caller;
    new.assessed_at := now();
  end if;

  return new;
end;
$$;

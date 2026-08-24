-- Booking flow & pricing revamp (#22) - bundled migrations for manual review/reference.
-- Source of truth is supabase/migrations/; this file mirrors those 5 files concatenated.

-- =============================================================================
-- 20260803084_m05_remove_staff_supplied_billing.sql
-- =============================================================================
-- Booking flow & pricing revamp (#22): staff are no longer allowed to buy
-- food/medication on a customer's behalf (it placed billing/liability risk
-- on staff that the business no longer wants). This removes the "hotel
-- supplies this, bill the customer" path entirely, including for past
-- stays - the historical remaining-balance detail for any stay that used
-- it is lost, but no already-collected total is affected: checkout.service.
-- ts's remainingBalance (and lineItemSources.service.ts's mirrored line
-- items) were always computed live at checkout time, never persisted onto
-- bookings.total_price.

alter table public.care_feeding_instructions
  drop constraint care_feeding_instructions_charge_requires_supplied;

alter table public.care_medication_instructions
  drop constraint care_medication_instructions_charge_requires_supplied;

alter table public.care_feeding_instructions
  drop column brought_by_customer,
  drop column charged_price;

alter table public.care_medication_instructions
  drop column brought_by_customer,
  drop column charged_price;

alter table public.hotel_stays
  drop column supplied_items_charge;

-- =============================================================================
-- 20260803085_m05_m08_product_catalog_customer_ownership.sql
-- =============================================================================
-- Booking flow & pricing revamp (#22): staff no longer buy food/medication
-- for customers (see 20260803084), so customers now maintain their own
-- reusable food/medication "types" for future hotel bookings instead. Rather
-- than build a parallel catalog, this repurposes the existing staff-managed
-- product_catalog (already the shared shape for a named, priced, selectable
-- item) by adding an owner column: null = staff/global entry (unchanged
-- existing behavior, still Admin/Superadmin-only to write), non-null = a
-- customer's own private entry.
--
-- price stays NOT NULL (existing constraint) - customer-owned rows are never
-- billed (no staff-supplied billing exists anymore, see 20260803084), so the
-- API always writes 0 for them; the column is kept rather than made
-- nullable so misc_retail/staff rows keep their existing guarantee.

alter table public.product_catalog
  add column owner_customer_id uuid references public.customer_profiles(id);

-- Replace the blanket (name, category) uniqueness with two partial indexes:
-- global entries keep colliding with each other on (name, category), while
-- customer-owned entries only collide with their own other entries - two
-- different customers (or a customer and the global catalog) may use the
-- same food/medication name.
alter table public.product_catalog drop constraint product_catalog_name_category_key;

create unique index product_catalog_global_name_category_uniq
  on public.product_catalog (name, category)
  where owner_customer_id is null;

create unique index product_catalog_owner_name_category_uniq
  on public.product_catalog (owner_customer_id, name, category)
  where owner_customer_id is not null;

-- Customer-owned rows are restricted to food/medication for hotel bookings
-- only - customers never get a path to misc_retail (the Cashier/POS catalog
-- shares this same table, see 20260731067).
alter table public.product_catalog
  add constraint product_catalog_customer_rows_food_or_medication_hotel_only
  check (
    owner_customer_id is null
    or (category in ('food', 'medication') and service_scope = 'hotel')
  );

-- The original "Any authenticated user can read" policy (20260731067) was
-- written back when every reader was staff; it must be narrowed to staff
-- now that customers are authenticated too, otherwise its `using (true)`
-- would let any customer see every other customer's private catalog rows
-- regardless of the scoped policy added below (permissive RLS policies
-- OR together).
drop policy "Any authenticated user can read the product catalog"
  on public.product_catalog;

create policy "Staff can read the product catalog"
  on public.product_catalog
  for select
  to authenticated
  using (public.current_staff_role() is not null);

create policy "Customers can read their own and global catalog entries"
  on public.product_catalog
  for select
  to authenticated
  using (owner_customer_id is null or owner_customer_id = auth.uid());

create policy "Customers can insert their own catalog entries"
  on public.product_catalog
  for insert
  to authenticated
  with check (owner_customer_id = auth.uid());

create policy "Customers can update their own catalog entries"
  on public.product_catalog
  for update
  to authenticated
  using (owner_customer_id = auth.uid())
  with check (owner_customer_id = auth.uid());

create policy "Customers can delete their own catalog entries"
  on public.product_catalog
  for delete
  to authenticated
  using (owner_customer_id = auth.uid());

-- =============================================================================
-- 20260803086_m05_add_playing_instructions.sql
-- =============================================================================
-- Booking flow & pricing revamp (#22): adds "playtime" as a first-class care
-- instruction alongside feeding/walking/medication - same shape as walking
-- (a time-of-day block + a duration), tracked in its own table rather than
-- folded into care_walking_instructions so the Care Log / check-in flows can
-- keep treating each care type as its own fixed-shape structured form (the
-- same reasoning the original three tables were split out, see
-- 20260727052).
--
-- Also repurposes care_walking_instructions.time_block from a free HH:MM
-- clock-time string to the same Morning/Afternoon/Evening block
-- care_feeding_instructions.meal_time already uses: walk/play scheduling is
-- meant to be minutes-based ("15 min", "10 min"), not literal clock-time
-- ("7:00 AM"), so the new care_playing_instructions table is created with
-- that constraint from the start and the existing walking table is altered
-- to match. Any existing time_block value outside the three labels is
-- coerced to 'Morning' rather than left to violate the new constraint - it
-- was free text before, so there is no reliable way to recover which block
-- was originally meant.

update public.care_walking_instructions
set time_block = 'Morning'
where time_block not in ('Morning', 'Afternoon', 'Evening');

alter table public.care_walking_instructions
  add constraint care_walking_instructions_time_block_check
  check (time_block in ('Morning', 'Afternoon', 'Evening'));

create table public.care_playing_instructions (
  id uuid primary key default gen_random_uuid(),
  hotel_stay_id uuid not null references public.hotel_stays(id) on delete cascade,
  time_block text not null check (time_block in ('Morning', 'Afternoon', 'Evening')),
  duration_minutes integer not null check (duration_minutes > 0),
  notes text
);

create index care_playing_instructions_hotel_stay_id_idx
  on public.care_playing_instructions(hotel_stay_id);

alter table public.care_log_entries
  drop constraint care_log_entries_care_type_check,
  add constraint care_log_entries_care_type_check
  check (care_type in ('Feeding', 'Walking', 'Medication', 'Playing'));

-- RLS: identical shape to care_walking_instructions (20260727052).
alter table public.care_playing_instructions enable row level security;

create policy "Staff can read playing instructions at their branch"
  on public.care_playing_instructions
  for select
  to authenticated
  using (
    public.current_staff_role() in (
      'Receptionist', 'Admin', 'Supervisor', 'Pet Assistant'
    )
    and hotel_stay_id in (
      select hs.id from public.hotel_stays hs
      join public.cages c on c.id = hs.cage_id
      where c.branch_id = (
        select sp.branch_id from public.staff_profiles sp where sp.id = auth.uid()
      )
    )
  );

create policy "Front-desk staff can write playing instructions at their branch"
  on public.care_playing_instructions
  for all
  to authenticated
  using (
    public.current_staff_role() in ('Receptionist', 'Admin', 'Supervisor')
    and hotel_stay_id in (
      select hs.id from public.hotel_stays hs
      join public.cages c on c.id = hs.cage_id
      where c.branch_id = (
        select sp.branch_id from public.staff_profiles sp where sp.id = auth.uid()
      )
    )
  )
  with check (
    public.current_staff_role() in ('Receptionist', 'Admin', 'Supervisor')
    and hotel_stay_id in (
      select hs.id from public.hotel_stays hs
      join public.cages c on c.id = hs.cage_id
      where c.branch_id = (
        select sp.branch_id from public.staff_profiles sp where sp.id = auth.uid()
      )
    )
  );

create policy "Superadmins can manage all playing instructions"
  on public.care_playing_instructions
  for all
  to authenticated
  using (public.current_staff_role() = 'Superadmin')
  with check (public.current_staff_role() = 'Superadmin');

-- =============================================================================
-- 20260803087_m03_m05_hotel_per_night_care.sql
-- =============================================================================
-- Booking flow & pricing revamp (#22): lets a multi-night hotel stay carry
-- different feeding/walking/playing/medication instructions per calendar
-- night instead of one set applied uniformly to every day. stay_date is
-- nullable and additive, not a replacement: null keeps today's behavior
-- unchanged (the row applies to every day of the stay, per
-- careInstructions.service.ts's generateCareLogEntries), while a non-null
-- date scopes the row to that single night only - a customer/receptionist
-- who leaves "same instructions every night" on never produces stay_date
-- values at all, so existing check-in flows and existing rows need no
-- backfill.

alter table public.care_feeding_instructions add column stay_date date;
alter table public.care_walking_instructions add column stay_date date;
alter table public.care_playing_instructions add column stay_date date;
alter table public.care_medication_instructions add column stay_date date;

create index care_feeding_instructions_stay_date_idx
  on public.care_feeding_instructions(hotel_stay_id, stay_date);
create index care_walking_instructions_stay_date_idx
  on public.care_walking_instructions(hotel_stay_id, stay_date);
create index care_playing_instructions_stay_date_idx
  on public.care_playing_instructions(hotel_stay_id, stay_date);
create index care_medication_instructions_stay_date_idx
  on public.care_medication_instructions(hotel_stay_id, stay_date);

-- =============================================================================
-- 20260803088_m08_daycare_overnight_pricing.sql
-- =============================================================================
-- Booking flow & pricing revamp (#22): a daycare pet not picked up before
-- the branch closes now accrues a flat per-night overnight fee on top of
-- the existing first-hour/succeeding-hour charge, e.g. two nights unclaimed
-- = 2 * daycare_overnight_fee + 100 + (succeeding hours * 50). Reuses the
-- existing pricing_configuration singleton (Admin/Superadmin-editable, see
-- 20260726047) rather than a new table - it is already the shared home for
-- an admin-tunable pricing constant.

alter table public.pricing_configuration
  add column daycare_overnight_fee numeric(10, 2) not null default 850.00
  check (daycare_overnight_fee >= 0);


-- Reference copy of the 7 migrations this session added to golden-fur.
-- Source of truth: golden-fur/supabase/migrations/20260913195..201_*.sql
-- (migration 199 shown here is the FIXED version, after splitting the
-- transactions spend-threshold trigger into INSERT/UPDATE variants -
-- see testing.md's Database section for why).

-- ============================================================
-- 20260913195_custom_promos_add_weekly_recurring_type.sql
-- ============================================================
-- Custom change (promo variations, session 86): a second promo "type"
-- alongside the existing date-range one - "every Monday, 10% off Grooming".
--
-- promo_type is a discriminator; existing promos default to 'date_range' so
-- nothing already seeded/created changes behavior. start_date/end_date
-- remain valid (and optional) even for a weekly_recurring promo - they bound
-- an OVERALL campaign window on top of the day-of-week match (both null =
-- recurs indefinitely on those weekdays).
--
-- days_of_week uses 0=Sunday..6=Saturday, matching both JS's
-- Date#getDay()/Date#getUTCDay() and Postgres's extract(dow from ...), so
-- neither side of the stack needs to remap the value.

create type public.promo_type as enum ('date_range', 'weekly_recurring');

alter table public.promos
  add column promo_type public.promo_type not null default 'date_range',
  add column days_of_week integer[];

alter table public.promos
  add constraint promos_days_of_week_valid check (
    days_of_week is null
    or (
      array_length(days_of_week, 1) > 0
      and days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]
    )
  ),
  add constraint promos_weekly_recurring_needs_days check (
    promo_type <> 'weekly_recurring' or days_of_week is not null
  ),
  add constraint promos_date_range_no_days check (
    promo_type = 'weekly_recurring' or days_of_week is null
  );

comment on column public.promos.days_of_week is
  'Only set when promo_type = weekly_recurring. 0=Sunday..6=Saturday '
  '(Manila-local day). start_date/end_date, if set, bound the overall '
  'campaign window IN ADDITION to the day-of-week match; if null the promo '
  'recurs indefinitely on those weekdays.';

-- ============================================================
-- 20260913196_custom_rewards_create_spin_wheel_config_and_rewards.sql
-- ============================================================
-- Custom change (coupon spin wheel, session 86): singleton trigger/pity
-- config + admin-managed reward pool. Singleton pattern mirrors
-- pricing_configuration (20260726047)/promo_cap_configuration (20260726049).
--
-- Real, non-null defaults (not left blank/disabled) so the feature works out
-- of the box the moment this migration runs, in every environment - the
-- same reason promo_cap_configuration/pricing_configuration seed a working
-- default via column DEFAULT + `insert ... default values` rather than a
-- separate seed script (a singleton settings row is schema, not reference
-- data). Still a plain nullable-in-spirit toggle - an admin can raise either
-- threshold arbitrarily high via the config page to effectively disable it.

create table public.spin_wheel_config (
  id uuid primary key default gen_random_uuid(),
  bookings_milestone_interval integer not null default 5
    check (bookings_milestone_interval > 0),
  spend_threshold_amount numeric(10, 2) not null default 5000.00
    check (spend_threshold_amount >= 0),
  pity_threshold integer not null default 10 check (pity_threshold > 0),
  updated_by_staff_id uuid references public.staff_profiles(id),
  updated_at timestamptz not null default now()
);

create unique index spin_wheel_config_singleton_uniq
  on public.spin_wheel_config((true));

insert into public.spin_wheel_config default values;

create table public.spin_wheel_rewards (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  discount_type public.discount_type not null,
  value numeric(10, 2) not null check (value >= 0),
  rarity_percent numeric(5, 2) not null
    check (rarity_percent > 0 and rarity_percent <= 100),
  is_active boolean not null default true,
  archived_at timestamptz,
  created_by uuid references public.staff_profiles(id),
  updated_by uuid references public.staff_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The set of currently-active, non-archived rewards' rarity_percent must sum
-- to exactly 100 (or to 0, meaning the wheel is intentionally left with no
-- active rewards - a temporarily-disabled state, not an error) - checked at
-- COMMIT (deferred), not per-statement, so an admin can edit several rows'
-- percentages in one transaction without a transient false failure.
create or replace function public.check_spin_wheel_rewards_sum()
returns trigger
language plpgsql
as $$
declare
  v_sum numeric;
begin
  select coalesce(sum(rarity_percent), 0) into v_sum
  from public.spin_wheel_rewards
  where is_active and archived_at is null;

  if v_sum <> 0 and round(v_sum, 2) <> 100.00 then
    raise exception
      'Active spin wheel rewards must have rarity percentages summing to 100 (currently %)',
      v_sum;
  end if;

  return null;
end;
$$;

create constraint trigger spin_wheel_rewards_sum_check
  after insert or update or delete on public.spin_wheel_rewards
  deferrable initially deferred
  for each row
  execute function public.check_spin_wheel_rewards_sum();

alter table public.spin_wheel_config enable row level security;
alter table public.spin_wheel_rewards enable row level security;

create policy "Staff can read spin wheel config"
  on public.spin_wheel_config for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Admins and superadmins can manage spin wheel config"
  on public.spin_wheel_config for all to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

-- Customers need to read the reward pool too (the wheel UI renders every
-- active reward as a segment before/while spinning), so this is open to any
-- authenticated user, not gated to current_staff_role() like the two
-- policies above.
create policy "Anyone authenticated can read active spin wheel rewards"
  on public.spin_wheel_rewards for select to authenticated
  using (true);

create policy "Admins and superadmins can manage spin wheel rewards"
  on public.spin_wheel_rewards for all to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

-- ============================================================
-- 20260913197_custom_rewards_create_coupons_milestones_pity.sql
-- ============================================================
-- Custom change (coupon spin wheel, session 86): per-customer running state
-- backing the two spin-credit triggers (next migration) plus the pity
-- counter and the issued coupons themselves.
--
-- No authenticated-role write policy on any of these four tables - only the
-- service-role client (the spin_wheel() RPC, the completion triggers in the
-- next migration, and resolveDiscountAndPromos redeeming a coupon at
-- booking time) ever writes them, mirroring credit_balances/
-- credit_transactions' own "reads are policy-gated, writes go through a
-- SECURITY DEFINER function" shape.

create table public.customer_booking_milestone_progress (
  customer_id uuid primary key references public.customer_profiles(id),
  completed_bookings_count integer not null default 0,
  updated_at timestamptz not null default now()
);

create table public.customer_pity_progress (
  customer_id uuid primary key references public.customer_profiles(id),
  spins_since_last_pity_win integer not null default 0,
  updated_at timestamptz not null default now()
);

-- Ledger of granted-but-not-yet-spun spin credits. Each row is a single
-- spin grant, consumed exactly once by the spin_wheel() RPC.
create table public.customer_spin_credits (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customer_profiles(id),
  source text not null check (source in ('booking_milestone', 'spend_threshold')),
  source_booking_id uuid references public.bookings(id),
  source_transaction_id uuid references public.transactions(id),
  is_consumed boolean not null default false,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (source = 'booking_milestone' and source_booking_id is not null and source_transaction_id is null)
    or (source = 'spend_threshold' and source_transaction_id is not null and source_booking_id is null)
  )
);

create index customer_spin_credits_customer_unconsumed_idx
  on public.customer_spin_credits(customer_id)
  where is_consumed = false;

create table public.customer_coupons (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customer_profiles(id),
  spin_wheel_reward_id uuid references public.spin_wheel_rewards(id),
  -- Snapshotted at issuance so a later reward-catalog edit never changes an
  -- already-issued coupon's value.
  discount_type public.discount_type not null,
  value numeric(10, 2) not null check (value >= 0),
  is_redeemed boolean not null default false,
  redeemed_at timestamptz,
  redeemed_by_booking_id uuid references public.bookings(id),
  redeemed_by_booking_group_id uuid references public.booking_groups(id),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (is_redeemed and redeemed_at is not null)
    or (not is_redeemed and redeemed_at is null
        and redeemed_by_booking_id is null and redeemed_by_booking_group_id is null)
  ),
  check (num_nonnulls(redeemed_by_booking_id, redeemed_by_booking_group_id) <= 1)
);

create index customer_coupons_customer_unredeemed_idx
  on public.customer_coupons(customer_id)
  where is_redeemed = false;

alter table public.customer_booking_milestone_progress enable row level security;
alter table public.customer_pity_progress enable row level security;
alter table public.customer_spin_credits enable row level security;
alter table public.customer_coupons enable row level security;

create policy "Customers can read their own milestone progress"
  on public.customer_booking_milestone_progress for select to authenticated
  using (customer_id = auth.uid());
create policy "Staff can read any milestone progress"
  on public.customer_booking_milestone_progress for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Customers can read their own pity progress"
  on public.customer_pity_progress for select to authenticated
  using (customer_id = auth.uid());
create policy "Staff can read any pity progress"
  on public.customer_pity_progress for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Customers can read their own spin credits"
  on public.customer_spin_credits for select to authenticated
  using (customer_id = auth.uid());
create policy "Staff can read any spin credits"
  on public.customer_spin_credits for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Customers can read their own coupons"
  on public.customer_coupons for select to authenticated
  using (customer_id = auth.uid());
create policy "Staff can read any coupon"
  on public.customer_coupons for select to authenticated
  using (public.current_staff_role() is not null);

-- ============================================================
-- 20260913198_custom_rewards_create_spin_history_and_spin_wheel_rpc.sql
-- ============================================================
-- Custom change (coupon spin wheel, session 86): the atomic "spin the
-- wheel" operation, mirroring issue_credit()/redeem_credit()'s row-lock
-- style (20260805097/20260901155) - consume a spin credit, roll (or apply
-- pity), record history, and issue the resulting coupon, all in one
-- transaction so a race can't double-spend a spin credit or desync the
-- pity counter.

create table public.spin_history (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customer_profiles(id),
  spin_wheel_reward_id uuid not null references public.spin_wheel_rewards(id),
  spin_credit_id uuid not null references public.customer_spin_credits(id),
  was_pity boolean not null default false,
  created_at timestamptz not null default now()
);

create index spin_history_customer_id_idx on public.spin_history(customer_id);

alter table public.spin_history enable row level security;

create policy "Customers can read their own spin history"
  on public.spin_history for select to authenticated
  using (customer_id = auth.uid());
create policy "Staff can read any spin history"
  on public.spin_history for select to authenticated
  using (public.current_staff_role() is not null);

-- Added here (rather than in the previous migration's customer_coupons
-- definition) to avoid a forward reference to spin_history across files.
alter table public.customer_coupons
  add column spin_history_id uuid references public.spin_history(id);

create or replace function public.spin_wheel(p_customer_id uuid)
returns table(reward_id uuid, was_pity boolean, coupon_id uuid, history_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_credit     public.customer_spin_credits;
  v_config     public.spin_wheel_config;
  v_pity       public.customer_pity_progress;
  v_lowest     numeric;
  v_reward     public.spin_wheel_rewards;
  v_roll       numeric;
  v_cumulative numeric := 0;
  v_was_pity   boolean := false;
  v_history_id uuid;
  v_coupon_id  uuid;
begin
  -- skip locked: two concurrent spins for the same customer each grab a
  -- different unconsumed credit rather than one blocking on the other's lock.
  select * into v_credit
  from public.customer_spin_credits
  where customer_id = p_customer_id and is_consumed = false
  order by created_at
  limit 1
  for update skip locked;

  if not found then
    raise exception 'spin_wheel: no available spin credit for customer %', p_customer_id;
  end if;

  select * into v_config from public.spin_wheel_config limit 1;
  if not found then
    raise exception 'spin_wheel: spin_wheel_config has no row';
  end if;

  insert into public.customer_pity_progress (customer_id)
  values (p_customer_id)
  on conflict (customer_id) do nothing;

  select * into v_pity
  from public.customer_pity_progress
  where customer_id = p_customer_id
  for update;

  select min(rarity_percent) into v_lowest
  from public.spin_wheel_rewards
  where is_active and archived_at is null;

  if v_lowest is null then
    raise exception 'spin_wheel: no active rewards configured';
  end if;

  if v_pity.spins_since_last_pity_win >= v_config.pity_threshold then
    v_was_pity := true;

    -- Uniformly random among ties at the lowest rarity.
    select * into v_reward
    from public.spin_wheel_rewards
    where is_active and archived_at is null and rarity_percent = v_lowest
    order by random()
    limit 1;
  else
    v_roll := random() * 100;

    for v_reward in
      select * from public.spin_wheel_rewards
      where is_active and archived_at is null
      order by id
    loop
      v_cumulative := v_cumulative + v_reward.rarity_percent;
      exit when v_roll <= v_cumulative;
    end loop;

    v_was_pity := (v_reward.rarity_percent = v_lowest);
  end if;

  update public.customer_pity_progress
  set spins_since_last_pity_win =
        case when v_was_pity then 0 else spins_since_last_pity_win + 1 end,
      updated_at = now()
  where customer_id = p_customer_id;

  update public.customer_spin_credits
  set is_consumed = true, consumed_at = now()
  where id = v_credit.id;

  insert into public.spin_history (customer_id, spin_wheel_reward_id, spin_credit_id, was_pity)
  values (p_customer_id, v_reward.id, v_credit.id, v_was_pity)
  returning id into v_history_id;

  insert into public.customer_coupons
    (customer_id, spin_wheel_reward_id, spin_history_id, discount_type, value)
  values
    (p_customer_id, v_reward.id, v_history_id, v_reward.discount_type, v_reward.value)
  returning id into v_coupon_id;

  return query select v_reward.id, v_was_pity, v_coupon_id, v_history_id;
end;
$$;

revoke all on function public.spin_wheel(uuid) from public;
grant execute on function public.spin_wheel(uuid) to service_role;

-- ============================================================
-- 20260913199_custom_rewards_create_completion_triggers.sql
-- ============================================================
-- Custom change (coupon spin wheel, session 86): grants a spin credit
-- whenever a customer's running completed-bookings count crosses a
-- multiple of spin_wheel_config.bookings_milestone_interval (a REPEATING
-- milestone - every Nth completed booking, indefinitely, never one-time),
-- and separately whenever a single transaction is fully paid for at least
-- spin_wheel_config.spend_threshold_amount.
--
-- Trigger-based rather than a call added into every "mark
-- Completed"/"mark Fully Paid" call site: booking completion is set
-- independently from several service files (booking.service.ts,
-- daycareBilling.service.ts, hotel/services/checkout.service.ts,
-- careLogCompletion.service.ts) and a DB trigger can't be missed by a new
-- one added later.

create or replace function public.trg_increment_booking_milestone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_config    public.spin_wheel_config;
  v_new_count integer;
begin
  select * into v_config from public.spin_wheel_config limit 1;

  insert into public.customer_booking_milestone_progress (customer_id)
  values (new.customer_id)
  on conflict (customer_id) do nothing;

  update public.customer_booking_milestone_progress
  set completed_bookings_count = completed_bookings_count + 1,
      updated_at = now()
  where customer_id = new.customer_id
  returning completed_bookings_count into v_new_count;

  if v_new_count % v_config.bookings_milestone_interval = 0 then
    insert into public.customer_spin_credits (customer_id, source, source_booking_id)
    values (new.customer_id, 'booking_milestone', new.id);
  end if;

  return new;
end;
$$;

create trigger bookings_completed_milestone
  after update of status on public.bookings
  for each row
  when (new.status = 'Completed' and old.status is distinct from 'Completed')
  execute function public.trg_increment_booking_milestone();

-- Needs to fire on INSERT too (a cash sale can insert already-'Fully
-- Paid'), not just UPDATE - but Postgres forbids an INSERT trigger's WHEN
-- clause from referencing OLD at all (even combined with UPDATE in one
-- trigger, and even though OLD is conceptually NULL on INSERT) - SQLSTATE
-- 42P17. So this is two separate triggers on the same function instead of
-- one INSERT-OR-UPDATE trigger: the INSERT one has no OLD comparison to
-- make (a freshly inserted row can't have had a prior status), the UPDATE
-- one keeps the OLD/NEW transition check so an already-'Fully Paid' row
-- doesn't grant a second credit on every unrelated update.
create or replace function public.trg_spend_threshold_spin_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_config public.spin_wheel_config;
begin
  select * into v_config from public.spin_wheel_config limit 1;

  if new.total_amount >= v_config.spend_threshold_amount then
    insert into public.customer_spin_credits (customer_id, source, source_transaction_id)
    values (new.customer_id, 'spend_threshold', new.id);
  end if;

  return new;
end;
$$;

create trigger transactions_spend_threshold_spin_credit_insert
  after insert on public.transactions
  for each row
  when (new.payment_status = 'Fully Paid')
  execute function public.trg_spend_threshold_spin_credit();

create trigger transactions_spend_threshold_spin_credit_update
  after update of payment_status on public.transactions
  for each row
  when (new.payment_status = 'Fully Paid'
        and old.payment_status is distinct from 'Fully Paid')
  execute function public.trg_spend_threshold_spin_credit();

-- ============================================================
-- 20260913200_custom_booking_create_booking_promo_selections.sql
-- ============================================================
-- Custom change (promos/coupons multiselect booking step, session 86):
-- booking-time promo/coupon selection moves from a single FK
-- (bookings.selected_promo_id / booking_groups.selected_promo_id) to a
-- one-row-per-selection table, so a customer/receptionist can pick several
-- promos and/or coupons on one booking, capped the same way the cashier's
-- checkout-time evaluatePromos already caps multiple auto-applied promos.
--
-- Those two selected_promo_id columns and their promo_amount columns are
-- left in place - promo_amount becomes the SUM across this table's rows for
-- a given booking/group, and selected_promo_id is simply no longer written
-- by new bookings (kept only so already-existing rows keep displaying).
--
-- Deliberately a NEW table rather than repurposing transaction_promo_selections:
-- that table is a checkout-time audit log keyed by transaction_id (a
-- different lifecycle/owner - it only exists once a transaction is
-- recorded); this one is the booking/booking_group-scoped "what was locked
-- in", which exists from booking creation onward, well before any
-- transaction.

create table public.booking_promo_selections (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings(id) on delete cascade,
  booking_group_id uuid references public.booking_groups(id) on delete cascade,
  promo_id uuid references public.promos(id),
  customer_coupon_id uuid references public.customer_coupons(id),
  applied_amount numeric(10, 2) not null check (applied_amount >= 0),
  created_at timestamptz not null default now(),
  check (num_nonnulls(booking_id, booking_group_id) = 1),
  check (num_nonnulls(promo_id, customer_coupon_id) = 1)
);

create index booking_promo_selections_booking_id_idx
  on public.booking_promo_selections(booking_id);
create index booking_promo_selections_booking_group_id_idx
  on public.booking_promo_selections(booking_group_id);
-- A coupon can be locked into at most one booking/group, ever (belt-and-
-- suspenders alongside customer_coupons.is_redeemed).
create unique index booking_promo_selections_coupon_uniq
  on public.booking_promo_selections(customer_coupon_id)
  where customer_coupon_id is not null;

alter table public.booking_promo_selections enable row level security;

create policy "Customers can read their own booking promo selections"
  on public.booking_promo_selections for select to authenticated
  using (
    exists (
      select 1 from public.bookings b
      where b.id = booking_id and b.customer_id = auth.uid()
    )
    or exists (
      select 1 from public.booking_groups g
      where g.id = booking_group_id and g.customer_id = auth.uid()
    )
  );

create policy "Staff can read any booking promo selection"
  on public.booking_promo_selections for select to authenticated
  using (public.current_staff_role() is not null);
-- No authenticated write policy - only the server's service-role client
-- (resolveDiscountAndPromos / bookingGroup.service.ts) writes this table.

-- Widen the checkout-time audit table to also be able to record a redeemed
-- coupon (kept as its own table per the note above - this only widens what
-- it can point at).
alter table public.transaction_promo_selections
  alter column promo_id drop not null,
  add column customer_coupon_id uuid references public.customer_coupons(id);

alter table public.transaction_promo_selections
  add constraint transaction_promo_selections_one_target check (
    num_nonnulls(promo_id, customer_coupon_id) = 1
  );

create index transaction_promo_selections_coupon_id_idx
  on public.transaction_promo_selections(customer_coupon_id);

-- ============================================================
-- 20260913201_custom_notification_event_type_add_spin_wheel_earned.sql
-- ============================================================
-- Custom change (coupon spin wheel, session 86): adds the notification
-- event fired when a customer earns a new spin credit (booking milestone or
-- spend threshold), so they see a "You earned a spin!" notification linking
-- to My Rewards.
--
-- Must be its own migration: Postgres forbids using a value added by ADD
-- VALUE in the same transaction it was added in - same isolation already
-- used by 20260814124/20260819137/20260911189's own notification_event_type
-- additions.

alter type public.notification_event_type add value 'spin_wheel_earned';


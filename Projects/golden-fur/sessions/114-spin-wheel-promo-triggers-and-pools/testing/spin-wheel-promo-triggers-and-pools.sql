-- Reference copy of the 8 migrations this session added to golden-fur.
-- Source of truth: golden-fur/supabase/migrations/20260925208..215_*.sql
--
-- All 8 have been pushed to and verified live against the dev project
-- (hikgijuipymfghfuyrjv) - see testing.md's "Database" and "Database-level
-- checks" sections. Migration 209 below includes a real ordering fix found
-- during that push (DROP TRIGGER moved before the backfill UPDATE) - see
-- its own comment. The verification queries actually run against dev are
-- appended at the bottom of this file.

-- ============================================================
-- 20260925208_custom_promos_promo_type_add_spin_wheel.sql
-- ============================================================
-- Custom change (session 114): the coupon spin wheel becomes a promo TYPE
-- instead of a standalone settings page - "Add New Promo > Coupon Spin
-- Wheel" in the existing promo builder wizard.
--
-- Its own file, same as 20260913201: a value added by ALTER TYPE ... ADD
-- VALUE can't be referenced (CHECKs, inserts, comparisons) until the
-- transaction that added it has committed, and the follow-up migrations in
-- this session all reference 'spin_wheel'.

alter type public.promo_type add value if not exists 'spin_wheel';

-- ============================================================
-- 20260925209_custom_rewards_rarity_tiers_and_weights.sql
-- ============================================================
-- Custom change (session 114): "As an admin, I want to be able to freely add
-- a coupon spin wheel reward and configure its rarity without having to
-- manually adjust everything to make it total to 100%."
--
-- rarity_percent (every active reward's % had to sum to exactly 100) is
-- replaced by two independent fields:
--   * rarity_tier - a display/pity label, Common..Legendary. The enum's
--     declaration order IS the rarity order, so max(rarity_tier) is the
--     rarest tier present in a set of rewards.
--   * weight      - a free positive number. A reward's chance of landing is
--     computed per reward pool as weight / sum(active weights in that pool),
--     so adding or deactivating one reward never requires touching another.
--
-- The deferred sum-to-100 constraint trigger from 20260913196 is dropped:
-- besides the ask above, it made the single-row admin API unable to add or
-- deactivate any reward once the catalog summed to 100 (each PostgREST call
-- is its own transaction, so the "deferred" check still ran after every
-- single write).
--
-- rarity_percent itself is kept until 20260925215 so the old spin_wheel()
-- body stays valid until 20260925214 replaces it.

create type public.reward_rarity_tier as enum (
  'Common',
  'Uncommon',
  'Rare',
  'Epic',
  'Legendary'
);

alter table public.spin_wheel_rewards
  add column rarity_tier public.reward_rarity_tier,
  add column weight numeric(10, 2) check (weight > 0);

-- Dropped BEFORE the backfill UPDATE below, not after: this trigger is
-- DEFERRABLE INITIALLY DEFERRED, so an UPDATE against this table queues a
-- pending trigger event rather than firing immediately. Postgres then
-- refuses any ALTER COLUMN on the table for the rest of the transaction
-- while that event is pending ("cannot ALTER TABLE ... because it has
-- pending trigger events", SQLSTATE 55006) - so the trigger has to be gone
-- before the UPDATE fires it, not merely before the ALTER COLUMN runs.
-- (Found by actually pushing this migration to dev - the mocked
-- service-layer tests never exercise real trigger/transaction semantics.)
drop trigger if exists spin_wheel_rewards_sum_check on public.spin_wheel_rewards;
drop function if exists public.check_spin_wheel_rewards_sum();

-- weight = the old percent keeps every existing reward's exact odds; the
-- tier is derived from how rare the old percent was.
update public.spin_wheel_rewards
set weight = rarity_percent,
    rarity_tier = case
      when rarity_percent >= 30 then 'Common'
      when rarity_percent >= 15 then 'Uncommon'
      when rarity_percent >= 10 then 'Rare'
      when rarity_percent > 5 then 'Epic'
      else 'Legendary'
    end::public.reward_rarity_tier;

alter table public.spin_wheel_rewards
  alter column rarity_tier set not null,
  alter column rarity_tier set default 'Common',
  alter column weight set not null,
  alter column weight set default 10,
  alter column rarity_percent drop not null;

-- ============================================================
-- 20260925210_custom_rewards_create_reward_pools.sql
-- ============================================================
-- Custom change (session 114): "I also want to be able to create multiple
-- reward pools, and assign trigger conditions to them (ex: monthly login
-- triggers a reward pool that consists of only rare rewards)."
--
-- A reward pool is a named set of spin_wheel_rewards. One reward can sit in
-- any number of pools; each spin-wheel promo (20260925211) draws from
-- exactly one pool. Chance-of-landing is computed per pool from the member
-- rewards' weights (20260925209), never stored.
--
-- Same deactivate-then-archive shape as every other admin catalog
-- (is_active + archived_at, 20260731071/072).

create table public.reward_pools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  description text,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_by uuid references public.staff_profiles(id),
  updated_by uuid references public.staff_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index reward_pools_name_live_uniq
  on public.reward_pools (lower(name))
  where archived_at is null;

create table public.reward_pool_rewards (
  reward_pool_id uuid not null
    references public.reward_pools(id) on delete cascade,
  spin_wheel_reward_id uuid not null
    references public.spin_wheel_rewards(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reward_pool_id, spin_wheel_reward_id)
);

create index reward_pool_rewards_reward_idx
  on public.reward_pool_rewards (spin_wheel_reward_id);

alter table public.reward_pools enable row level security;
alter table public.reward_pool_rewards enable row level security;

-- Staff-only reads: customers never read pools directly - the per-promo
-- wheel endpoint (server, service role) returns the pool's rewards with
-- their computed chances.
create policy "Staff can read reward pools"
  on public.reward_pools for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Admins and superadmins can manage reward pools"
  on public.reward_pools for all to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

create policy "Staff can read reward pool members"
  on public.reward_pool_rewards for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Admins and superadmins can manage reward pool members"
  on public.reward_pool_rewards for all to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

-- Universal deleted-records archive (20260913202 convention).
create trigger trg_archive_deleted_row
  after delete on public.reward_pools
  for each row execute function public.archive_deleted_row();

create trigger trg_archive_deleted_row
  after delete on public.reward_pool_rewards
  for each row execute function public.archive_deleted_row();

-- ============================================================
-- 20260925211_custom_promos_spin_wheel_settings.sql
-- ============================================================
-- Custom change (session 114): per-promo settings for promo_type =
-- 'spin_wheel' - which reward pool it draws from, its pity threshold, and
-- its trigger conditions ("after every X completed bookings, daily login,
-- consecutive logins per week, consecutive logins per month").
--
-- A spin-wheel promo has no discount of its own (the rewards in its pool do),
-- so discount_type/value/scope_type become nullable - but ONLY for that type,
-- enforced by promos_spin_wheel_no_discount below. Existing CHECKs
-- (value >= 0, scope_type in (...)) already pass on NULL.
--
-- Spin-wheel promos have no promo_branch_availability rows: their booking /
-- spend / login triggers are customer-wide, not per-branch.
--
-- Trigger conditions are COLUMNS on one row rather than rows in a child
-- table: a single login_trigger column makes "some conditions should not be
-- able to be enabled at the same time" (daily login vs weekly streak vs
-- monthly streak) structurally impossible to violate, while the booking and
-- spend triggers stay freely combinable with anything.

alter table public.promos
  alter column discount_type drop not null,
  alter column value drop not null,
  alter column scope_type drop not null;

alter table public.promos
  add constraint promos_spin_wheel_no_discount check (
    (promo_type = 'spin_wheel')
      = (discount_type is null and value is null and scope_type is null)
  ),
  add constraint promos_spin_wheel_no_condition check (
    promo_type <> 'spin_wheel' or condition_note is null
  );

create table public.spin_wheel_promo_settings (
  promo_id uuid primary key references public.promos(id) on delete cascade,
  reward_pool_id uuid not null
    references public.reward_pools(id) on delete restrict,
  -- NULL = no pity. Otherwise: after this many spins in a row without
  -- landing the pool's rarest tier, the next spin is guaranteed to.
  pity_threshold integer check (pity_threshold > 0),
  -- Every Nth completed booking (lifetime count, repeating).
  booking_milestone_interval integer check (booking_milestone_interval > 0),
  -- One spin when a single transaction is fully paid for at least this much.
  spend_threshold_amount numeric(10, 2) check (spend_threshold_amount > 0),
  login_trigger text check (
    login_trigger in ('daily_login', 'weekly_login_streak', 'monthly_login_streak')
  ),
  -- N consecutive login days within the current Manila calendar week
  -- (Mon-Sun) or month. Only for the two streak triggers.
  login_streak_days integer,
  updated_at timestamptz not null default now(),
  constraint spin_wheel_promo_settings_has_trigger check (
    num_nonnulls(booking_milestone_interval, spend_threshold_amount, login_trigger) >= 1
  ),
  -- coalesce: a CHECK that evaluates to NULL passes, so a streak trigger
  -- with a NULL day count must be forced to false explicitly.
  constraint spin_wheel_promo_settings_streak_days check (
    case login_trigger
      when 'weekly_login_streak' then coalesce(login_streak_days between 1 and 7, false)
      when 'monthly_login_streak' then coalesce(login_streak_days between 1 and 31, false)
      else login_streak_days is null
    end
  )
);

create index spin_wheel_promo_settings_pool_idx
  on public.spin_wheel_promo_settings (reward_pool_id);

alter table public.spin_wheel_promo_settings enable row level security;

create policy "Staff can read spin wheel promo settings"
  on public.spin_wheel_promo_settings for select to authenticated
  using (public.current_staff_role() is not null);

create policy "Admins and superadmins can manage spin wheel promo settings"
  on public.spin_wheel_promo_settings for all to authenticated
  using (public.current_staff_role() in ('Admin', 'Superadmin'))
  with check (public.current_staff_role() in ('Admin', 'Superadmin'));

create trigger trg_archive_deleted_row
  after delete on public.spin_wheel_promo_settings
  for each row execute function public.archive_deleted_row();

-- ============================================================
-- 20260925212_custom_rewards_login_days_and_credit_sources.sql
-- ============================================================
-- Custom change (session 114): login tracking for the daily-login /
-- weekly-streak / monthly-streak spin triggers, and per-promo spin credits.
--
-- customer_login_days: one row per customer per Manila calendar day they
-- opened the customer portal (written only by record_customer_login(),
-- 20260925214, via the server's check-in endpoint). A day, not a login
-- event, because sessions persist - a returning customer who never types
-- their password again still "logged in" that day.
--
-- customer_spin_credits gains promo_id (which spin-wheel promo granted it,
-- and so which reward pool it spins) and period_key (the day / ISO week /
-- month a login-based credit was granted for). The partial unique index on
-- period_key makes every login grant idempotent: the same login period can
-- never grant the same promo two spins, however many times the customer
-- checks in.
--
-- promo_id stays nullable here; 20260925213 backfills it and 20260925214
-- sets NOT NULL together with the trigger rewrite.

create table public.customer_login_days (
  customer_id uuid not null references public.customer_profiles(id),
  login_date date not null,
  created_at timestamptz not null default now(),
  primary key (customer_id, login_date)
);

alter table public.customer_login_days enable row level security;

create policy "Customers can read their own login days"
  on public.customer_login_days for select to authenticated
  using (customer_id = auth.uid());
create policy "Staff can read any login days"
  on public.customer_login_days for select to authenticated
  using (public.current_staff_role() is not null);

create trigger trg_archive_deleted_row
  after delete on public.customer_login_days
  for each row execute function public.archive_deleted_row();

-- The two original CHECKs on customer_spin_credits (20260913197) were
-- declared inline without names - look them up rather than guess Postgres's
-- generated names.
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.customer_spin_credits'::regclass
      and contype = 'c'
  loop
    execute format(
      'alter table public.customer_spin_credits drop constraint %I',
      r.conname
    );
  end loop;
end $$;

alter table public.customer_spin_credits
  add column promo_id uuid references public.promos(id),
  add column period_key text;

alter table public.customer_spin_credits
  add constraint customer_spin_credits_source_valid check (
    source in (
      'booking_milestone',
      'spend_threshold',
      'daily_login',
      'weekly_login_streak',
      'monthly_login_streak'
    )
  ),
  add constraint customer_spin_credits_source_refs check (
    (source = 'booking_milestone'
      and source_booking_id is not null
      and source_transaction_id is null
      and period_key is null)
    or (source = 'spend_threshold'
      and source_transaction_id is not null
      and source_booking_id is null
      and period_key is null)
    or (source in ('daily_login', 'weekly_login_streak', 'monthly_login_streak')
      and source_booking_id is null
      and source_transaction_id is null
      and period_key is not null)
  );

-- Deliberately NO unique index on (promo_id, source_booking_id) /
-- (promo_id, source_transaction_id): the booking/spend triggers already
-- only fire on the transition INTO Completed / Fully Paid (their WHEN
-- clauses, unchanged from 20260913199), and the pre-existing credit rows
-- were never constrained that way - a booking re-completed after being
-- reopened could already hold two credits, which would make 20260925213's
-- backfill (every old credit -> the one "Loyalty Spin" promo) violate such
-- an index and fail the migration on a real database.
create unique index customer_spin_credits_period_uniq
  on public.customer_spin_credits (customer_id, promo_id, source, period_key)
  where period_key is not null;

create index customer_spin_credits_customer_promo_unconsumed_idx
  on public.customer_spin_credits (customer_id, promo_id)
  where is_consumed = false;

alter table public.customer_pity_progress
  add column promo_id uuid references public.promos(id);

alter table public.spin_history
  add column promo_id uuid references public.promos(id),
  add column reward_pool_id uuid references public.reward_pools(id);

-- ============================================================
-- 20260925213_custom_rewards_backfill_standard_pool_and_loyalty_promo.sql
-- ============================================================
-- Custom change (session 114): converts the old single, global spin wheel
-- into the new promo + pool shape, in EVERY environment. This is a migration,
-- not a seed, on purpose: seeds only run on `supabase db reset`, never on
-- `db push`, so the provisioned dev/prod databases would otherwise be left
-- with credits pointing at no promo.
--
--   * a "Standard" reward pool containing every non-archived reward that
--     exists right now (may be zero on a fresh `db reset`, where migrations
--     run before seeds - the custom-rewards seed attaches its rewards to
--     this pool by name),
--   * a "Loyalty Spin" spin-wheel promo carrying the old spin_wheel_config
--     numbers (every N completed bookings, single-transaction spend, pity),
--   * every existing spin credit / pity counter / spin history row is
--     pointed at that promo, so no customer loses an earned spin.

do $$
declare
  v_config   public.spin_wheel_config;
  v_pool_id  uuid;
  v_promo_id uuid;
begin
  select * into v_config from public.spin_wheel_config limit 1;

  insert into public.reward_pools (name, description)
  values (
    'Standard',
    'The original spin wheel reward list, converted automatically when reward pools were introduced.'
  )
  returning id into v_pool_id;

  insert into public.reward_pool_rewards (reward_pool_id, spin_wheel_reward_id)
  select v_pool_id, id
  from public.spin_wheel_rewards
  where archived_at is null;

  insert into public.promos (name, promo_type, is_active)
  values ('Loyalty Spin', 'spin_wheel', true)
  returning id into v_promo_id;

  insert into public.spin_wheel_promo_settings (
    promo_id,
    reward_pool_id,
    pity_threshold,
    booking_milestone_interval,
    spend_threshold_amount
  )
  values (
    v_promo_id,
    v_pool_id,
    coalesce(v_config.pity_threshold, 10),
    coalesce(v_config.bookings_milestone_interval, 5),
    -- The new column requires > 0; an old 0 threshold meant "every fully
    -- paid transaction", which the booking trigger alone now covers better.
    nullif(coalesce(v_config.spend_threshold_amount, 5000.00), 0)
  );

  update public.customer_spin_credits
  set promo_id = v_promo_id
  where promo_id is null;

  update public.customer_pity_progress
  set promo_id = v_promo_id
  where promo_id is null;

  update public.spin_history
  set promo_id = v_promo_id,
      reward_pool_id = v_pool_id
  where promo_id is null;
end $$;

-- ============================================================
-- 20260925214_custom_rewards_rewrite_spin_wheel_rpc_and_grant_triggers.sql
-- ============================================================
-- Custom change (session 114): the spin-wheel engine, rewritten for
-- multiple spin-wheel promos, each with its own reward pool, pity threshold
-- and trigger conditions (20260925211).
--
--   * spin_wheel_promo_is_live()  - is this promo currently granting spins?
--   * grant_spin_credit()         - idempotent single-credit insert.
--   * trg_increment_booking_milestone / trg_spend_threshold_spin_credit -
--     same triggers as 20260913199, now looping every live promo instead of
--     reading one global spin_wheel_config row.
--   * record_customer_login()     - records today's portal visit and grants
--     any due daily-login / weekly-streak / monthly-streak spins.
--   * spin_wheel()                - weighted roll over the credit's promo's
--     pool; pity is tracked per (customer, promo) and guarantees the pool's
--     RAREST TIER (max(rarity_tier)).
--
-- Every "which day is it" decision uses Asia/Manila, same convention as
-- 20260902160 - never the client clock.

-- ---------------------------------------------------------------------------
-- Backfilled in 20260925213; required from here on.
-- ---------------------------------------------------------------------------

alter table public.customer_spin_credits
  alter column promo_id set not null;

alter table public.spin_history
  alter column promo_id set not null;

delete from public.customer_pity_progress where promo_id is null;

alter table public.customer_pity_progress
  alter column promo_id set not null,
  drop constraint customer_pity_progress_pkey,
  add primary key (customer_id, promo_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.spin_wheel_promo_is_live(
  p_promo_id uuid,
  p_today date
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.promos p
    join public.spin_wheel_promo_settings s on s.promo_id = p.id
    join public.reward_pools rp on rp.id = s.reward_pool_id
    where p.id = p_promo_id
      and p.promo_type = 'spin_wheel'
      and p.is_active
      and p.archived_at is null
      and (p.start_date is null or p.start_date <= p_today)
      and (p.end_date is null or p.end_date >= p_today)
      and rp.is_active
      and rp.archived_at is null
      and exists (
        select 1
        from public.reward_pool_rewards m
        join public.spin_wheel_rewards r on r.id = m.spin_wheel_reward_id
        where m.reward_pool_id = rp.id
          and r.is_active
          and r.archived_at is null
      )
  );
$$;

-- ON CONFLICT DO NOTHING with no target: the customer+promo+source+period
-- partial unique index from 20260925212 turns a repeat login grant into a
-- no-op, and the NULL return tells the caller nothing new was granted.
-- (Booking/spend grants rely on their triggers' transition-only WHEN
-- clauses instead - see 20260925212's note.)
create or replace function public.grant_spin_credit(
  p_customer_id uuid,
  p_promo_id uuid,
  p_source text,
  p_booking_id uuid,
  p_transaction_id uuid,
  p_period_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.customer_spin_credits (
    customer_id, promo_id, source, source_booking_id, source_transaction_id, period_key
  )
  values (
    p_customer_id, p_promo_id, p_source, p_booking_id, p_transaction_id, p_period_key
  )
  on conflict do nothing
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.spin_wheel_promo_is_live(uuid, date) from public;
revoke all on function public.grant_spin_credit(uuid, uuid, text, uuid, uuid, text) from public;

-- ---------------------------------------------------------------------------
-- Booking / spend triggers (trigger definitions from 20260913199 unchanged -
-- only the functions they call are replaced).
-- ---------------------------------------------------------------------------

create or replace function public.trg_increment_booking_milestone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today     date := (now() at time zone 'Asia/Manila')::date;
  v_new_count integer;
  v_settings  record;
begin
  insert into public.customer_booking_milestone_progress (customer_id)
  values (new.customer_id)
  on conflict (customer_id) do nothing;

  -- One lifetime counter per customer, shared by every promo: "every Nth
  -- completed booking" for each promo's own N.
  update public.customer_booking_milestone_progress
  set completed_bookings_count = completed_bookings_count + 1,
      updated_at = now()
  where customer_id = new.customer_id
  returning completed_bookings_count into v_new_count;

  for v_settings in
    select s.promo_id, s.booking_milestone_interval
    from public.spin_wheel_promo_settings s
    where s.booking_milestone_interval is not null
      and public.spin_wheel_promo_is_live(s.promo_id, v_today)
  loop
    if v_new_count % v_settings.booking_milestone_interval = 0 then
      perform public.grant_spin_credit(
        new.customer_id, v_settings.promo_id, 'booking_milestone', new.id, null, null
      );
    end if;
  end loop;

  return new;
end;
$$;

create or replace function public.trg_spend_threshold_spin_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today    date := (now() at time zone 'Asia/Manila')::date;
  v_settings record;
begin
  for v_settings in
    select s.promo_id
    from public.spin_wheel_promo_settings s
    where s.spend_threshold_amount is not null
      and new.total_amount >= s.spend_threshold_amount
      and public.spin_wheel_promo_is_live(s.promo_id, v_today)
  loop
    perform public.grant_spin_credit(
      new.customer_id, v_settings.promo_id, 'spend_threshold', null, new.id, null
    );
  end loop;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Login check-in
-- ---------------------------------------------------------------------------

-- Output columns are prefixed granted_* so they can't collide with the
-- promo_id/source table columns referenced inside the body.
create or replace function public.record_customer_login(p_customer_id uuid)
returns table(granted_promo_id uuid, granted_source text, granted_credit_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today        date := (now() at time zone 'Asia/Manila')::date;
  v_settings     record;
  v_period_start date;
  v_floor        date;
  v_period_key   text;
  v_run          integer;
  v_day          date;
  v_credit_id    uuid;
begin
  insert into public.customer_login_days (customer_id, login_date)
  values (p_customer_id, v_today)
  on conflict do nothing;

  for v_settings in
    select s.promo_id,
           s.login_trigger,
           s.login_streak_days,
           p.start_date,
           p.created_at
    from public.spin_wheel_promo_settings s
    join public.promos p on p.id = s.promo_id
    where s.login_trigger is not null
      and public.spin_wheel_promo_is_live(s.promo_id, v_today)
  loop
    v_credit_id := null;

    if v_settings.login_trigger = 'daily_login' then
      v_period_key := to_char(v_today, 'YYYY-MM-DD');
      v_credit_id := public.grant_spin_credit(
        p_customer_id, v_settings.promo_id, 'daily_login', null, null, v_period_key
      );
    else
      if v_settings.login_trigger = 'weekly_login_streak' then
        -- ISO week: Monday..Sunday.
        v_period_start := date_trunc('week', v_today)::date;
        v_period_key := to_char(v_today, 'IYYY-"W"IW');
      else
        v_period_start := date_trunc('month', v_today)::date;
        v_period_key := to_char(v_today, 'YYYY-MM');
      end if;

      -- A streak never counts days from before the promo started, so a new
      -- promo doesn't instantly pay out for visits made before it existed.
      v_floor := greatest(
        v_period_start,
        coalesce(
          v_settings.start_date,
          (v_settings.created_at at time zone 'Asia/Manila')::date
        )
      );

      -- Consecutive run of login days ending today, within the period.
      v_run := 0;
      v_day := v_today;
      while v_day >= v_floor and exists (
        select 1
        from public.customer_login_days d
        where d.customer_id = p_customer_id
          and d.login_date = v_day
      ) loop
        v_run := v_run + 1;
        v_day := v_day - 1;
      end loop;

      if v_run >= v_settings.login_streak_days then
        v_credit_id := public.grant_spin_credit(
          p_customer_id, v_settings.promo_id, v_settings.login_trigger, null, null, v_period_key
        );
      end if;
    end if;

    if v_credit_id is not null then
      granted_promo_id := v_settings.promo_id;
      granted_source := v_settings.login_trigger;
      granted_credit_id := v_credit_id;
      return next;
    end if;
  end loop;
end;
$$;

revoke all on function public.record_customer_login(uuid) from public;
grant execute on function public.record_customer_login(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- spin_wheel(): the signature changes, so the old one-arg function must be
-- dropped first - `create or replace` with a new arg list would add a second
-- overload and make the server's rpc('spin_wheel', {p_customer_id}) call
-- ambiguous.
-- ---------------------------------------------------------------------------

drop function if exists public.spin_wheel(uuid);

create function public.spin_wheel(
  p_customer_id uuid,
  p_promo_id uuid default null
)
returns table(
  reward_id uuid,
  was_pity boolean,
  coupon_id uuid,
  history_id uuid,
  wheel_promo_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_credit     public.customer_spin_credits;
  v_settings   public.spin_wheel_promo_settings;
  v_pity       public.customer_pity_progress;
  v_rarest     public.reward_rarity_tier;
  v_total      numeric;
  v_reward     public.spin_wheel_rewards;
  v_roll       numeric;
  v_cumulative numeric := 0;
  v_was_pity   boolean := false;
  v_pity_hit   boolean;
  v_history_id uuid;
  v_coupon_id  uuid;
begin
  -- skip locked: two concurrent spins for the same customer each grab a
  -- different unconsumed credit rather than one blocking on the other's lock.
  select c.* into v_credit
  from public.customer_spin_credits c
  where c.customer_id = p_customer_id
    and c.is_consumed = false
    and (p_promo_id is null or c.promo_id = p_promo_id)
  order by c.created_at
  limit 1
  for update skip locked;

  if not found then
    raise exception 'spin_wheel: no available spin credit for customer %', p_customer_id;
  end if;

  select s.* into v_settings
  from public.spin_wheel_promo_settings s
  where s.promo_id = v_credit.promo_id;

  if not found then
    raise exception 'spin_wheel: promo % has no spin wheel settings', v_credit.promo_id;
  end if;

  -- An already-earned credit can still be spun after its promo is
  -- deactivated/archived ("earned is earned") - only an empty pool blocks
  -- it, and the raise rolls back so the credit stays unconsumed.
  select max(r.rarity_tier), sum(r.weight) into v_rarest, v_total
  from public.reward_pool_rewards m
  join public.spin_wheel_rewards r on r.id = m.spin_wheel_reward_id
  where m.reward_pool_id = v_settings.reward_pool_id
    and r.is_active
    and r.archived_at is null;

  if v_rarest is null then
    raise exception 'spin_wheel: reward pool has no active rewards';
  end if;

  insert into public.customer_pity_progress (customer_id, promo_id)
  values (p_customer_id, v_credit.promo_id)
  on conflict (customer_id, promo_id) do nothing;

  select pp.* into v_pity
  from public.customer_pity_progress pp
  where pp.customer_id = p_customer_id
    and pp.promo_id = v_credit.promo_id
  for update;

  v_pity_hit := v_settings.pity_threshold is not null
    and v_pity.spins_since_last_pity_win >= v_settings.pity_threshold;

  if v_pity_hit then
    -- Weighted pick among the rarest tier only.
    select sum(r.weight) into v_total
    from public.reward_pool_rewards m
    join public.spin_wheel_rewards r on r.id = m.spin_wheel_reward_id
    where m.reward_pool_id = v_settings.reward_pool_id
      and r.is_active
      and r.archived_at is null
      and r.rarity_tier = v_rarest;
  end if;

  v_roll := random() * v_total;

  -- Cumulative-weight walk. If float rounding ever leaves v_roll >= the
  -- final total, the loop ends on (and keeps) the last row.
  for v_reward in
    select r.*
    from public.reward_pool_rewards m
    join public.spin_wheel_rewards r on r.id = m.spin_wheel_reward_id
    where m.reward_pool_id = v_settings.reward_pool_id
      and r.is_active
      and r.archived_at is null
      and (not v_pity_hit or r.rarity_tier = v_rarest)
    order by r.id
  loop
    v_cumulative := v_cumulative + v_reward.weight;
    exit when v_roll < v_cumulative;
  end loop;

  -- A natural hit on the rarest tier also resets the pity counter.
  v_was_pity := (v_reward.rarity_tier = v_rarest);

  update public.customer_pity_progress pp
  set spins_since_last_pity_win =
        case when v_was_pity then 0 else pp.spins_since_last_pity_win + 1 end,
      updated_at = now()
  where pp.customer_id = p_customer_id
    and pp.promo_id = v_credit.promo_id;

  update public.customer_spin_credits c
  set is_consumed = true, consumed_at = now()
  where c.id = v_credit.id;

  insert into public.spin_history (
    customer_id, spin_wheel_reward_id, spin_credit_id, was_pity, promo_id, reward_pool_id
  )
  values (
    p_customer_id, v_reward.id, v_credit.id, v_was_pity, v_credit.promo_id, v_settings.reward_pool_id
  )
  returning id into v_history_id;

  insert into public.customer_coupons
    (customer_id, spin_wheel_reward_id, spin_history_id, discount_type, value)
  values
    (p_customer_id, v_reward.id, v_history_id, v_reward.discount_type, v_reward.value)
  returning id into v_coupon_id;

  return query
    select v_reward.id, v_was_pity, v_coupon_id, v_history_id, v_credit.promo_id;
end;
$$;

revoke all on function public.spin_wheel(uuid, uuid) from public;
grant execute on function public.spin_wheel(uuid, uuid) to service_role;

-- ============================================================
-- 20260925215_custom_rewards_drop_spin_wheel_config_and_rarity_percent.sql
-- ============================================================
-- Custom change (session 114): removes what the promo + reward pool shape
-- fully replaced. spin_wheel_config's numbers now live per promo in
-- spin_wheel_promo_settings (copied into the "Loyalty Spin" promo by
-- 20260925213); rarity_percent is replaced by rarity_tier + weight
-- (20260925209). Nothing reads either after 20260925214.

drop table if exists public.spin_wheel_config;

alter table public.spin_wheel_rewards
  drop column if exists rarity_percent;

-- ============================================================
-- Verification queries (session 114's testing.md, section G) - actually run
-- via `npx supabase db query --linked "<sql>"` against the dev project
-- (hikgijuipymfghfuyrjv) after the push above. Results noted inline.
-- ============================================================

-- 1. The backfill created exactly one Standard pool and one Loyalty Spin
--    promo, and repointed every pre-existing row. RUN, RESULT: all five
--    below returned exactly 1, 1, 0, 0, 0 respectively - no orphans.
select count(*) as standard_pools from public.reward_pools where name = 'Standard';
select count(*) as loyalty_spin_promos from public.promos where name = 'Loyalty Spin' and promo_type = 'spin_wheel';
select count(*) as orphaned_credits from public.customer_spin_credits where promo_id is null;
select count(*) as orphaned_pity from public.customer_pity_progress where promo_id is null;
select count(*) as orphaned_history from public.spin_history where promo_id is null;

-- 2. Adding, then deactivating, a reward never raises a constraint error
--    (confirms the sum-to-100 trigger is gone). RUN, RESULT: with the
--    Standard pool already at 5 active rewards / weight 100, insert
--    succeeded immediately, deactivate succeeded immediately, delete
--    (cleanup) succeeded - this is the literal ask from the request,
--    proven against real Postgres, not a mock.
insert into public.spin_wheel_rewards (label, discount_type, value, rarity_tier, weight)
values ('ZZZ_TEST_temp_reward_session114', 'Flat', 1, 'Common', 999);
update public.spin_wheel_rewards set is_active = false where label = 'ZZZ_TEST_temp_reward_session114';
delete from public.spin_wheel_rewards where label = 'ZZZ_TEST_temp_reward_session114'; -- cleanup, confirmed gone

-- 3. Two concurrent check-ins on the same day grant at most one daily_login
--    credit per promo (run both statements in separate sessions/transactions
--    against the same customer_id/promo_id and confirm only one row lands):
--    select * from record_customer_login('<customer_id>');
--    RUN (single-session form below), RESULT: zero rows - no duplicate
--    login-sourced credit exists yet on dev. The genuinely CONCURRENT case
--    (two overlapping transactions racing the same insert) was not
--    load-tested - still open, see testing.md.
select customer_id, promo_id, source, period_key, count(*)
from public.customer_spin_credits
where source in ('daily_login', 'weekly_login_streak', 'monthly_login_streak')
group by customer_id, promo_id, source, period_key
having count(*) > 1;
-- (returned zero rows)

-- 4. Pity always lands the rarest tier in the pool it fired for, and resets
--    the counter afterward. NOT YET RUN - no real customer has spun enough
--    times on dev yet to trigger pity; still open, see testing.md.
select ph.id, ph.was_pity, r.rarity_tier, rp.name as pool_name,
       max(r2.rarity_tier) over (partition by ph.reward_pool_id) as pool_rarest_tier
from public.spin_history ph
join public.spin_wheel_rewards r on r.id = ph.spin_wheel_reward_id
join public.reward_pools rp on rp.id = ph.reward_pool_id
join public.reward_pool_rewards prr on prr.reward_pool_id = ph.reward_pool_id
join public.spin_wheel_rewards r2 on r2.id = prr.spin_wheel_reward_id
where ph.was_pity = true;
-- every row's rarity_tier should equal its pool_rarest_tier

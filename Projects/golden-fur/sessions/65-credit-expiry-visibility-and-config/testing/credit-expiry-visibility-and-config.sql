-- Reference copy. Source of truth:
--   golden-fur/supabase/migrations/20260902159_m10_policy_credit_expiry_mode.sql
-- Applied to the linked Supabase project via `supabase db push` as the
-- closing step of session 65. Do not run this copy directly.

-- Credit expiry visibility + config (feat/credit-expiry-visibility-and-config).
--
-- WHY: the credit-expiry control was a single boolean + day count
-- (credit_expiry_enabled / credit_expiry_days, 20260805094) that could only
-- ever mean "N days after each credit is issued". The advisor backlog asks
-- for a branch owner to instead be able to say "all of this branch's credit
-- expires on one fixed calendar date", as a mutually-exclusive alternative.
--
-- Model it as one enum mode on policy_configurations, replacing the boolean:
--   none        - credit never expires (the old enabled = false).
--   rolling     - each credit lot expires credit_expiry_days after issuance
--                 (the old enabled = true - unchanged behaviour).
--   fixed_date  - every not-yet-expired credit lot at the branch expires on
--                 credit_expiry_fixed_date.
--
-- Same seeded-default-row + per-branch-override + resolveEffectivePolicy()
-- shape as every other policy_configurations column. NOT NULL DEFAULT
-- 'rolling' backfills the seeded default row and any branch-override rows
-- automatically, so existing branches keep behaving exactly as before.
--
-- The sweep model is unchanged - expire_credits() still walks
-- credit_transactions.expires_at < now(); 'fixed_date' just means many
-- issuance rows share one expires_at. reapply_branch_credit_expiry() below
-- is what makes a mode change retroactive (the caller is
-- staffPicker.service.ts's updatePolicyConfiguration). expire_credits()
-- itself is re-created at the end of this file with a per-iteration balance
-- re-read (see the comment there) - the only behavioural change, and only in
-- the multi-lot edge case the old version could not handle.

create type public.credit_expiry_mode as enum ('none', 'rolling', 'fixed_date');

alter table public.policy_configurations
  add column credit_expiry_mode public.credit_expiry_mode not null default 'rolling',
  add column credit_expiry_fixed_date date;

-- Carry the old boolean's meaning across before dropping it.
update public.policy_configurations
  set credit_expiry_mode = case
    when credit_expiry_enabled then 'rolling'::public.credit_expiry_mode
    else 'none'::public.credit_expiry_mode
  end;

alter table public.policy_configurations
  drop column credit_expiry_enabled;

alter table public.policy_configurations
  add constraint policy_configurations_credit_expiry_fixed_date_required check (
    credit_expiry_mode <> 'fixed_date' or credit_expiry_fixed_date is not null
  );

comment on column public.policy_configurations.credit_expiry_mode is
  'How account credit issued at this branch expires: none (never), rolling (credit_expiry_days after issuance), or fixed_date (all on credit_expiry_fixed_date). Resolved by resolveEffectivePolicy in staffPicker.service.ts; new lots stamped in cancellation.service.ts; existing lots re-stamped by reapply_branch_credit_expiry().';
comment on column public.policy_configurations.credit_expiry_fixed_date is
  'The calendar date every not-yet-expired credit lot at this branch expires on, when credit_expiry_mode = fixed_date. NULL otherwise (enforced by policy_configurations_credit_expiry_fixed_date_required).';

-- ---------------------------------------------------------------------------
-- reapply_branch_credit_expiry(): re-stamp expires_at on every outstanding
-- (not-yet-swept) issuance row for the given branches according to a mode.
--
-- Called best-effort by updatePolicyConfiguration() whenever an admin changes
-- credit_expiry_mode / _days / _fixed_date, so "entire branch credits expire
-- at X date" (and the reverse, relaxing the rule) applies to credit customers
-- already hold - not just future issuances. When the edited policy row is a
-- concrete branch, p_branch_ids is [that branch]; when it is the system
-- default row, it is every branch with no override of its own.
--
-- SECURITY DEFINER + service_role-only, mirroring issue_credit() /
-- redeem_credit(): credit_balances / credit_transactions have no
-- authenticated write policy at all.
-- ---------------------------------------------------------------------------
create or replace function public.reapply_branch_credit_expiry(
  p_branch_ids uuid[],
  p_mode public.credit_expiry_mode,
  p_days integer,
  p_fixed_date date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_expires_at timestamptz;
  v_updated integer := 0;
begin
  if p_branch_ids is null or array_length(p_branch_ids, 1) is null then
    return 0;
  end if;

  if p_mode = 'rolling' and p_days is null then
    raise exception 'reapply_branch_credit_expiry: rolling mode needs p_days';
  end if;
  if p_mode = 'fixed_date' and p_fixed_date is null then
    raise exception 'reapply_branch_credit_expiry: fixed_date mode needs p_fixed_date';
  end if;

  -- fixed_date -> end of that calendar day (UTC), matching the string
  -- cancellation.service.ts builds for newly issued lots.
  if p_mode = 'fixed_date' then
    v_new_expires_at := (p_fixed_date::text || 'T23:59:59.999Z')::timestamptz;
  end if;

  update public.credit_transactions ct
    set expires_at = case p_mode
      when 'none' then null
      when 'rolling' then ct.created_at + make_interval(days => p_days)
      when 'fixed_date' then v_new_expires_at
    end
    from public.credit_balances cb
    where ct.credit_balance_id = cb.id
      and cb.branch_id = any (p_branch_ids)
      and ct.transaction_type = 'issuance'
      and ct.expired_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.reapply_branch_credit_expiry(uuid[], public.credit_expiry_mode, integer, date) from public;
grant execute on function public.reapply_branch_credit_expiry(uuid[], public.credit_expiry_mode, integer, date) to service_role;

-- ---------------------------------------------------------------------------
-- expire_credits(): re-read the balance per iteration.
--
-- The 20260805098 version selected cb.balance once for the whole loop, so
-- two+ not-yet-swept lots on the same balance each capped against the
-- ORIGINAL balance. 'fixed_date' mode makes that common - a retroactive
-- fixed date leaves every one of a customer's lots past-expiry with the
-- same date - and if their nominal total exceeds the balance the stale cap
-- drives balance below 0, tripping the balance >= 0 CHECK and aborting the
-- whole sweep. Re-selecting the balance (FOR UPDATE) each iteration makes
-- each lot expire only min(its amount, what's actually left).
-- ---------------------------------------------------------------------------
create or replace function public.expire_credits()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_swept integer := 0;
  r record;
  v_current_balance numeric(10, 2);
  v_expire_amount numeric(10, 2);
begin
  for r in
    select ct.id, ct.credit_balance_id, ct.amount
    from public.credit_transactions ct
    where ct.transaction_type = 'issuance'
      and ct.expired_at is null
      and ct.expires_at is not null
      and ct.expires_at < now()
    order by ct.expires_at asc
  loop
    select balance into v_current_balance
    from public.credit_balances
    where id = r.credit_balance_id
    for update;

    v_expire_amount := least(r.amount, greatest(v_current_balance, 0));

    if v_expire_amount > 0 then
      insert into public.credit_transactions (credit_balance_id, transaction_type, amount)
      values (r.credit_balance_id, 'expiry', -v_expire_amount);

      update public.credit_balances
        set balance = balance - v_expire_amount, updated_at = now()
        where id = r.credit_balance_id;
    end if;

    update public.credit_transactions set expired_at = now() where id = r.id;
    v_swept := v_swept + 1;
  end loop;

  return v_swept;
end;
$$;

revoke all on function public.expire_credits() from public;
grant execute on function public.expire_credits() to authenticated;
grant execute on function public.expire_credits() to service_role;
-- Reference copy. Source of truth:
--   golden-fur/supabase/migrations/20260902160_m10_credit_expiry_manila_end_of_day.sql
-- Applied to the linked Supabase project via `supabase db push` (session 65
-- follow-up). Do not run this copy directly.

-- Credit expiry: land every lot's expires_at on the end of its Manila
-- calendar day (feat/credit-expiry-visibility-and-config, follow-up).
--
-- WHY: 20260902159 stamped rolling lots at `created_at + N days` (an exact
-- time of day) and fixed_date lots at UTC end-of-day. Two lots issued a few
-- hours apart on the same day then got expires_at values a few hours apart,
-- so the customer credits page showed them as two separate "Oct 1" rows with
-- different "days left", and a UTC end-of-day for "Dec 31" reads as "Jan 1"
-- in Manila. Credit expires per calendar day in the one timezone every
-- branch uses (Asia/Manila, UTC+8, no DST) - so snap every not-yet-swept
-- issuance lot, and both branches of reapply_branch_credit_expiry(), to the
-- end of the Manila day. cancellation.service.ts does the same for new lots
-- (creditExpiry.util.ts). expire_credits() is unchanged.

update public.credit_transactions
set expires_at =
  ((expires_at at time zone 'Asia/Manila')::date + time '23:59:59.999')
    at time zone 'Asia/Manila'
where transaction_type = 'issuance'
  and expired_at is null
  and expires_at is not null;

create or replace function public.reapply_branch_credit_expiry(
  p_branch_ids uuid[],
  p_mode public.credit_expiry_mode,
  p_days integer,
  p_fixed_date date
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_expires_at timestamptz;
  v_updated integer := 0;
begin
  if p_branch_ids is null or array_length(p_branch_ids, 1) is null then
    return 0;
  end if;

  if p_mode = 'rolling' and p_days is null then
    raise exception 'reapply_branch_credit_expiry: rolling mode needs p_days';
  end if;
  if p_mode = 'fixed_date' and p_fixed_date is null then
    raise exception 'reapply_branch_credit_expiry: fixed_date mode needs p_fixed_date';
  end if;

  -- fixed_date -> end of that Manila calendar day.
  if p_mode = 'fixed_date' then
    v_new_expires_at :=
      (p_fixed_date + time '23:59:59.999') at time zone 'Asia/Manila';
  end if;

  update public.credit_transactions ct
    set expires_at = case p_mode
      when 'none' then null
      when 'rolling' then
        (((ct.created_at + make_interval(days => p_days))
          at time zone 'Asia/Manila')::date + time '23:59:59.999')
          at time zone 'Asia/Manila'
      when 'fixed_date' then v_new_expires_at
    end
    from public.credit_balances cb
    where ct.credit_balance_id = cb.id
      and cb.branch_id = any (p_branch_ids)
      and ct.transaction_type = 'issuance'
      and ct.expired_at is null;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.reapply_branch_credit_expiry(uuid[], public.credit_expiry_mode, integer, date) from public;
grant execute on function public.reapply_branch_credit_expiry(uuid[], public.credit_expiry_mode, integer, date) to service_role;

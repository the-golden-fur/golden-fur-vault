-- Reference copy — source of truth is golden-fur/supabase/migrations/:
--   20260901150_m08_bookings_replace_payment_stage_with_payment_status.sql
--   20260901151_m08_transactions_payment_choice_free_label.sql
--   20260901152_m08_payment_method_add_credit.sql
--   20260901153_m08_settle_transaction_rpc.sql
--   20260901154_m08_add_booking_payment_rpc.sql
--   20260901155_m10_redeem_credit_rpc.sql
--   20260901156_m03_get_staff_availability_payment_status.sql
--   20260901157_m14_reporting_functions_settled_only.sql
--
-- Branch: feat/payment-transactions-rework. All 8 were applied to the linked
-- Supabase project via `supabase db push` (confirmed with
-- `supabase migration list --linked` — remote through 20260901157). The local
-- Docker stack was down at push time, so there was NO local `supabase db
-- reset` dry-run first; they went straight to the linked DB.
-- ==========================================================================

-- ========================================================================
-- supabase/migrations/20260901150_m08_bookings_replace_payment_stage_with_payment_status.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 1/8.
--
-- WHY: bookings.payment_stage (enum payment_stage = Unpaid / Paid in Advance
-- / Paid, added by 20260803082) was a bespoke, manually-advanced track that
-- duplicated the concept the M08 payment_status enum (Pending / Partially
-- Paid / Fully Paid, from 20260731068) already models for transactions. The
-- rework makes a booking's payment state a straight rollup of its
-- transactions rows, so it now reuses that same enum on bookings and is kept
-- current by settle_transaction() / add_booking_payment() (later migrations
-- in this series) instead of a separate "Advance" action.
--
-- Mapping applied to existing rows:
--   Unpaid          -> Pending
--   Paid in Advance -> Partially Paid
--   Paid            -> Fully Paid
--
-- bookings_downpayment_gate_idx (20260808111) is a partial index on
-- (downpayment_required, payment_stage); Postgres would auto-drop it with the
-- column, so it is explicitly dropped and recreated against payment_status to
-- keep the down-payment slot-gate lookup covered.

alter table public.bookings
  add column payment_status public.payment_status not null default 'Pending';

update public.bookings
set payment_status = case payment_stage
  when 'Unpaid' then 'Pending'::public.payment_status
  when 'Paid in Advance' then 'Partially Paid'::public.payment_status
  when 'Paid' then 'Fully Paid'::public.payment_status
end;

drop index if exists public.bookings_payment_stage_idx;
drop index if exists public.bookings_downpayment_gate_idx;

alter table public.bookings drop column payment_stage;

drop type public.payment_stage;

create index bookings_payment_status_idx on public.bookings(payment_status);

-- Same shape as the index 20260808111 created, re-pointed at payment_status.
-- The gate now fires while payment_status = 'Pending' (was payment_stage =
-- 'Unpaid').
create index bookings_downpayment_gate_idx
  on public.bookings (downpayment_required, payment_status)
  where downpayment_required = true;

comment on column public.bookings.payment_status is
  'Rollup of this booking''s transactions rows (Pending / Partially Paid / Fully Paid). Maintained by settle_transaction() and add_booking_payment(); do not write directly. Replaced the bespoke payment_stage column (20260803082) in the payment/transactions rework.';

-- ========================================================================
-- supabase/migrations/20260901151_m08_transactions_payment_choice_free_label.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 2/8.
--
-- WHY: 20260809118 added transactions.payment_choice ('full' | 'downpayment')
-- purely as a hint for the customer-initiated PayMongo webhook, and coupled
-- it to initiated_by = 'customer' via
-- transactions_payment_choice_requires_customer_initiated. In the reworked
-- model a booking_payment row can also be created by staff (see
-- add_booking_payment() later in this series) and carries a 'balance' choice,
-- so payment_choice becomes a free label independent of who initiated the
-- row.
--
--   * drop the initiated_by coupling CHECK entirely.
--   * widen the value CHECK to allow 'full' | 'downpayment' | 'balance'
--     (kept as a CHECK rather than dropped so the column stays a known set).
--
-- transactions_payment_choice_check is the auto-generated name Postgres gave
-- the inline `check (payment_choice in (...))` in 20260809118 (only column
-- referenced is payment_choice).

alter table public.transactions
  drop constraint transactions_payment_choice_requires_customer_initiated;

alter table public.transactions
  drop constraint transactions_payment_choice_check;

alter table public.transactions
  add constraint transactions_payment_choice_check
    check (payment_choice is null
           or payment_choice in ('full', 'downpayment', 'balance'));

-- ========================================================================
-- supabase/migrations/20260901152_m08_payment_method_add_credit.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 3/8.
--
-- WHY: the reworked payments flow lets a customer settle a booking balance
-- with previously-issued account credit (redeem_credit(), later in this
-- series), which is recorded as a transactions row whose payment_method is
-- 'Credit'. Adds that value to the payment_method enum (from 20260731068:
-- Cash, GCash, Maya, Card, Bank Transfer, Grabmart, Pickaroo).
--
-- Kept in its own migration file with nothing else in it: `alter type ... add
-- value` and any statement that then USES the new value cannot run in the
-- same transaction, and Supabase wraps each migration file in one
-- transaction. Every consumer of the new value lives in a later file.

alter type public.payment_method add value if not exists 'Credit';

-- ========================================================================
-- supabase/migrations/20260901153_m08_settle_transaction_rpc.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 4/8.
--
-- WHY: in the reworked model a booking_payment transaction is created up
-- front in 'Pending' state (at booking time, or via add_booking_payment())
-- and later "settled" when the cashier actually collects the money. Settling
-- must atomically (a) flip the transaction to Fully Paid with its real
-- payment details and (b) recompute the parent booking's payment_status
-- rollup - a two-round-trip application-layer read-then-write can't guarantee
-- that. Single SECURITY DEFINER PL/pgSQL function, same pattern as
-- issue_credit() (20260805097): the server's service-role client calls it as
-- a plain RPC and the whole update happens inside one Postgres transaction.
--
-- p_cash_tendered is accepted for call-site symmetry with the cashier change-
-- due UI but is not persisted - transactions has no tendered/change column.
--
-- Rollup rule (mirrors add_booking_payment()): net = total_price -
-- discount_amount - promo_amount; paid = sum(total_amount) over this
-- booking's non-Pending booking_payment transactions.

create or replace function public.settle_transaction(
  p_transaction_id uuid,
  p_payment_method public.payment_method,
  p_bank_name text,
  p_payment_reference text,
  p_cash_tendered numeric,
  p_processed_by uuid
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_txn public.transactions;
  v_booking public.bookings;
  v_net numeric(10, 2);
  v_paid numeric(10, 2);
  v_new_status public.payment_status;
begin
  select * into v_txn
  from public.transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception 'settle_transaction: transaction % not found', p_transaction_id;
  end if;

  if v_txn.payment_status = 'Fully Paid' then
    raise exception 'settle_transaction: transaction % is already Fully Paid', p_transaction_id;
  end if;

  update public.transactions
  set payment_status = 'Fully Paid',
      payment_method = p_payment_method,
      bank_name = p_bank_name,
      payment_reference = coalesce(p_payment_reference, payment_reference),
      processed_by_staff_id = p_processed_by,
      updated_at = now()
  where id = p_transaction_id
  returning * into v_txn;

  if v_txn.booking_id is null then
    raise exception 'settle_transaction: transaction % has no booking to roll up', p_transaction_id;
  end if;

  select * into v_booking
  from public.bookings
  where id = v_txn.booking_id
  for update;

  v_net := coalesce(v_booking.total_price, 0)
         - coalesce(v_booking.discount_amount, 0)
         - coalesce(v_booking.promo_amount, 0);

  select coalesce(sum(t.total_amount), 0)
    into v_paid
  from public.transactions t
  where t.booking_id = v_booking.id
    and t.transaction_type = 'booking_payment'
    and t.payment_status <> 'Pending';

  v_new_status := case
    when v_paid <= 0 then 'Pending'::public.payment_status
    when v_paid >= v_net then 'Fully Paid'::public.payment_status
    else 'Partially Paid'::public.payment_status
  end;

  update public.bookings
  set payment_status = v_new_status,
      paid_at = case
        when v_new_status = 'Fully Paid' then now()
        else paid_at
      end,
      updated_at = now()
  where id = v_booking.id
  returning * into v_booking;

  return v_booking;
end;
$$;

revoke all on function public.settle_transaction(uuid, public.payment_method, text, text, numeric, uuid) from public;
grant execute on function public.settle_transaction(uuid, public.payment_method, text, text, numeric, uuid) to service_role;

-- ========================================================================
-- supabase/migrations/20260901154_m08_add_booking_payment_rpc.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 5/8.
--
-- WHY: staff need to record an additional partial payment against a booking
-- (e.g. collecting a balance in instalments) as a distinct, settleable
-- transaction. This creates a 'Pending' booking_payment transactions row plus
-- its single line item atomically, after validating the amount fits inside
-- the booking's outstanding balance. SECURITY DEFINER, same rationale as
-- settle_transaction() / issue_credit(): the row + line item must land
-- together, which two PostgREST round trips can't guarantee.
--
-- payment_method / payment_choice on the new row are placeholders:
-- payment_method 'Cash' (a valid enum value, overwritten by
-- settle_transaction() when the money is actually collected), payment_choice
-- 'balance'. remaining balance = net - already-settled, where net =
-- total_price - discount_amount - promo_amount and "settled" is the sum over
-- non-Pending booking_payment rows (same rule settle_transaction() rolls up
-- with).

create or replace function public.add_booking_payment(
  p_booking_id uuid,
  p_amount numeric,
  p_processed_by uuid
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings;
  v_net numeric(10, 2);
  v_settled numeric(10, 2);
  v_remaining numeric(10, 2);
  v_txn public.transactions;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'add_booking_payment: amount must be positive';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'add_booking_payment: booking % not found', p_booking_id;
  end if;

  v_net := coalesce(v_booking.total_price, 0)
         - coalesce(v_booking.discount_amount, 0)
         - coalesce(v_booking.promo_amount, 0);

  select coalesce(sum(t.total_amount), 0)
    into v_settled
  from public.transactions t
  where t.booking_id = p_booking_id
    and t.transaction_type = 'booking_payment'
    and t.payment_status <> 'Pending';

  v_remaining := v_net - v_settled;

  if p_amount > v_remaining then
    raise exception
      'add_booking_payment: amount % exceeds remaining balance %',
      p_amount, v_remaining;
  end if;

  insert into public.transactions (
    booking_id,
    customer_id,
    branch_id,
    transaction_type,
    payment_method,
    payment_status,
    payment_choice,
    subtotal_amount,
    total_amount,
    processed_by_staff_id
  ) values (
    p_booking_id,
    v_booking.customer_id,
    v_booking.branch_id,
    'booking_payment',
    'Cash',
    'Pending',
    'balance',
    p_amount,
    p_amount,
    p_processed_by
  )
  returning * into v_txn;

  insert into public.transaction_line_items (
    transaction_id,
    line_item_type,
    description,
    quantity,
    unit_price,
    line_total
  ) values (
    v_txn.id,
    'service',
    'Additional payment',
    1,
    p_amount,
    p_amount
  );

  return v_txn;
end;
$$;

revoke all on function public.add_booking_payment(uuid, numeric, uuid) from public;
grant execute on function public.add_booking_payment(uuid, numeric, uuid) to service_role;

-- ========================================================================
-- supabase/migrations/20260901155_m10_redeem_credit_rpc.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 6/8.
--
-- WHY: the inverse of issue_credit() (20260805097). When a customer pays a
-- booking balance with account credit, the credit_balances row must be
-- decremented and a matching 'redemption' credit_transactions row written
-- atomically - the same "can't span two PostgREST round trips" reasoning that
-- made issue_credit() a function. SECURITY DEFINER, granted to service_role
-- only.
--
-- The caller is expected to pass an amount already capped at
-- min(balance, amount_owed); this function re-checks balance >= p_amount
-- under a row lock and raises if not, so a stale client cap can never drive
-- the balance negative (the credit_balances.balance >= 0 CHECK is the last
-- line of defense behind this).
--
-- amount is stored negative (-p_amount) to satisfy
-- credit_transactions_amount_sign_matches_type (redemption rows must be < 0)
-- and to keep SUM(amount) == balance. transaction_id links the redemption to
-- the transactions row it paid down.

create or replace function public.redeem_credit(
  p_customer_id uuid,
  p_branch_id uuid,
  p_amount numeric,
  p_transaction_id uuid
)
returns public.credit_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance public.credit_balances;
  v_transaction public.credit_transactions;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'redeem_credit: amount must be positive';
  end if;

  select * into v_balance
  from public.credit_balances
  where customer_id = p_customer_id
    and branch_id = p_branch_id
  for update;

  if not found then
    raise exception
      'redeem_credit: no credit balance for customer % at branch %',
      p_customer_id, p_branch_id;
  end if;

  if v_balance.balance < p_amount then
    raise exception
      'redeem_credit: balance % is less than requested %',
      v_balance.balance, p_amount;
  end if;

  update public.credit_balances
  set balance = balance - p_amount,
      updated_at = now()
  where id = v_balance.id;

  insert into public.credit_transactions (
    credit_balance_id,
    transaction_type,
    amount,
    transaction_id
  ) values (
    v_balance.id,
    'redemption',
    -p_amount,
    p_transaction_id
  )
  returning * into v_transaction;

  return v_transaction;
end;
$$;

revoke all on function public.redeem_credit(uuid, uuid, numeric, uuid) from public;
grant execute on function public.redeem_credit(uuid, uuid, numeric, uuid) to service_role;

-- ========================================================================
-- supabase/migrations/20260901156_m03_get_staff_availability_payment_status.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 7/8.
--
-- WHY: get_staff_availability() (last redefined 20260829148) reads the
-- down-payment slot gate off bookings.payment_stage = 'Unpaid'. That column
-- is gone (20260901150); the equivalent state is now payment_status =
-- 'Pending'. CREATE OR REPLACE against the identical signature - body is
-- 20260829148 verbatim except Check 2's guard and comment now reference
-- payment_status. Cautionary note carried over from every prior redefinition:
-- this function has repeatedly been clobbered by parallel same-day migrations
-- branching off a stale copy - this one is based on the current (20260829148)
-- definition; confirm no other migration redefines it between ...148 and here.

create or replace function public.get_staff_availability(
  p_role public.staff_role,
  p_branch_id uuid,
  p_requested_start timestamptz,
  p_requested_end timestamptz,
  p_staff_id uuid default null,
  p_exclude_booking_id uuid default null
)
returns table (
  staff_id uuid,
  display_name text,
  profile_photo_url text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_branch_timezone text;
  v_day_name text;
  v_requested_start_local time;
  v_requested_end_local time;
  v_open_time time;
  v_close_time time;
  v_lunch_break_enabled boolean;
  v_lunch_break_start time;
  v_lunch_break_end time;
begin
  if p_requested_end <= p_requested_start then
    return;
  end if;

  select b.timezone
    into v_branch_timezone
  from public.branches b
  where b.id = p_branch_id;

  if v_branch_timezone is null then
    return;
  end if;

  v_day_name :=
    lower(trim(to_char(p_requested_start at time zone v_branch_timezone, 'day')));
  v_requested_start_local :=
    (p_requested_start at time zone v_branch_timezone)::time;
  v_requested_end_local :=
    (p_requested_end at time zone v_branch_timezone)::time;

  -- Check 1: within branch operating hours for that day. Branch-level, so a
  -- failure returns an empty set regardless of staff schedules (#49 AC-4).
  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.operating_hours ? v_day_name
  ) then
    return;
  end if;

  select
    make_time(
      split_part((b.operating_hours -> v_day_name ->> 'open'), ':', 1)::int,
      split_part((b.operating_hours -> v_day_name ->> 'open'), ':', 2)::int,
      0
    ),
    make_time(
      split_part((b.operating_hours -> v_day_name ->> 'close'), ':', 1)::int,
      split_part((b.operating_hours -> v_day_name ->> 'close'), ':', 2)::int,
      0
    )
    into v_open_time, v_close_time
  from public.branches b
  where b.id = p_branch_id;

  if v_open_time is null or v_close_time is null then
    return;
  end if;

  if v_requested_start_local < v_open_time
     or v_requested_end_local > v_close_time
     or v_requested_start_local >= v_requested_end_local
  then
    return;
  end if;

  -- Lunch break check: the branch-specific policy_configurations row wins
  -- whole-row if one exists, else the system-wide default (branch_id null)
  -- row - same whole-row precedence resolveEffectivePolicy() uses
  -- server-side, mirrored here so the RPC agrees with the TS resolution.
  select pc.lunch_break_enabled, pc.lunch_break_start, pc.lunch_break_end
    into v_lunch_break_enabled, v_lunch_break_start, v_lunch_break_end
  from public.policy_configurations pc
  where pc.branch_id = p_branch_id
  limit 1;

  if not found then
    select pc.lunch_break_enabled, pc.lunch_break_start, pc.lunch_break_end
      into v_lunch_break_enabled, v_lunch_break_start, v_lunch_break_end
    from public.policy_configurations pc
    where pc.branch_id is null
    limit 1;
  end if;

  if v_lunch_break_enabled
     and v_requested_start_local < v_lunch_break_end
     and v_requested_end_local > v_lunch_break_start
  then
    return;
  end if;

  return query
  select sp.id, sp.display_name, sp.profile_photo_url
  from public.staff_profiles sp
  where sp.branch_id = p_branch_id
    and sp.role = p_role
    and sp.is_active
    and (p_staff_id is null or sp.id = p_staff_id)
    -- Check 2: no overlapping booking that still holds a real slot -
    -- Pending/In Progress/Completed, EXCEPT a down-payment-required booking
    -- that hasn't paid any of its down payment yet (down-payment slot gate,
    -- 20260829146/147): that one sits Pending without reserving anything
    -- until payment_status leaves 'Pending'. Mirrors the
    -- downpayment_required/payment_status filter grooming.service.ts and
    -- consultation.service.ts already apply to their queues.
    and not exists (
      select 1
      from public.bookings bk
      where bk.assigned_staff_id = sp.id
        and bk.status in ('Pending', 'In Progress', 'Completed')
        and not (bk.downpayment_required and bk.payment_status = 'Pending')
        and (p_exclude_booking_id is null or bk.id <> p_exclude_booking_id)
        and bk.scheduled_start < p_requested_end
        and bk.scheduled_end > p_requested_start
    )
    -- Check 3: no overlapping APPROVED unavailability block (#49 AC-3);
    -- pending/denied rows are ignored per the Jul 11, 2026 redesign.
    and not exists (
      select 1
      from public.staff_unavailability_blocks sub
      where sub.staff_id = sp.id
        and sub.status = 'approved'
        and sub.start_time < p_requested_end
        and sub.end_time > p_requested_start
    )
  order by sp.display_name, sp.id;
end;
$$;

-- ========================================================================
-- supabase/migrations/20260901157_m14_reporting_functions_settled_only.sql
-- ========================================================================
-- Payment/transactions model rework (feat/payment-transactions-rework), 8/8.
--
-- WHY: before the rework a booking_payment transactions row was only ever
-- written once money had actually been collected, so every reporting
-- aggregation could sum total_amount unconditionally. Now a booking_payment
-- row is created 'Pending' up front (at booking time / via
-- add_booking_payment()) and only reaches 'Fully Paid' when
-- settle_transaction() records the collection. Summing unconditionally would
-- inflate gross by every uncollected charge.
--
-- CREATE OR REPLACE of get_daily_sales_report() and get_analytics_summary()
-- from 20260805101, verbatim except every `from public.transactions t`
-- aggregation gains `and t.payment_status = 'Fully Paid'`.
-- get_cage_occupancy_report() is unchanged and intentionally not redefined
-- here.

-- ---------------------------------------------------------------------------
-- get_daily_sales_report(p_branch_id, p_report_date)
-- ---------------------------------------------------------------------------
create or replace function public.get_daily_sales_report(
  p_branch_id uuid,
  p_report_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_breakdown jsonb;
  v_totals jsonb;
  v_credit_usage jsonb;
  v_misc_sales jsonb;
  v_misc_total numeric(10, 2);
begin
  -- service_category × payment_method breakdown - settled booking-payment
  -- transactions only, category read from the booking (bookings.service_category),
  -- not transaction_line_items (a booking's items always share one category).
  select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    into v_breakdown
  from (
    select
      b.service_category,
      t.payment_method,
      count(*)::int as transaction_count,
      sum(t.total_amount)::numeric(10, 2) as gross_amount
    from public.transactions t
    join public.bookings b on b.id = t.booking_id
    where t.transaction_type = 'booking_payment'
      and t.payment_status = 'Fully Paid'
      and t.created_at::date = p_report_date
      and (p_branch_id is null or t.branch_id = p_branch_id)
    group by b.service_category, t.payment_method
    order by b.service_category, t.payment_method
  ) row_data;

  select jsonb_build_object(
    'transaction_count', coalesce(count(*), 0)::int,
    'gross_amount', coalesce(sum(t.total_amount), 0)::numeric(10, 2)
  )
    into v_totals
  from public.transactions t
  where t.transaction_type = 'booking_payment'
    and t.payment_status = 'Fully Paid'
    and t.created_at::date = p_report_date
    and (p_branch_id is null or t.branch_id = p_branch_id);

  -- Credit-usage section: credit_transactions rows of type 'redemption'
  -- (amount is stored negative for redemption per migration ...097's sign
  -- convention, so this reports the absolute value actually redeemed).
  select jsonb_build_object(
    'transaction_count', coalesce(count(*), 0)::int,
    'total_credit_applied', coalesce(sum(-ct.amount), 0)::numeric(10, 2)
  )
    into v_credit_usage
  from public.credit_transactions ct
  join public.credit_balances cb on cb.id = ct.credit_balance_id
  where ct.transaction_type = 'redemption'
    and ct.created_at::date = p_report_date
    and (p_branch_id is null or cb.branch_id = p_branch_id);

  -- Miscellaneous-sale section, broken down by payment method - kept
  -- separate from the service-category breakdown above (AC-2).
  select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    into v_misc_sales
  from (
    select
      t.payment_method,
      count(*)::int as transaction_count,
      sum(t.total_amount)::numeric(10, 2) as gross_amount
    from public.transactions t
    where t.transaction_type = 'miscellaneous_sale'
      and t.payment_status = 'Fully Paid'
      and t.created_at::date = p_report_date
      and (p_branch_id is null or t.branch_id = p_branch_id)
    group by t.payment_method
    order by t.payment_method
  ) row_data;

  select coalesce(sum(t.total_amount), 0)::numeric(10, 2)
    into v_misc_total
  from public.transactions t
  where t.transaction_type = 'miscellaneous_sale'
    and t.payment_status = 'Fully Paid'
    and t.created_at::date = p_report_date
    and (p_branch_id is null or t.branch_id = p_branch_id);

  return jsonb_build_object(
    'branch_id', p_branch_id,
    'report_date', p_report_date,
    'breakdown', v_breakdown,
    'totals', v_totals,
    'credit_usage', v_credit_usage,
    'misc_sales', v_misc_sales,
    'misc_sales_total', v_misc_total
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- get_analytics_summary(p_branch_id, p_time_filter)
-- ---------------------------------------------------------------------------
create or replace function public.get_analytics_summary(
  p_branch_id uuid,
  p_time_filter text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_range_start timestamptz;
  v_revenue numeric(10, 2);
  v_booking_count int;
  v_cancelled_count int;
begin
  v_range_start := case p_time_filter
    when 'today' then date_trunc('day', now())
    when 'this_week' then date_trunc('week', now())
    when 'this_month' then date_trunc('month', now())
    when 'this_year' then date_trunc('year', now())
    when 'all_time' then '-infinity'::timestamptz
    else date_trunc('day', now())
  end;

  select coalesce(sum(t.total_amount), 0)::numeric(10, 2)
    into v_revenue
  from public.transactions t
  where t.created_at >= v_range_start
    and t.payment_status = 'Fully Paid'
    and (p_branch_id is null or t.branch_id = p_branch_id);

  select
    count(*)::int,
    count(*) filter (where b.status = 'Cancelled')::int
    into v_booking_count, v_cancelled_count
  from public.bookings b
  where b.scheduled_start >= v_range_start
    and (p_branch_id is null or b.branch_id = p_branch_id);

  return jsonb_build_object(
    'branch_id', p_branch_id,
    'time_filter', p_time_filter,
    'total_revenue', v_revenue,
    'booking_count', v_booking_count,
    'cancelled_count', v_cancelled_count,
    'cancellation_rate',
      case when v_booking_count > 0
        then round((v_cancelled_count::numeric / v_booking_count) * 100, 2)
        else 0
      end
  );
end;
$$;


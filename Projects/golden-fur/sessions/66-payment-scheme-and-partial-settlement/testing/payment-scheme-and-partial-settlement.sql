-- Reference copies of the migrations added on
-- feat/booking-payment-scheme-and-partial-settlement.
-- Source of truth: golden-fur/supabase/migrations/ (do not run from here).


-- ======================================================================
-- 20260902161_m09_policy_configurations_downpayment_default_on.sql
-- ======================================================================

-- Architectural-Change-History "In Progress" row (Matthew): a new booking must
-- let the customer/receptionist choose downpayment vs full payment at the last
-- step. The choice UI (CustomerBookingFlowPage's Review step) already exists but
-- only renders when the branch downpayment policy is enabled, and 20260828143
-- shipped it disabled - so nobody ever sees the choice and every booking is
-- charged in full ("currently it auto locks full payment").
--
-- This flips the system-wide default to ENABLED at 50% (Percentage), the
-- advisor's own worked example (MsMayuga-Aug27). An Admin can still turn it off
-- or change the amount/type per branch on Settings > Config > Policies; a flat
-- PHP amount is a one-line edit here.
--
-- Column DEFAULT flip: future per-branch override rows inherit "enabled".
-- Existing-row UPDATE: only the seeded system-default row (branch_id IS NULL),
-- and only when its type/amount were never set - so a shared dev/staging DB
-- where an Admin already configured downpayment is left untouched.
--
-- The enabled-requires-type-and-amount invariant and the 0-100 percentage cap
-- stay at the validator layer (booking.validator.ts), matching this table's
-- reschedule_fee_* convention - no DB CHECK added here.

alter table public.policy_configurations
  alter column downpayment_enabled set default true;

update public.policy_configurations
set downpayment_enabled = true,
    downpayment_type = 'Percentage',
    downpayment_amount = 50,
    updated_at = now()
where branch_id is null
  and downpayment_type is null
  and downpayment_amount is null;

comment on column public.policy_configurations.downpayment_enabled is
  'Whether an online booking transaction requires a downpayment. Default TRUE (enabled system-wide at 50% Percentage since 20260902161); Admin can disable or override per branch. Resolved by resolveEffectivePolicy/resolveDownpaymentPolicy in staffPicker.service.ts.';

-- ======================================================================
-- 20260902162_m08_create_initial_booking_charge_rpc.sql
-- ======================================================================

-- Architectural-Change-History "In Progress" row (Matthew): "choosing the
-- downpayment scheme should initially create 2 transactions (downpayment +
-- remaining balance)". Until now createBooking emitted a single Pending
-- booking_payment transaction (the down payment OR the full total, via the
-- old app-side createInitialBookingCharge). This RPC replaces that helper so
-- the down payment and its remaining-balance charge land together in one
-- Postgres transaction - same SECURITY DEFINER pattern as settle_transaction
-- (20260901153) / add_booking_payment (20260901154) / issue_credit
-- (20260805097), whose rationale is "the row + its line item must be atomic,
-- two PostgREST round trips can't guarantee that".
--
--   p_scheme = 'downpayment' -> two Pending rows:
--     1. payment_choice 'downpayment', total = round2(p_downpayment_amount),
--        line item "Down payment"
--     2. payment_choice 'balance',     total = net - downpayment  (only if > 0),
--        line item "Remaining balance"
--   p_scheme = 'full' -> one Pending row: payment_choice 'full', total = net,
--     line item "Full payment"
--
-- Both rows are Pending, so neither counts as "settled" in any rollup
-- (payment_status <> 'Pending'): the booking stays payment_status 'Pending'
-- and (when a down payment is required) holds no slot until the first row is
-- actually settled - unchanged from before. Invariant preserved: each row has
-- exactly one line item with line_total = total_amount.
--
-- payment_method 'Cash' is a placeholder (a valid enum value), overwritten by
-- settle_transaction() when the money is collected. Caller (createBooking) is
-- best-effort: it logs a failure and never rolls the booking back.

create or replace function public.create_initial_booking_charge(
  p_booking_id uuid,
  p_scheme text,
  p_net_total numeric,
  p_downpayment_amount numeric
)
returns setof public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings;
  v_dp numeric(10, 2);
  v_balance numeric(10, 2);
  v_txn public.transactions;
begin
  if p_scheme not in ('downpayment', 'full') then
    raise exception 'create_initial_booking_charge: bad scheme %', p_scheme;
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'create_initial_booking_charge: booking % not found', p_booking_id;
  end if;

  if p_scheme = 'downpayment' then
    v_dp := round(coalesce(p_downpayment_amount, 0), 2);
    v_balance := round(coalesce(p_net_total, 0) - v_dp, 2);

    insert into public.transactions (
      booking_id, customer_id, branch_id, transaction_type,
      payment_method, payment_status, payment_choice,
      subtotal_amount, total_amount
    ) values (
      v_booking.id, v_booking.customer_id, v_booking.branch_id, 'booking_payment',
      'Cash', 'Pending', 'downpayment',
      v_dp, v_dp
    )
    returning * into v_txn;

    insert into public.transaction_line_items (
      transaction_id, line_item_type, description, quantity, unit_price, line_total
    ) values (v_txn.id, 'service', 'Down payment', 1, v_dp, v_dp);

    return next v_txn;

    if v_balance > 0 then
      insert into public.transactions (
        booking_id, customer_id, branch_id, transaction_type,
        payment_method, payment_status, payment_choice,
        subtotal_amount, total_amount
      ) values (
        v_booking.id, v_booking.customer_id, v_booking.branch_id, 'booking_payment',
        'Cash', 'Pending', 'balance',
        v_balance, v_balance
      )
      returning * into v_txn;

      insert into public.transaction_line_items (
        transaction_id, line_item_type, description, quantity, unit_price, line_total
      ) values (v_txn.id, 'service', 'Remaining balance', 1, v_balance, v_balance);

      return next v_txn;
    end if;
  else
    insert into public.transactions (
      booking_id, customer_id, branch_id, transaction_type,
      payment_method, payment_status, payment_choice,
      subtotal_amount, total_amount
    ) values (
      v_booking.id, v_booking.customer_id, v_booking.branch_id, 'booking_payment',
      'Cash', 'Pending', 'full',
      round(coalesce(p_net_total, 0), 2), round(coalesce(p_net_total, 0), 2)
    )
    returning * into v_txn;

    insert into public.transaction_line_items (
      transaction_id, line_item_type, description, quantity, unit_price, line_total
    ) values (
      v_txn.id, 'service', 'Full payment', 1,
      round(coalesce(p_net_total, 0), 2), round(coalesce(p_net_total, 0), 2)
    );

    return next v_txn;
  end if;
end;
$$;

revoke all on function public.create_initial_booking_charge(uuid, text, numeric, numeric) from public;
grant execute on function public.create_initial_booking_charge(uuid, text, numeric, numeric) to service_role;

-- ======================================================================
-- 20260902163_m08_settle_transaction_partial.sql
-- ======================================================================

-- Architectural-Change-History "In Progress" row (Matthew): "if remaining
-- balance isn't fully paid, it creates another remaining balance transaction
-- instance" - and the follow-up in chat: this must also apply to a 'full'
-- charge that gets underpaid.
--
-- Until now settle_transaction() (20260901153) only ever flipped a Pending row
-- straight to 'Fully Paid' for its whole total_amount. This version takes an
-- optional p_amount_applied (the amount actually collected). When it is less
-- than the transaction's total:
--   1. the settled row (and its line item) is shrunk to the amount collected,
--   2. it is flipped 'Fully Paid' with the real payment details,
--   3. a NEW Pending 'booking_payment' row (payment_choice 'balance', line item
--      "Remaining balance") is created for the leftover.
-- Each spawned 'balance' row is itself settleable the same way, so "keep paying
-- until it's covered" needs no extra logic. p_amount_applied = null keeps the
-- old behaviour (settle for the full total) so existing callers are untouched.
--
-- Assumes one transaction_line_items row per booking_payment transaction - true
-- for every creation path (create_initial_booking_charge, add_booking_payment,
-- customerBookingPayment). The line-item shrink keeps the documented
-- SUM(line_total) = total_amount convention.
--
-- Booking rollup rule unchanged: net = total_price - discount - promo;
-- paid = sum(total_amount) over this booking's non-Pending booking_payment
-- rows. The shrunk row now contributes v_applied; the leftover is Pending
-- (excluded), so the booking lands 'Partially Paid' (or 'Fully Paid' if this
-- payment completed the net).
--
-- Based verbatim on 20260901153_m08_settle_transaction_rpc.sql.
--
-- The new trailing parameter changes the function's argument list, so the old
-- 6-arg version is dropped first (CREATE OR REPLACE cannot change a signature -
-- it would leave a stale overload that a 6-arg call still resolves to). The
-- only caller is transactionPayment.service.ts, updated in the same change to
-- always pass p_amount_applied.

drop function if exists public.settle_transaction(
  uuid, public.payment_method, text, text, numeric, uuid
);

create or replace function public.settle_transaction(
  p_transaction_id uuid,
  p_payment_method public.payment_method,
  p_bank_name text,
  p_payment_reference text,
  p_cash_tendered numeric,
  p_processed_by uuid,
  p_amount_applied numeric default null
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
  v_full numeric(10, 2);
  v_applied numeric(10, 2);
  v_leftover numeric(10, 2);
  v_leftover_id uuid;
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

  v_full := round(v_txn.total_amount, 2);
  v_applied := round(coalesce(p_amount_applied, v_full), 2);

  if v_applied <= 0 then
    raise exception 'settle_transaction: amount applied must be positive';
  end if;

  if v_applied > v_full + 0.001 then
    raise exception
      'settle_transaction: amount applied % exceeds transaction total %',
      v_applied, v_full;
  end if;

  v_leftover := round(v_full - v_applied, 2);

  -- Partial settlement: shrink this row + its line item to what was collected
  -- before flipping it Fully Paid, then spawn a Pending 'balance' row below.
  if v_leftover > 0 then
    update public.transactions
    set subtotal_amount = v_applied,
        total_amount = v_applied
    where id = p_transaction_id;

    update public.transaction_line_items
    set unit_price = v_applied,
        line_total = v_applied
    where transaction_id = p_transaction_id;
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

  if v_leftover > 0 then
    insert into public.transactions (
      booking_id, customer_id, branch_id, transaction_type,
      payment_method, payment_status, payment_choice,
      subtotal_amount, total_amount, processed_by_staff_id
    ) values (
      v_txn.booking_id, v_txn.customer_id, v_txn.branch_id, 'booking_payment',
      'Cash', 'Pending', 'balance',
      v_leftover, v_leftover, p_processed_by
    )
    returning id into v_leftover_id;

    insert into public.transaction_line_items (
      transaction_id, line_item_type, description, quantity, unit_price, line_total
    ) values (
      v_leftover_id, 'service', 'Remaining balance', 1, v_leftover, v_leftover
    );
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

revoke all on function public.settle_transaction(uuid, public.payment_method, text, text, numeric, uuid, numeric) from public;
grant execute on function public.settle_transaction(uuid, public.payment_method, text, text, numeric, uuid, numeric) to service_role;

-- ======================================================================
-- 20260902164_m10_pay_transaction_with_credit_partial.sql
-- ======================================================================

-- Architectural-Change-History "In Progress" row (Matthew) + chat follow-up:
-- partial settlement must spawn a remaining-balance transaction, and this must
-- also work when paying with account credit. Until now
-- pay_transaction_with_credit() was full-cover only (payTransactionWithCredit
-- 400'd with "split it first" when the balance didn't cover the whole charge).
--
-- This version applies whatever credit amount the caller passes (p_amount, the
-- service caps it at min(available, charge)); when that is less than the
-- transaction's total it shrinks the settled row + its line item to p_amount
-- and spawns a new Pending 'balance' transaction for the leftover - identical
-- mechanism to settle_transaction() (20260902163).
--
-- Signature unchanged (still 3 args), so plain CREATE OR REPLACE. Based
-- verbatim on 20260901158_m10_pay_transaction_with_credit_rpc.sql.

create or replace function public.pay_transaction_with_credit(
  p_transaction_id uuid,
  p_amount numeric,
  p_processed_by uuid
)
returns public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_txn public.transactions;
  v_balance public.credit_balances;
  v_booking public.bookings;
  v_net numeric(10, 2);
  v_paid numeric(10, 2);
  v_new_status public.payment_status;
  v_full numeric(10, 2);
  v_leftover numeric(10, 2);
  v_leftover_id uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'pay_transaction_with_credit: amount must be positive';
  end if;

  select * into v_txn
  from public.transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception 'pay_transaction_with_credit: transaction % not found', p_transaction_id;
  end if;

  if v_txn.transaction_type <> 'booking_payment' then
    raise exception 'pay_transaction_with_credit: transaction % is not a booking payment', p_transaction_id;
  end if;

  if v_txn.payment_status = 'Fully Paid' then
    raise exception 'pay_transaction_with_credit: transaction % is already Fully Paid', p_transaction_id;
  end if;

  if v_txn.booking_id is null then
    raise exception 'pay_transaction_with_credit: transaction % has no booking to roll up', p_transaction_id;
  end if;

  v_full := round(v_txn.total_amount, 2);

  if round(p_amount, 2) > v_full + 0.001 then
    raise exception
      'pay_transaction_with_credit: amount % exceeds transaction total %',
      p_amount, v_full;
  end if;

  v_leftover := round(v_full - p_amount, 2);

  -- Redeem the credit (redeem_credit()'s body, inlined so it shares this txn).
  select * into v_balance
  from public.credit_balances
  where customer_id = v_txn.customer_id
    and branch_id = v_txn.branch_id
  for update;

  if not found then
    raise exception
      'pay_transaction_with_credit: no credit balance for customer % at branch %',
      v_txn.customer_id, v_txn.branch_id;
  end if;

  if v_balance.balance < p_amount then
    raise exception
      'pay_transaction_with_credit: balance % is less than requested %',
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
  );

  -- Partial credit: shrink this row + its line item to the amount covered
  -- before flipping it Fully Paid, then spawn a Pending 'balance' row below.
  if v_leftover > 0 then
    update public.transactions
    set subtotal_amount = p_amount,
        total_amount = p_amount
    where id = p_transaction_id;

    update public.transaction_line_items
    set unit_price = p_amount,
        line_total = p_amount
    where transaction_id = p_transaction_id;
  end if;

  -- Settle the transaction as 'Credit'.
  update public.transactions
  set payment_status = 'Fully Paid',
      payment_method = 'Credit',
      credit_applied_amount = p_amount,
      processed_by_staff_id = p_processed_by,
      updated_at = now()
  where id = p_transaction_id
  returning * into v_txn;

  if v_leftover > 0 then
    insert into public.transactions (
      booking_id, customer_id, branch_id, transaction_type,
      payment_method, payment_status, payment_choice,
      subtotal_amount, total_amount, processed_by_staff_id
    ) values (
      v_txn.booking_id, v_txn.customer_id, v_txn.branch_id, 'booking_payment',
      'Cash', 'Pending', 'balance',
      v_leftover, v_leftover, p_processed_by
    )
    returning id into v_leftover_id;

    insert into public.transaction_line_items (
      transaction_id, line_item_type, description, quantity, unit_price, line_total
    ) values (
      v_leftover_id, 'service', 'Remaining balance', 1, v_leftover, v_leftover
    );
  end if;

  -- Roll the parent booking's payment_status up.
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

revoke all on function public.pay_transaction_with_credit(uuid, numeric, uuid) from public;
grant execute on function public.pay_transaction_with_credit(uuid, numeric, uuid) to service_role;

-- ======================================================================
-- 20260902165_m08_add_booking_payment_pending_aware.sql
-- ======================================================================

-- Architectural-Change-History "In Progress" row (Matthew): a downpayment
-- booking now starts with TWO transactions - a settled-later 'downpayment' row
-- AND a Pending 'balance' row (create_initial_booking_charge, 20260902162). The
-- old add_booking_payment() computed "remaining" as net - already-settled only,
-- and the service layer bolted on a guard rejecting any "Add a payment" while a
-- Pending charge existed. With a Pending balance row present from creation that
-- guard would block "Add a payment" forever.
--
-- Fix: net the Pending booking_payment rows too, so
--   remaining = net - sum(settled) - sum(pending)
-- and the app-side guard can be dropped - the RPC alone stops the outstanding
-- charges from ever exceeding the bill.
--
-- Signature unchanged. Based verbatim on 20260901154_m08_add_booking_payment_rpc.sql.

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
  v_pending numeric(10, 2);
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

  select coalesce(sum(t.total_amount), 0)
    into v_pending
  from public.transactions t
  where t.booking_id = p_booking_id
    and t.transaction_type = 'booking_payment'
    and t.payment_status = 'Pending';

  v_remaining := v_net - v_settled - v_pending;

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

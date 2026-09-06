-- Reference copy for session 72 (multi-booking checkout). Source of truth:
-- golden-fur/supabase/migrations/20260906173_m08_create_booking_groups_schema.sql
-- golden-fur/supabase/migrations/20260906174_m08_transactions_add_booking_group_id.sql
-- golden-fur/supabase/migrations/20260906175_m08_create_initial_booking_group_charge_rpc.sql
-- golden-fur/supabase/migrations/20260906176_m08_settle_transaction_group_aware.sql
-- golden-fur/supabase/migrations/20260906177_m10_pay_transaction_with_credit_group_aware.sql
-- Do not apply this file directly - it is a concatenated reference copy only.

-- ============================================================================
-- Source: golden-fur/supabase/migrations/20260906173_m08_create_booking_groups_schema.sql
-- ============================================================================
-- Multi-booking checkout: several independent bookings rows (each possibly
-- a different pet, category, date/time, staff/cage) can be created and paid
-- for together as a single cart - one shared discount, one shared promo, one
-- shared downpayment/payment-scheme decision, settled via one shared
-- transaction (or downpayment+balance transaction pair, mirroring
-- create_initial_booking_charge - 20260902162). booking_groups is the row
-- that carries that shared checkout state; each bookings row it covers is
-- linked back to it via the new bookings.booking_group_id column, but a
-- booking never requires a group - single-booking checkout is unaffected
-- (booking_group_id stays null).
--
-- Column shape deliberately mirrors bookings' own payment columns
-- (downpayment_amount, downpayment_required, downpayment_due_at,
-- payment_status, paid_at - see 20260718035 / 20260829147 / 20260901150)
-- and transactions' discount/promo columns (discount_amount, promo_amount -
-- see 20260731068 / 20260726049), since the group is standing in for what
-- would otherwise be per-booking values. payment_status reuses the exact
-- same public.payment_status enum bookings.payment_status was migrated onto
-- (20260901150) rather than inventing a parallel one.
--
-- net_total is the group's post-discount/promo total (analogous to
-- transactions.total_amount), computed and trusted server-side only - same
-- rationale as transactions.total_amount's "never trusted from client input"
-- comment (20260731068).

create table public.booking_groups (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customer_profiles(id),
  branch_id uuid not null references public.branches(id),
  -- Set when a receptionist builds the cart on behalf of a walk-in/phone-in
  -- client; NULL for self-service portal checkout - mirrors
  -- bookings.created_by_staff_id (20260718035).
  created_by_staff_id uuid references public.staff_profiles(id),
  selected_discount_id uuid references public.discounts(id),
  selected_promo_id uuid references public.promos(id),
  discount_amount numeric(10, 2) not null default 0,
  promo_amount numeric(10, 2) not null default 0,
  -- Post-discount/promo total for the whole cart; computed server-side only.
  net_total numeric(10, 2) not null,
  downpayment_amount numeric(10, 2),
  downpayment_required boolean not null default false,
  downpayment_due_at timestamptz,
  payment_status public.payment_status not null default 'Pending',
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bookings
  add column booking_group_id uuid references public.booking_groups(id);

create index bookings_booking_group_id_idx on public.bookings(booking_group_id);
create index booking_groups_customer_id_idx on public.booking_groups(customer_id);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- booking_groups is created and updated only by the API layer's checkout
-- endpoints (via create_initial_booking_group_charge - 20260906175 - and its
-- surrounding service-role Supabase client code), never by a direct client
-- table write - so, unlike bookings (which has customer-scoped INSERT/UPDATE
-- policies for self-service portal bookings) and transactions (which has
-- staff-scoped INSERT and Admin/Superadmin UPDATE/DELETE policies), no
-- INSERT/UPDATE/DELETE policy is declared here at all: RLS enabled with zero
-- write policies denies every authenticated-role write outright, and the
-- service role bypasses RLS entirely regardless of policies. Only read
-- access is granted, using the exact same two-tier idiom bookings' own read
-- policies use (20260718035): staff read-all via current_staff_role(), and
-- a customer reads only their own rows via customer_id = auth.uid().

alter table public.booking_groups enable row level security;

create policy "Staff can read booking groups"
  on public.booking_groups
  for select
  to authenticated
  using (public.current_staff_role() is not null);

create policy "Customers can read their own booking groups"
  on public.booking_groups
  for select
  to authenticated
  using (customer_id = auth.uid());

-- ============================================================================
-- Source: golden-fur/supabase/migrations/20260906174_m08_transactions_add_booking_group_id.sql
-- ============================================================================
-- Multi-booking checkout (see booking_groups - 20260906173): a settlement
-- for a cart of bookings needs to attach to the group as a whole rather than
-- to any single booking, so transactions gets a second, mutually-exclusive
-- FK alongside booking_id. transactions_booking_id_matches_type
-- (20260731068) previously required exactly one shape per transaction_type
-- (booking_id null for miscellaneous_sale, booking_id not null for
-- booking_payment); it is now widened so a booking_payment row satisfies it
-- via EITHER booking_id (single-booking checkout, unchanged) OR
-- booking_group_id (new multi-booking checkout), never both, and a
-- miscellaneous_sale row still has neither. Every row that satisfied the old
-- constraint still satisfies the new one - booking_group_id does not exist
-- before this migration, so it is null on every existing row, and "booking_id
-- is not null and booking_group_id is null" is exactly the old
-- booking_payment shape - so no backfill is needed.

alter table public.transactions
  add column booking_group_id uuid references public.booking_groups(id);

create index transactions_booking_group_id_idx on public.transactions(booking_group_id);

alter table public.transactions
  drop constraint transactions_booking_id_matches_type;

alter table public.transactions
  add constraint transactions_booking_id_matches_type check (
    (transaction_type = 'miscellaneous_sale' and booking_id is null and booking_group_id is null)
    or (transaction_type = 'booking_payment' and (
      (booking_id is not null and booking_group_id is null)
      or (booking_id is null and booking_group_id is not null)
    ))
  );

-- ============================================================================
-- Source: golden-fur/supabase/migrations/20260906175_m08_create_initial_booking_group_charge_rpc.sql
-- ============================================================================
-- Multi-booking checkout (booking_groups - 20260906173 / transactions.
-- booking_group_id - 20260906174): the group-checkout counterpart of
-- create_initial_booking_charge (20260902162), which stays untouched and
-- still serves plain single-booking checkout. This RPC creates the group's
-- shared initial charge(s) - the downpayment/balance pair or the single full
-- payment - in one Postgres transaction, same SECURITY DEFINER "the row +
-- its line item must be atomic, two PostgREST round trips can't guarantee
-- that" rationale as settle_transaction (20260901153) / add_booking_payment
-- (20260901154) / issue_credit (20260805097) / create_initial_booking_charge
-- (20260902162) itself.
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
-- (payment_status <> 'Pending'): the group stays payment_status 'Pending' and
-- (when a down payment is required) every booking in the group holds no slot
-- until the first row is actually settled - unchanged from the single-
-- booking flow. Invariant preserved: each row has exactly one line item with
-- line_total = total_amount. Every inserted row sets booking_id = null and
-- booking_group_id = the group's id (never both, per
-- transactions_booking_id_matches_type - 20260906174), and denormalizes
-- customer_id/branch_id from the group rather than from any one booking.
--
-- payment_method 'Cash' is a placeholder (a valid enum value), overwritten by
-- settle_transaction() when the money is collected. Caller (the checkout
-- endpoint) is best-effort: it logs a failure and never rolls the group or
-- its bookings back.

create or replace function public.create_initial_booking_group_charge(
  p_booking_group_id uuid,
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
  v_group public.booking_groups;
  v_dp numeric(10, 2);
  v_balance numeric(10, 2);
  v_txn public.transactions;
begin
  if p_scheme not in ('downpayment', 'full') then
    raise exception 'create_initial_booking_group_charge: bad scheme %', p_scheme;
  end if;

  select * into v_group
  from public.booking_groups
  where id = p_booking_group_id
  for update;

  if not found then
    raise exception 'create_initial_booking_group_charge: booking group % not found', p_booking_group_id;
  end if;

  if p_scheme = 'downpayment' then
    v_dp := round(coalesce(p_downpayment_amount, 0), 2);
    v_balance := round(coalesce(p_net_total, 0) - v_dp, 2);

    insert into public.transactions (
      booking_id, booking_group_id, customer_id, branch_id, transaction_type,
      payment_method, payment_status, payment_choice,
      subtotal_amount, total_amount
    ) values (
      null, v_group.id, v_group.customer_id, v_group.branch_id, 'booking_payment',
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
        booking_id, booking_group_id, customer_id, branch_id, transaction_type,
        payment_method, payment_status, payment_choice,
        subtotal_amount, total_amount
      ) values (
        null, v_group.id, v_group.customer_id, v_group.branch_id, 'booking_payment',
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
      booking_id, booking_group_id, customer_id, branch_id, transaction_type,
      payment_method, payment_status, payment_choice,
      subtotal_amount, total_amount
    ) values (
      null, v_group.id, v_group.customer_id, v_group.branch_id, 'booking_payment',
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

revoke all on function public.create_initial_booking_group_charge(uuid, text, numeric, numeric) from public;
grant execute on function public.create_initial_booking_group_charge(uuid, text, numeric, numeric) to service_role;

-- ============================================================================
-- Source: golden-fur/supabase/migrations/20260906176_m08_settle_transaction_group_aware.sql
-- ============================================================================
-- Multi-booking checkout (booking_groups - 20260906173 / transactions.
-- booking_group_id - 20260906174 / create_initial_booking_group_charge -
-- 20260906175): settle_transaction (20260901153, partial-amount version
-- 20260902163) is the RPC the cashier's "record a payment" action
-- (transactionPayment.service.ts recordTransactionPayment) calls to flip a
-- Pending booking_payment transaction to Fully Paid. It has always assumed
-- the transaction has a `booking_id` to roll `bookings.payment_status` up
-- against, unconditionally raising otherwise - which meant settling a
-- GROUP's downpayment/balance/full transaction (booking_id NULL,
-- booking_group_id set - the only shape create_initial_booking_group_charge
-- ever produces) threw instead of settling.
--
-- Fix, deliberately NOT duplicating the booking_groups rollup + sibling-
-- bookings mirror in SQL (recomputeBookingGroupPaymentStatus,
-- booking.service.ts, already does this in one place): when the just-
-- settled row is a group transaction (booking_id is null and
-- booking_group_id is not null), this RPC now
--   1. still spawns the Pending 'balance' leftover row for a partial
--      settlement (that's just another transactions insert - no
--      bookings-table involvement either way), against the SAME group
--      (booking_id null, booking_group_id carried over) rather than a
--      booking, and
--   2. returns NULL instead of raising or touching `bookings` at all -
--      there is no single `public.bookings` row to report back for a group
--      settlement (this function's `returns public.bookings` is unchanged;
--      returning NULL is the least-disruptive option since there is no
--      SETOF/array wrapping to instead return zero rows with). The caller
--      (transactionPayment.service.ts) doesn't use this RPC's return value
--      for a group transaction anyway - it calls
--      recomputeBookingGroupPaymentStatus(booking_group_id) right after,
--      the same way it already calls applyFirstBookingPaymentSideEffects
--      after settling a single booking's transaction.
--
-- The non-group path (booking_id not null - every booking created before
-- this feature, and every non-grouped booking going forward) is preserved
-- byte-for-byte: same shrink-then-flip-then-spawn-leftover-then-roll-up
-- sequence, same SQL text, just reached via an added `elsif`-style guard
-- rather than unconditionally. The "both null" shape stays defensively
-- unreachable (the transactions_booking_id_matches_type CHECK - 20260906174 -
-- guarantees a booking_payment row always has exactly one of the two set) but
-- still raises exactly as before if it were ever reached directly.
--
-- Signature unchanged (still 7 args, same as 20260902163), so plain
-- CREATE OR REPLACE. Based verbatim on
-- 20260902163_m08_settle_transaction_partial.sql.

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

  -- Group transaction: no single `bookings` row to roll up - leave that to
  -- the JS-side recomputeBookingGroupPaymentStatus (see this migration's own
  -- header note). Still spawn the Pending leftover row, against the group.
  if v_txn.booking_id is null and v_txn.booking_group_id is not null then
    if v_leftover > 0 then
      insert into public.transactions (
        booking_id, booking_group_id, customer_id, branch_id, transaction_type,
        payment_method, payment_status, payment_choice,
        subtotal_amount, total_amount, processed_by_staff_id
      ) values (
        null, v_txn.booking_group_id, v_txn.customer_id, v_txn.branch_id, 'booking_payment',
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

    return null;
  end if;

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

-- ============================================================================
-- Source: golden-fur/supabase/migrations/20260906177_m10_pay_transaction_with_credit_group_aware.sql
-- ============================================================================
-- Multi-booking checkout, credit-payment counterpart of
-- 20260906176_m08_settle_transaction_group_aware.sql - same problem
-- (pay_transaction_with_credit unconditionally raised
-- "has no booking to roll up" whenever `booking_id` was null, which is
-- exactly the shape every group transaction has), same fix shape.
--
-- When the transaction being paid is a group transaction (booking_id null,
-- booking_group_id set), this RPC still redeems the credit and settles the
-- transaction as 'Credit' exactly as before (that part is identical
-- regardless of booking vs. group - it only ever reads
-- v_txn.customer_id/branch_id), still spawns the Pending 'balance' leftover
-- row for a partial credit application (against the group instead of a
-- booking), but skips the `bookings` rollup entirely and returns NULL - the
-- caller (transactionPayment.service.ts payTransactionWithCredit) calls
-- recomputeBookingGroupPaymentStatus(booking_group_id) right after, mirroring
-- how it already calls applyFirstBookingPaymentSideEffects for the
-- single-booking path. See settle_transaction's own (20260906176) header
-- note for the fuller rationale on returning NULL here instead of changing
-- the return type.
--
-- Non-group path preserved byte-for-byte (same credit-redemption body, same
-- shrink-then-settle-then-spawn-leftover-then-roll-up sequence). The early
-- "no booking" guard now only raises when BOTH booking_id and
-- booking_group_id are null - defensively unreachable for a booking_payment
-- row per the transactions_booking_id_matches_type CHECK (20260906174), same
-- as before this change for every real caller.
--
-- Signature unchanged (still 3 args), so plain CREATE OR REPLACE. Based
-- verbatim on 20260902164_m10_pay_transaction_with_credit_partial.sql.

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

  if v_txn.booking_id is null and v_txn.booking_group_id is null then
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

  -- Group transaction: no single `bookings` row to roll up - leave that to
  -- the JS-side recomputeBookingGroupPaymentStatus (see this migration's own
  -- header note). Still spawn the Pending leftover row, against the group.
  if v_txn.booking_id is null then
    if v_leftover > 0 then
      insert into public.transactions (
        booking_id, booking_group_id, customer_id, branch_id, transaction_type,
        payment_method, payment_status, payment_choice,
        subtotal_amount, total_amount, processed_by_staff_id
      ) values (
        null, v_txn.booking_group_id, v_txn.customer_id, v_txn.branch_id, 'booking_payment',
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

    return null;
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


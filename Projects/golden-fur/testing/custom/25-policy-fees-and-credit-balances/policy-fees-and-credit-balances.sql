-- Sprint 5 Epic B addendum (#25) - bundled migrations for manual review/reference.
-- Source of truth is supabase/migrations/; this file mirrors those six files, in application order.

-- =============================================================================
-- 20260805094_m09_policy_configurations_downpayment_reschedule_fee_credit_expiry.sql
-- =============================================================================
-- Sprint 5 Epic B (#88): ALTER policy_configurations - downpayment %,
-- reschedule fee, credit expiry columns.
--
-- Numbering note: the Sprint5-EpicB-Guide assumed the latest merged
-- migration was ...092 and numbered this epic's migrations starting at 093.
-- The actual latest on dev is 20260804093 (m01_staff_unavailability_blocks_
-- leave_type), so this epic's 6 migrations are renumbered 094-099.
--
-- This is an ALTER, not a CREATE - policy_configurations already exists
-- (20260718037_m03_policy_configurations_stub.sql, Sprint 2 #52) and was
-- already extended once (20260804091, lunch break). Its existing columns,
-- unique indexes, RLS policies, and the enforcement_mode enum are untouched.
--
-- reschedule_fee_type is the only genuinely new enum this epic introduces -
-- enforcement_mode already exists and is reused as-is by cancellation_logs
-- below (095).

create type public.reschedule_fee_type as enum ('Flat', 'Percentage');

alter table public.policy_configurations
  add column downpayment_percentage numeric(5, 2) not null default 50.00
    check (downpayment_percentage >= 0 and downpayment_percentage <= 100),
  add column reschedule_fee_enabled boolean not null default false,
  -- Nullable: populated only when reschedule_fee_enabled = true.
  add column reschedule_fee_type public.reschedule_fee_type,
  add column reschedule_fee_value numeric(10, 2)
    check (reschedule_fee_value is null or reschedule_fee_value >= 0),
  -- NULL = unlimited free reschedules (documented default); 1 or 2 tightens
  -- it. Read against the existing bookings.reschedule_count column.
  add column reschedule_free_allowance integer
    check (reschedule_free_allowance is null or reschedule_free_allowance >= 0),
  add column credit_expiry_enabled boolean not null default true,
  add column credit_expiry_days integer not null default 30
    check (credit_expiry_days > 0);


-- =============================================================================
-- 20260805095_m09_create_cancellation_logs_schema.sql
-- =============================================================================
-- Sprint 5 Epic B (#89): cancellation_logs table.
--
-- Logs every cancellation/reschedule event and its policy outcome,
-- regardless of whether credit was actually issued, so Admin/Supervisor
-- dashboards always have a complete record (Modules-Features). Written by
-- server/src/features/booking/services/cancellationLog.service.ts (#91),
-- called from both cancellation.service.ts and reschedule.service.ts.
--
-- event_type is plain text, not an enum, matching the established
-- transaction_line_items.line_item_type convention (Sprint 5 Epic A).
-- Documented allowed values: 'cancellation', 'reschedule'.
--
-- enforcement_mode_applied reuses the pre-existing public.enforcement_mode
-- enum (created by 20260718037, Sprint 2 #52) - a snapshot of
-- policy_configurations.notice_enforcement_mode at event time, since the
-- configuration can change after the fact.
--
-- customer_id/branch_id are denormalized here (rather than derived
-- transitively through booking_id), mirroring transactions' own
-- denormalization rationale (Sprint 5 Epic A), so dashboards can filter
-- without a join through bookings.

create table public.cancellation_logs (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id),
  customer_id uuid not null references public.customer_profiles(id),
  branch_id uuid not null references public.branches(id),
  event_type text not null check (event_type in ('cancellation', 'reschedule')),
  notice_period_met boolean not null,
  enforcement_mode_applied public.enforcement_mode not null,
  -- True only for a Soft-mode event where notice was not met.
  policy_violation boolean not null default false,
  credit_issued boolean not null default false,
  -- Populated only when credit_issued = true.
  credit_amount numeric(10, 2)
    check (credit_amount is null or credit_amount >= 0),
  -- Populated only for event_type = 'reschedule' when a fee applied.
  reschedule_fee_charged numeric(10, 2)
    check (reschedule_fee_charged is null or reschedule_fee_charged >= 0),
  notes text,
  created_at timestamptz not null default now(),
  constraint cancellation_logs_credit_amount_requires_issued check (
    (credit_issued and credit_amount is not null)
    or (not credit_issued and credit_amount is null)
  ),
  constraint cancellation_logs_reschedule_fee_matches_type check (
    reschedule_fee_charged is null or event_type = 'reschedule'
  )
);

create index cancellation_logs_booking_id_idx on public.cancellation_logs(booking_id);
create index cancellation_logs_customer_id_idx on public.cancellation_logs(customer_id);
create index cancellation_logs_branch_id_idx on public.cancellation_logs(branch_id);

alter table public.cancellation_logs enable row level security;

-- Read-only for staff (AC-2): Admin/Supervisor/Superadmin, per the Guide's
-- own AC-2 wording. Write access has no `authenticated` policy at all -
-- only the server's service-role client (which bypasses RLS entirely,
-- Supabase's standard behavior) ever inserts a row, matching the "server-
-- role client, application-layer inserts only" requirement.
create policy "Admins and supervisors can read cancellation logs"
  on public.cancellation_logs
  for select
  to authenticated
  using (
    public.current_staff_role() in ('Superadmin', 'Admin', 'Supervisor')
  );


-- =============================================================================
-- 20260805096_m10_create_credit_balances_schema.sql
-- =============================================================================
-- Sprint 5 Epic B (#90): credit_balances table.
--
-- Per-customer, per-branch credit balance - branch-locked and non-
-- transferable (Modules-Features). UNIQUE(customer_id, branch_id) enforces
-- the branch-lock at the schema level; CHECK balance >= 0 is a second line
-- of defense behind the application-level min(balance, total) cap Epic A's
-- checkout applies on redemption.
--
-- CROSS-EPIC: Epic A's checkoutAggregation.service.ts (#84, already merged)
-- reads this table via server/src/features/billing/services/
-- creditStub.service.ts's stub interface - that stub's TODO(Epic B, #90)
-- comment names this table and this issue by number.

create table public.credit_balances (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customer_profiles(id),
  branch_id uuid not null references public.branches(id),
  balance numeric(10, 2) not null default 0.00 check (balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_balances_customer_branch_uniq unique (customer_id, branch_id)
);

create index credit_balances_customer_id_idx on public.credit_balances(customer_id);
create index credit_balances_branch_id_idx on public.credit_balances(branch_id);

alter table public.credit_balances enable row level security;

-- Read-only for everyone who can see it (AC-4): the owning customer reads
-- their own row(s); Cashier/Admin/Superadmin read any. No write policy for
-- `authenticated` - only the server's service-role client writes (via the
-- issue_credit() function below and future redemption/expiry paths).
create policy "Customers can read their own credit balances"
  on public.credit_balances
  for select
  to authenticated
  using (customer_id = auth.uid());

create policy "Cashiers and admins can read any credit balance"
  on public.credit_balances
  for select
  to authenticated
  using (public.current_staff_role() in ('Superadmin', 'Admin', 'Cashier'));


-- =============================================================================
-- 20260805097_m10_create_credit_transactions_schema.sql
-- =============================================================================
-- Sprint 5 Epic B (#90): credit_transactions table + the issue_credit()
-- atomic helper.
--
-- History of issuance/redemption/expiry events. transaction_type is plain
-- text, not an enum (same convention as cancellation_logs.event_type above
-- and transaction_line_items.line_item_type). Documented allowed values:
-- 'issuance', 'redemption', 'expiry'. amount is signed - positive for
-- issuance, negative for redemption/expiry - so SUM(amount) for a
-- credit_balances row always equals its balance.
--
-- transaction_id FKs to Epic A's already-merged public.transactions (#82) -
-- this table's only forward dependency on Epic A's schema, populated for
-- redemption rows once Epic A's credit-stub swap lands (tracked in
-- creditStub.service.ts, out of this epic's own scope - see this batch's
-- custom doc's Open Items).
--
-- expired_at (ADDITION beyond the Design sheet's literal column list): the
-- Design sheet's credit_transactions has no way to tell whether a given
-- 'issuance' row has already been swept by expire_credits() below without
-- it - there's no other row-level link between an issuance and the expiry
-- row that eventually offsets it. Nullable, only ever set (to the sweep
-- timestamp) on 'issuance' rows once expire_credits() has processed them;
-- always NULL for 'redemption'/'expiry' rows.

create table public.credit_transactions (
  id uuid primary key default gen_random_uuid(),
  credit_balance_id uuid not null references public.credit_balances(id),
  transaction_type text not null
    check (transaction_type in ('issuance', 'redemption', 'expiry')),
  amount numeric(10, 2) not null,
  cancellation_log_id uuid references public.cancellation_logs(id),
  transaction_id uuid references public.transactions(id),
  expires_at timestamptz,
  expired_at timestamptz,
  created_at timestamptz not null default now(),
  constraint credit_transactions_amount_sign_matches_type check (
    (transaction_type = 'issuance' and amount > 0)
    or (transaction_type in ('redemption', 'expiry') and amount < 0)
  ),
  constraint credit_transactions_expired_at_only_on_issuance check (
    expired_at is null or transaction_type = 'issuance'
  )
);

create index credit_transactions_credit_balance_id_idx
  on public.credit_transactions(credit_balance_id);
create index credit_transactions_cancellation_log_id_idx
  on public.credit_transactions(cancellation_log_id);
create index credit_transactions_transaction_id_idx
  on public.credit_transactions(transaction_id);
-- Sweep query in expire_credits() (099) filters on exactly this shape.
create index credit_transactions_expiry_sweep_idx
  on public.credit_transactions(expires_at)
  where transaction_type = 'issuance' and expired_at is null;

alter table public.credit_transactions enable row level security;

create policy "Customers can read their own credit transaction history"
  on public.credit_transactions
  for select
  to authenticated
  using (
    exists (
      select 1 from public.credit_balances cb
      where cb.id = credit_transactions.credit_balance_id
        and cb.customer_id = auth.uid()
    )
  );

create policy "Cashiers and admins can read any credit transaction history"
  on public.credit_transactions
  for select
  to authenticated
  using (public.current_staff_role() in ('Superadmin', 'Admin', 'Cashier'));

-- ---------------------------------------------------------------------------
-- issue_credit(): atomic increment-balance + write-issuance-row helper.
--
-- AC-1 (#93) requires the balance increment and the issuance
-- credit_transactions row to be atomic. A plain two-step application-layer
-- select-then-write (the pattern policy_configurations' own
-- updatePolicyConfiguration() already uses elsewhere in this codebase) can't
-- guarantee that across two separate PostgREST round trips, so this is a
-- single PL/pgSQL function instead - SECURITY DEFINER so the server's
-- service-role client can call it as a plain RPC while the whole increment +
-- insert happens inside one Postgres transaction.
-- ---------------------------------------------------------------------------
create or replace function public.issue_credit(
  p_customer_id uuid,
  p_branch_id uuid,
  p_amount numeric,
  p_cancellation_log_id uuid,
  p_expires_at timestamptz
)
returns public.credit_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance_id uuid;
  v_transaction public.credit_transactions;
begin
  if p_amount <= 0 then
    raise exception 'issue_credit: amount must be positive';
  end if;

  insert into public.credit_balances (customer_id, branch_id, balance)
  values (p_customer_id, p_branch_id, p_amount)
  on conflict (customer_id, branch_id)
  do update set
    balance = public.credit_balances.balance + excluded.balance,
    updated_at = now()
  returning id into v_balance_id;

  insert into public.credit_transactions (
    credit_balance_id, transaction_type, amount, cancellation_log_id, expires_at
  ) values (
    v_balance_id, 'issuance', p_amount, p_cancellation_log_id, p_expires_at
  )
  returning * into v_transaction;

  return v_transaction;
end;
$$;

revoke all on function public.issue_credit(uuid, uuid, numeric, uuid, timestamptz) from public;
grant execute on function public.issue_credit(uuid, uuid, numeric, uuid, timestamptz) to service_role;


-- =============================================================================
-- 20260805098_m10_create_credit_expiry_function.sql
-- =============================================================================
-- Sprint 5 Epic B (#93): expire_credits() + conditional pg_cron schedule.
--
-- Walks every not-yet-swept 'issuance' credit_transactions row whose
-- expires_at has passed (oldest expiry first), writes a negative 'expiry'
-- row for whatever portion of that issuance the balance can still cover
-- (redemption isn't wired to actually decrement anything yet - Epic A's
-- creditStub.service.ts always applies 0 - so in practice today this is
-- always the full issuance amount), decrements credit_balances by the same
-- amount, and marks the issuance row's expired_at so it's never
-- reprocessed. Returns the number of issuance rows swept.
--
-- Mirrors deactivate_expired_promos()'s SECURITY DEFINER + conditional
-- pg_cron precedent (20260715032_m13_create_maintenance_schema.sql): pg_cron
-- availability is an Open Item, so the schedule below is created only if the
-- extension is already installed; otherwise
-- server/src/features/credits/services/creditExpiry.job.ts's admin-
-- triggerable endpoint is the primary mechanism, not just a verification aid.

create or replace function public.expire_credits()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_swept integer := 0;
  r record;
  v_expire_amount numeric(10, 2);
begin
  for r in
    select ct.id, ct.credit_balance_id, ct.amount, cb.balance
    from public.credit_transactions ct
    join public.credit_balances cb on cb.id = ct.credit_balance_id
    where ct.transaction_type = 'issuance'
      and ct.expired_at is null
      and ct.expires_at is not null
      and ct.expires_at < now()
    order by ct.expires_at asc
  loop
    v_expire_amount := least(r.amount, greatest(r.balance, 0));

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

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'expire-credits',
      '10 0 * * *',
      'select public.expire_credits()'
    );
  else
    raise notice
      'pg_cron not installed - credit expiry relies on creditExpiry.job.ts''s manual-trigger endpoint';
  end if;
end;
$$;


-- =============================================================================
-- 20260805099_m09_bookings_pending_reschedule_fee_amount.sql
-- =============================================================================
-- Sprint 5 Epic B (#92): bookings.pending_reschedule_fee_amount.
--
-- GUIDE GAP: Sprint5-EpicB-Design.xlsx's DB Design sheet documents this
-- column under a "Cross-Module Note" (bookings, ALTER), and Issue #92's own
-- Development Notes say it's "written to bookings.pending_reschedule_fee_
-- amount (new nullable column, ALTER)" - but neither the Design sheet's
-- Files inventory nor the Guide's Directory Structure actually lists a
-- migration file for it among the 5 enumerated there. This migration fills
-- that gap; see this batch's custom doc for the full note.
--
-- Written by rescheduleFee.service.ts (#92) at reschedule confirmation; read
-- and cleared to NULL by Epic A's checkoutAggregation.service.ts once posted
-- as a transaction_line_items row of type 'reschedule_fee' (that read side
-- is Epic A follow-up work, not built by this epic - see Open Items).

alter table public.bookings
  add column pending_reschedule_fee_amount numeric(10, 2)
    check (pending_reschedule_fee_amount is null or pending_reschedule_fee_amount >= 0);


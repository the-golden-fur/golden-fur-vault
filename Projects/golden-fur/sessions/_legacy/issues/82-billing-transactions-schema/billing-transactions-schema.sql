-- Issue #82 -- Supabase SQL Editor verification queries.
--
-- Run these one section at a time in Supabase Studio: your project -> SQL
-- Editor -> New query. Sections 1-4 are read-only. Section 5 is a real
-- insert used to confirm the CHECK constraints and the SUM(line_total) =
-- total_amount invariant hold - it cleans up after itself inside a
-- begin/rollback block.
--
-- Prerequisite: migrations 20260731067/068/069 applied (supabase db reset).

-- =========================================================================
-- SECTION 1: transactions schema - enums, columns, CHECK constraints
-- =========================================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'transactions'
order by ordinal_position;
-- Expected: booking_id (nullable), customer_id/branch_id (not null),
-- transaction_type/payment_method/payment_status (USER-DEFINED, enums),
-- bank_name (nullable), subtotal_amount/discount_amount/promo_amount/
-- credit_applied_amount/total_amount (numeric), payment_reference/
-- misc_sale_description (nullable), webhook_confirmed_at/
-- processed_by_staff_id (nullable), created_at/updated_at.

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.transactions'::regclass and contype = 'c';
-- Expected 3 CHECK constraints: transactions_booking_id_matches_type,
-- transactions_bank_name_requires_bank_transfer,
-- transactions_misc_sale_description_matches_type.

-- =========================================================================
-- SECTION 2: transaction_line_items schema
-- =========================================================================

select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'transaction_line_items'
order by ordinal_position;
-- Expected: transaction_id, line_item_type (text), reference_id (uuid,
-- nullable, no FK), description, quantity (default 1), unit_price,
-- line_total, created_at.

-- =========================================================================
-- SECTION 3: the forward-declared transaction_promo_selections FK exists
-- (Epic B's migration 20260726049 left this as a comment-only TODO)
-- =========================================================================

select
  tc.constraint_name,
  ccu.table_name as references_table
from information_schema.table_constraints tc
join information_schema.constraint_column_usage ccu
  on tc.constraint_name = ccu.constraint_name
where tc.table_name = 'transaction_promo_selections'
  and tc.constraint_type = 'FOREIGN KEY'
  and ccu.table_name = 'transactions';
-- Expected: one row - transaction_promo_selections_transaction_id_fkey.

-- =========================================================================
-- SECTION 4: RLS is enabled and the Admin/Superadmin-only misc-sale
-- update/delete policies exist
-- =========================================================================

select relrowsecurity
from pg_class
where relname in ('transactions', 'transaction_line_items');
-- Expected: true for both.

select polname, polcmd
from pg_policy
where polrelid = 'public.transactions'::regclass
order by polname;
-- Expected 5 policies incl. "Admins and superadmins can update
-- miscellaneous sales" (polcmd = 'w') and "...delete miscellaneous sales"
-- (polcmd = 'd').

-- =========================================================================
-- SECTION 5: a real transaction + line items round-trips correctly, and
-- SUM(line_total) = total_amount holds (AC-4) - self-cleaning, rolled back
-- =========================================================================

begin;

with sample as (
  select
    (select id from public.customer_profiles limit 1) as customer_id,
    (select id from public.branches limit 1) as branch_id
),
new_txn as (
  insert into public.transactions (
    booking_id, customer_id, branch_id, transaction_type, payment_method,
    payment_status, subtotal_amount, discount_amount, promo_amount,
    credit_applied_amount, total_amount, misc_sale_description
  )
  select
    null, sample.customer_id, sample.branch_id, 'miscellaneous_sale', 'Cash',
    'Fully Paid', 250.00, 0, 0, 0, 250.00, 'Verification: Leash'
  from sample
  returning id
)
insert into public.transaction_line_items (
  transaction_id, line_item_type, description, quantity, unit_price, line_total
)
select id, 'misc_sale_item', 'Leash', 1, 250.00, 250.00
from new_txn;

select
  t.total_amount,
  sum(li.line_total) as summed_line_total,
  t.total_amount = sum(li.line_total) as invariant_holds
from public.transactions t
join public.transaction_line_items li on li.transaction_id = t.id
where t.misc_sale_description = 'Verification: Leash'
group by t.total_amount;
-- Expected: invariant_holds = true.

rollback;

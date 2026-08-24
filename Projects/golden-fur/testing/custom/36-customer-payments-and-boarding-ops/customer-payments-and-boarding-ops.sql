-- Bundled for reference only - source of truth is still supabase/migrations/.
-- Apply in order (all eight are additive/backfill, safe to run in one pass):
--   20260809115_custom_backfill_product_catalog_customer_owner.sql
--   20260809116_custom_downpayment_high_price_services.sql
--   20260809117_custom_policy_online_payments_enabled.sql
--   20260809118_custom_transactions_customer_initiated_payment.sql
--   20260809119_custom_bookings_reminder_sent_at.sql
--   20260809120_custom_care_log_entries_time_block.sql
--   20260809121_custom_care_log_entries_status.sql
--   20260809122_custom_cages_admin_crud.sql

-- ============================================================
-- 20260809115_custom_backfill_product_catalog_customer_owner.sql
-- ============================================================

-- Customers now own every food/medication catalog type they see (no more
-- "provided by the hotel" global-reference concept, see
-- module-4-hotel.seed.ts/.sql) - backfill any pre-existing global
-- (owner_customer_id IS NULL) hotel food/medication rows onto
-- customer1@goldenfur.com so they match the new seed convention instead of
-- being orphaned duplicates once the seed is re-run.
--
-- Reassigns in place (rather than delete+reinsert) so any existing
-- references to these product_catalog ids (e.g. saved care instructions)
-- keep pointing at the same row.

update public.product_catalog
set owner_customer_id = (
  select id from public.customer_profiles where account_email = 'customer1@goldenfur.com'
)
where owner_customer_id is null
  and category in ('food', 'medication')
  and service_scope = 'hotel'
  and exists (
    select 1 from public.customer_profiles where account_email = 'customer1@goldenfur.com'
  );

-- ============================================================
-- 20260809116_custom_downpayment_high_price_services.sql
-- ============================================================

-- High-price seeded services (>= ~PHP 1,000) now require a 50% downpayment,
-- matching the existing convention on Overnight Stay (Aircon Room) - see
-- 20260808112. A customer/receptionist selecting one of these during
-- booking is now restricted to that single service (see
-- CustomerBookingFlowPage.tsx's toggleServiceSelect + booking.service.ts's
-- server-side enforcement of the same rule).

update public.services
set requires_downpayment = true,
    downpayment_type = 'Percentage',
    downpayment_amount = 50
where id in (
  'a1300000-0000-4000-a000-000000000019', -- Dental Cleaning (1500)
  'a1300000-0000-4000-a000-000000000020', -- Surgery (3000)
  'a1300000-0000-4000-a000-000000000021'  -- Emergency Consultation (1000)
);

-- ============================================================
-- 20260809117_custom_policy_online_payments_enabled.sql
-- ============================================================

-- Admins/Superadmins can now enable or disable online (PayMongo) payments
-- per branch (or system-wide, via the null branch_id default row), same
-- toggle shape as the existing staff_picker_enabled_* columns on this
-- table. Read by isOnlinePaymentsEnabled() in staffPicker.service.ts and
-- exposed to the customer app via a small dedicated endpoint (customers
-- have no direct SELECT policy on this table, see 20260718037).

alter table public.policy_configurations
  add column online_payments_enabled boolean not null default true;

-- ============================================================
-- 20260809118_custom_transactions_customer_initiated_payment.sql
-- ============================================================

-- Customer self-service "Pay" button (booking payments page): a customer
-- can now pay their own booking online via PayMongo, creating a
-- booking_payment transaction the same way the cashier checkout flow
-- (checkoutBooking) already does - reusing the exact same table and the
-- exact same webhook reconciliation (confirmPaymongoWebhookEvent flips
-- Pending -> Fully Paid by payment_reference, unchanged).
--
-- Two new columns distinguish these customer-initiated rows so the webhook
-- can additionally advance the booking's payment_stage once one is
-- confirmed (bookings.payment_stage is otherwise only ever moved by a
-- staff Mark-as-Paid action or at booking creation - see
-- advancePaymentStage in booking.service.ts, reused as-is for this) without
-- changing any existing cashier-checkout behavior, which never sets these:
--
-- initiated_by: who created this transaction - 'staff' (default, matches
-- every pre-existing row) or 'customer'.
-- payment_choice: only meaningful for a customer-initiated booking_payment
-- row - 'full' or 'downpayment', so the webhook knows which
-- advancePaymentStage target applies.

alter table public.transactions
  add column initiated_by text not null default 'staff'
    check (initiated_by in ('staff', 'customer')),
  add column payment_choice text
    check (payment_choice in ('full', 'downpayment')),
  add constraint transactions_payment_choice_requires_customer_initiated
    check (payment_choice is null or initiated_by = 'customer');

-- ============================================================
-- 20260809119_custom_bookings_reminder_sent_at.sql
-- ============================================================

-- Configurable appointment-reminder timing (customer Settings > Preferences):
-- the reminder job used to run once/day at a fixed 8am and check "tomorrow"
-- bookings, which can't honor a per-customer offset (15 min / 1h / 3h / 1
-- day / 2 days before). It now polls every 15 minutes instead - this column
-- is the dedupe marker so a booking is only ever reminded once regardless
-- of how many poll ticks pass after its fire time, independent of whether
-- createNotification actually inserted a notifications row (a customer who
-- disabled both channels for this event still only gets checked once, not
-- re-evaluated every 15 minutes for the rest of the lookahead window).

alter table public.bookings
  add column reminder_sent_at timestamptz;

-- ============================================================
-- 20260809120_custom_care_log_entries_time_block.sql
-- ============================================================

-- Boarding Checklist (rename of Hotel Care Log, merged Hotel+Daycare): the
-- most important group-by is "time of day" (the Morning/Noon/Afternoon/
-- Evening block set on the originating care instruction), but that value
-- was only ever baked into care_log_entries.description as free text (e.g.
-- "Morning meal — 1 cup kibble") - not a real, queryable/groupable column.
-- Adds one nullable text column, backfilled for existing rows by parsing
-- the leading word off description (best-effort; new rows are populated
-- properly at generation time going forward - see generateCareLogEntries
-- in careInstructions.service.ts).

alter table public.care_log_entries
  add column time_block text
    check (time_block in ('Morning', 'Noon', 'Afternoon', 'Evening'));

update public.care_log_entries
set time_block = case
  when description ilike 'Morning %' then 'Morning'
  when description ilike 'Noon %' then 'Noon'
  when description ilike 'Afternoon %' then 'Afternoon'
  when description ilike 'Evening %' then 'Evening'
  else null
end
where time_block is null;

-- ============================================================
-- 20260809121_custom_care_log_entries_status.sql
-- ============================================================

-- Boarding Checklist Kanban view: a Pending/In Progress/Completed status
-- per task, not just the existing binary completed_at. completed_at/
-- completed_by remain exactly as before (still forced server-side, only
-- ever set when status transitions to 'Completed') - this adds the
-- intermediate 'In Progress' state Kanban's most important group-by needs.

alter table public.care_log_entries
  add column status text not null default 'Pending'
    check (status in ('Pending', 'In Progress', 'Completed'));

update public.care_log_entries
set status = 'Completed'
where completed_at is not null;

-- ============================================================
-- 20260809122_custom_cages_admin_crud.sql
-- ============================================================

-- Cage CRUD (Settings > Config): Admin/Superadmin can create, edit, and
-- delete specific cages, not just toggle Under Maintenance. Superadmin
-- already has an unrestricted "for all" policy (20260727050); this adds
-- the missing Admin-scoped INSERT/DELETE policies (UPDATE already exists
-- and already covers every column, not just status, so cage_label/size
-- edits need no new policy).
--
-- Deleting a cage with an active stay would orphan that stay's cage_id -
-- deleteCage() in cageStatus.service.ts blocks deleting an Occupied/
-- Reserved cage in application code; this policy only handles the "which
-- role" question, not that invariant.

create policy "Admins can create cages at their branch"
  on public.cages
  for insert
  to authenticated
  with check (
    public.current_staff_role() = 'Admin'
    and branch_id = (
      select sp.branch_id from public.staff_profiles sp where sp.id = auth.uid()
    )
  );

create policy "Admins can delete cages at their branch"
  on public.cages
  for delete
  to authenticated
  using (
    public.current_staff_role() = 'Admin'
    and branch_id = (
      select sp.branch_id from public.staff_profiles sp where sp.id = auth.uid()
    )
  );

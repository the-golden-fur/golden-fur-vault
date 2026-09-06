# Multi-booking checkout — several bookings, one shared payment

Branch: `feat/multi-booking-checkout` (off `dev`)

## The request, verbatim

> OR TO MAKE THINGS EASIER, just add a step before payment confirmation
>
> - Show list of bookings, make another booking and cancel booking buttons
>   below
> - No need for that append latest booking to previous end time feature
> - This uses a much simpler model, and still allows multiple bookings to
>   share payment, downpayment, promos or discounts

Decisions confirmed when asked (see `plan.md`): "Add another booking" lets a
different **pet** be picked each time; **branch** is shared across the whole
checkout; **one** discount and **one** promo apply to the combined total
(not per-booking); the backend represents the shared payment via a new
**`booking_groups`** table.

Follow-up bug report, once the feature was running:

> Luna has 2 services in this bundled booking but they can both be started at
> 11 AM on the same date — that seems a bit wrong. Perhaps make it so that
> start times for the specific pet of the chosen date are not selectable or
> hidden if they already have a service for it in the current bundled
> booking? Should only apply if it's a bundled booking, and for the current
> customer. Other customers should still be able to book that time, if it's
> done via online booking not walkin.

Scope note: an earlier, more complex design (auto-chaining each new
booking's start time to the previous one's end time, with staff/cage still
manual and optional overnight-stay overflow) was explored first and
explicitly rejected in favor of the plain list above — nothing from that
earlier design was built.

## Root cause / Context

Before this session, `bookings`, `transactions`, discounts, promos, and
downpayment were all scoped to exactly one booking — there was no concept of
several bookings sharing anything. Booking creation
(`server/src/features/booking/services/booking.service.ts`'s `createBooking`)
inserted one `bookings` row and called one initial-charge database function;
the client wizard (`CustomerBookingFlowPage.tsx`) tracked exactly one
in-progress booking's worth of state and submitted it once.

Once bookings could be grouped, a gap surfaced on its own: nothing stopped
the _same_ pet from being scheduled into two of its own group's bookings at
an overlapping time (each booking's date/time is still picked independently
in its own pass through the wizard) — the Luna bug above.

## What changed

### Database

- `20260906173_m08_create_booking_groups_schema.sql` — new `booking_groups`
  table (customer/branch, shared discount/promo/downpayment/payment-scheme
  fields, combined `net_total`, `payment_status`) and `bookings.booking_group_id`
  (nullable — a standalone booking is unaffected).
- `20260906174_m08_transactions_add_booking_group_id.sql` — `transactions.
booking_group_id` (nullable) plus a widened check constraint: a
  `booking_payment` transaction now attaches to exactly one of `booking_id`
  / `booking_group_id`, never both, never neither (a `miscellaneous_sale`
  row still has neither).
- `20260906175_m08_create_initial_booking_group_charge_rpc.sql` — group
  counterpart of the existing `create_initial_booking_charge`: same
  downpayment-scheme-makes-2-rows / full-scheme-makes-1-row shapes, scoped
  to a `booking_group_id` instead of a `booking_id`.
- `20260906176_m08_settle_transaction_group_aware.sql` /
  `20260906177_m10_pay_transaction_with_credit_group_aware.sql` — the two
  existing settlement database functions now recognize a group-keyed
  transaction (skip the single-booking rollup they used to require, leaving
  it to the new server-side `recomputeBookingGroupPaymentStatus`) instead of
  raising an error, which is what they did before this change whenever
  `booking_id` was null.

### Server

- `server/src/features/booking/services/bookingGroup.service.ts` (new) —
  `createBookingGroup()`: resolves every booking in the batch (pet
  ownership, eligibility, pricing, staff/cage), then resolves the shared
  discount/promo against the combined item list and the shared downpayment
  against the combined net total, inserts the group row plus every member
  booking, and creates one shared charge. Includes an in-request guard so
  two bookings in the _same_ batch can never claim the same staff member or
  cage at an overlapping time (this never came up for a single booking,
  since a booking can't compete with itself) — and, for the Luna bug, a
  matching guard so the _same pet_ can't end up in two overlapping bookings
  within one batch (Online bookings only — a receptionist's Walk-in is
  exempt, same as several other checks that already skip Walk-ins).
- `server/src/features/booking/services/booking.service.ts` —
  `recomputeBookingGroupPaymentStatus` (rolls a group's paid/unpaid status
  up from its shared transactions, then mirrors it onto every member
  booking) and `applyBookingGroupDownpaymentExpiry` (the group counterpart
  of the existing unpaid-downpayment auto-cancel sweep, so an abandoned,
  never-paid batch expires the same way a single unpaid booking already
  did).
- `server/src/features/booking/booking.controller.ts` /
  `booking.routes.ts` — new `POST /bookings/groups`.
- `server/src/features/booking/modules/validators/booking.validator.ts` —
  new `createBookingGroupValidator`, reusing the existing per-booking
  item/staff/cage/hotel-preference schema pieces.
- `server/src/features/billing/services/transactionPayment.service.ts` —
  settling (or paying with credit) a group-keyed transaction now calls
  `recomputeBookingGroupPaymentStatus` instead of the single-booking
  rollup.
- `server/src/features/billing/services/webhookConfirmation.service.ts` —
  an online (PayMongo) payment confirmation recognizes a group-keyed
  transaction the same way.
- `server/src/features/billing/services/checkoutAggregation.service.ts` —
  new `buildGroupCheckoutPreview`/`checkoutBookingGroup`, so a cashier can
  actually collect a batch's remaining balance in one action; new endpoints
  wired in `billing.controller.ts`/`billing.routes.ts`/`billing.validator.ts`.
- `server/src/features/billing/services/bookingTransactions.service.ts` —
  new `listBookingGroupTransactions`, for a batch's receipt/history.
- Deliberately deferred (noted, not built): a customer's own self-service
  "pay my balance" portal action for a batch (`customerBookingPayment.
service.ts`) — staff-assisted collection above is enough to make a batch's
  balance collectible; nothing blocks adding the self-service path later.

### Client

- `client/src/features/booking/pages/CustomerBookingFlowPage/
CustomerBookingFlowPage.tsx` — new `bookingsList` state (one frozen
  snapshot per booking already committed in this checkout), a new
  `'bookingsList'` wizard step ("Your bookings") rendered right before
  Review, "Add another booking" (jumps back to the Pet step, branch stays
  shared) and "Cancel booking" (removes one entry). The Review step's
  pricing (subtotal, applicable discounts/promos, downpayment) now reads
  off the combined list instead of a single booking. Submitting calls the
  existing single-booking endpoint unchanged when the list has exactly one
  entry, or the new group endpoint otherwise.
- `client/src/features/booking/components/BookingCountBadge/` (new) — "N
  bookings in this checkout" indicator next to the step bar.
- `client/src/features/booking/components/SlotPicker/SlotPicker.tsx` — new
  `excludedWindows` prop: any fetched time slot overlapping one of these
  windows is shown/disabled exactly like a genuinely unavailable one. The
  wizard passes the current pet's other booked windows from `bookingsList`
  (Online bookings only).
- `client/src/features/booking/booking.types.ts` / `api/booking.api.ts` —
  `BookingGroup`, `CreateBookingGroupPayload`/`Result`, `createBookingGroup()`.

## Manual test — step by step

1. Open your web browser and go to `http://localhost:5173`, log in as a
   customer (or start the receptionist flow at
   `http://localhost:5173/staff/bookings/new` and pick a walk-in/phone-in
   customer first).
2. Click **Book a service**. Pick a pet with an assessed weight class/coat
   type (e.g. **Max**), pick a branch, pick **Grooming**, pick a date/time
   and a staff preference, pick a service (e.g. **Bath**), click **Next**.
3. You should land on a new step labeled **Your bookings** in the step bar,
   showing one card for the booking you just configured (pet name, category,
   the service you picked, its date/time, its subtotal) and a badge reading
   **"1 booking in this checkout"** above the step bar. If you instead land
   directly on **Review**, the feature did not build correctly — stop here.
4. Click **Add another booking**. You should be returned to the **Pet**
   step. Pick a _different_ pet (e.g. **Luna**), a service type (e.g.
   **Daycare**), a date/time, a service, click **Next** through to **Your
   bookings** again — now it should show **2** cards and the badge should
   read **"2 bookings in this checkout"**.
5. On the second pet's Date & Time step, pick the exact same pet again via
   **Add another booking**, pick the same service type as one of that pet's
   existing bookings, and try to pick the exact same start time that pet
   already has booked in this checkout. That time slot should show
   **greyed out / "Unavailable"**, even though nothing else has taken it —
   this is the Luna fix. Picking a different time for that pet should work
   normally.
6. On **Your bookings**, click **Cancel booking** on one card — it should
   disappear and the badge count should drop by one.
7. Click **Next** to reach **Review**. You should see every remaining
   booking's items listed with a combined subtotal, and only **one**
   discount picker, **one** promo picker, and **one** payment-scheme choice
   for the whole checkout (not one per booking).
8. Click **Confirm booking**. You should land on **Bookings confirmed**
   (plural title, since there's more than one) with a status line per
   booking, and (if a downpayment was required) one shared downpayment
   notice, not one per booking.
9. As a Cashier/Admin, open the branch's **Transactions** page and confirm a
   single shared "Down payment"/"Full payment" charge exists — not one per
   booking in the batch — and that settling it marks every booking in the
   batch as paid.
10. Repeat steps 2–3 but click **Confirm booking** straight from **Your
    bookings** without ever clicking "Add another booking" (i.e. a list of
    exactly one). Confirm this still works exactly as it did before this
    session — one booking, one payment, no `booking_groups` row created.

See `testing/multi-booking-checkout.postman_collection.json` for the
`POST /bookings/groups` and group-checkout API-level requests, and
`testing/multi-booking-checkout.sql` for the migration reference copies.

## Test suites

- `server`: `npm test` — **997/997** passing (90 files); `npm run typecheck`
  clean; `npm run lint` — 0 errors (31 pre-existing `no-console` warnings,
  unrelated to this diff).
- `client`: `npx vitest run` — **774/774** passing (151 files); `npx tsc -b
--noEmit` clean; `npx eslint .` — 0 errors/warnings; `npm run build`
  (production Vite build) succeeds.
- Repo-wide: `npm run format:check` — clean.
- Migrations were **not** pushed (`supabase:push`) as part of this session —
  see `plan.md` / Open items below.

## Open items

- Migrations `20260906173`–`177` have not been applied to the linked
  Supabase project yet — run the `supabase-migration-push` skill (confirms
  the linked ref isn't production) before this reaches an environment that
  needs the new tables/columns/functions.
- Customer self-service "pay my balance" for a batch
  (`customerBookingPayment.service.ts`) was deliberately left for a
  fast-follow — today only staff (via the branch checkout screen) can
  collect a batch's remaining balance.
- `workflow-doc-sync` (matching this diff against existing
  `Library/golden-fur/features/**/workflows/` docs) was not run for this
  session, to conserve session budget — there is no pre-existing
  multi-booking workflow doc to go stale, so nothing is currently
  known-inconsistent, but the booking-creation workflow doc (if one exists)
  may be worth a follow-up pass describing the new list step.

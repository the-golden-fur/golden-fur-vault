# Move downpayment config from per-service to per-transaction

Branch: not yet created — staged directly on `dev`.

## The request, verbatim

> Down payment was configured per-service instead of per-transaction.
> During testing, the down payment toggle was found to apply at the
> individual service level rather than across the entire transaction. Per
> the proposal's scope, the down payment requirement should apply to all
> online payments/bookings as a whole.

— from the advisor walkthrough (`Projects/golden-fur/context/MsMayuga-URO-Aug27.pdf`,
summarized in `Projects/golden-fur/context/Architectural-Change-Suggestions.pdf`),
whose Part 2 dev-notes checklist item reads:

> Move the down payment toggle/config so it applies per transaction (all
> online bookings/services), not per individual service.
> Re-test down payment enforcement across grooming, hotel, daycare, and vet
> booking types after the fix.

## Root cause / Context

Downpayment had already moved twice before this pass. `20260805094` (Sprint
5 Epic B, `#88`) added a branch-wide `policy_configurations.downpayment_percentage`
(Hotel-only). `20260808110`-`20260808112` (custom change `#34`, later
revised by `#41`'s bug fix) replaced that with a **per-catalog-item** flag —
`services.requires_downpayment`/`downpayment_amount`/`downpayment_type`
(same on `packages`) — summed across whatever items were selected, and
dropped the branch-wide column entirely because it had never actually been
wired into `booking.service.ts` (that migration's own comment calls it "dead
code"). A side effect of the per-item design: `createBooking` rejected any
booking that combined a downpayment-flagged item with anything else ("must
be booked on its own"), and the admin had to flag each service/package
individually rather than set one policy.

This request reverses that second decision: downpayment goes back to being
a `policy_configurations` field (system-default + per-branch override, same
resolution as every other policy field), but this time actually wired in,
generalized to every service category (not Hotel-only), and computed once
against the whole booking transaction's `total_price` rather than summed
per selected item. The "must be booked alone" restriction is gone as a
direct consequence — nothing about the new config is tied to a specific
catalog item anymore.

## What changed

### Database

- `supabase/migrations/20260828143_m09_policy_configurations_downpayment.sql`
  — adds `policy_configurations.downpayment_enabled`/`downpayment_type`
  (`'Flat'`/`'Percentage'`)/`downpayment_amount`. Starts disabled
  (`downpayment_enabled` default `false`) — no behavior change ships until
  an Admin turns it on via the Policies page.
- `supabase/migrations/20260828144_m13_services_packages_downpayment_removal.sql`
  — drops `requires_downpayment`/`downpayment_amount`/`downpayment_type`
  (and their check constraints) from `services` and `packages`.
- `bookings.downpayment_required`/`downpayment_amount` and
  `stays.downpayment_amount` are unchanged — their meaning (a snapshot on
  the booking/stay) doesn't change, only how the value is computed.

### Server

- `services/staffPicker.service.ts` — `EffectivePolicy`/`DOCUMENTED_DEFAULTS`/
  `updatePolicyConfiguration`'s baseline object gain the three new fields;
  new exported `resolveDownpaymentPolicy(branchId)` (mirrors
  `isOnlinePaymentsEnabled`).
- `services/booking.service.ts` — `ResolvedBookingItem` loses its three
  downpayment fields; `resolveBookingItem` no longer copies them from the
  catalog row; the "must be booked on its own" rejection block is deleted;
  the per-item `catalogDownpaymentAmount` reduce is replaced with a single
  `resolveDownpaymentPolicy(input.branch_id)` call applied against
  `totalPrice`. Everything downstream (payment_stage derivation, the
  `bookings` insert, queue gating, cancellation credit conversion,
  `customerBookingPayment.service.ts`, `lineItemSources.service.ts`) reads
  `bookings.downpayment_amount`/`downpayment_required` unchanged — this
  boundary was already well isolated.
- `booking.controller.ts`/`booking.routes.ts` — new
  `GET /bookings/downpayment-status?branch_id=` (`jwtMiddleware` only, no
  role gate — same shape as the existing `online-payments-status` route),
  for the customer booking flow to preview the amount before submitting.
- `modules/validators/booking.validator.ts` — new
  `downpaymentStatusQueryValidator`; `updatePolicyValidator` gains the three
  fields plus a superRefine mirroring `reschedule_fee_type`/`value`'s own
  pairing + percentage-cap rules.
- `booking.types.ts` — `PolicyConfiguration`/`EffectivePolicy` gain the
  three fields; new `DownpaymentType` alias.
- `maintenance.validator.ts`/`maintenance.types.ts` — `DOWNPAYMENT_TYPES`,
  `requireDownpaymentAmount`, and the three fields removed from
  create/update service and package schemas/types.

### Client

- `api/booking.api.ts` — new `getDownpaymentStatus()` call.
- `booking.types.ts` — `PolicyConfiguration`/`UpdatePolicyPayload` gain the
  three fields; new `DownpaymentType` alias.
- `pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx` — new
  "Downpayment" section (enabled checkbox + type select + amount input),
  mirroring the existing "Reschedule fee" section's structure.
- `features/maintenance/maintenance.types.ts`,
  `pages/AdminServicesPage/AdminServicesPage.tsx`,
  `pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx` — all
  per-service/package downpayment form state, validation, payload fields,
  and read-only badges removed.
- `pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx` — removed
  `lockedDownpaymentService` and the single-item selection lock (in
  `toggleServiceSelect`/`togglePackageSelect` and the option-card JSX);
  fetches the branch's downpayment policy once (new effect) and computes
  `downpaymentAmount` against `subtotal` (the whole cart) the same way the
  server does. The pay-downpayment-now-vs-pay-in-full radio UI
  (`showPaymentChoice`) is unchanged — that's still a per-transaction
  concept, just no longer gated by a single locked item.

## Verification

### 1. Enable the policy

As Admin/Superadmin, open `/staff/admin/maintenance/policies`. Under
"Downpayment", check "Require a downpayment on the whole booking", set type
"Percentage of booking total", amount `50`. Save — either system-wide
(no branch selected) or for one branch.

### 2. Customer booking flow

As a customer, start a booking for any category at that branch, select
**two or more** services (previously impossible for a downpayment-flagged
item — confirm no restriction appears here at all). Confirm the pricing
summary shows "Downpayment required now: PHP `<50% of the combined total>`",
and (if paying online) the "pay downpayment now vs. pay in full" choice
appears. Submit and confirm the created booking's `downpayment_amount`
matches that combined-total calculation, not a sum of individual items'
own catalog flags (there is no such flag left to sum).

### 3. Queue gating still works

Confirm a Pending downpayment-required-but-Unpaid booking is excluded from
the Grooming/Hotel/Daycare/Veterinary staff queues, and reappears once
`payment_stage` advances (Mark as Paid, or the customer's online Pay).

### 4. Admin catalog pages have no downpayment fields left

On `/staff/admin/maintenance/services` and `.../packages`, confirm there is
no "Requires a downpayment" toggle anywhere on the create/edit forms or the
read-only list.

### 5. API-level checks (Postman)

See `downpayment-per-transaction-policy.postman_collection.json` in this
folder — covers `PATCH /bookings/policy` (enable Flat and Percentage),
`GET /bookings/downpayment-status`, and a multi-item `POST /bookings` that
used to be rejected under the old per-item rule.

## Test suites

- `server`: `npm run test` (from `server/`) — **887/887 passing** (85
  files), `npx tsc --noEmit` clean.
- `client`: `npm run test` (from `client/`) — **696/696 passing** (137
  files), `npx tsc -b` clean.
- `npx eslint` clean on every file touched by this change, both packages.

## Open items

- **Migrations were not applied to a local Supabase instance** — Docker
  Desktop wasn't running in the environment this change was made in, so
  `supabase db reset` should be run and checked before this merges, per the
  usual convention (confirm `20260828143`/`20260828144` apply cleanly after
  `20260825142`, the actual latest at the time of writing).
- **No default-value backfill** was applied to make downpayment behave like
  the old seeded 50%-Hotel/high-price-Vet-services default — it starts
  fully disabled system-wide. If the client wants that pre-existing
  behavior restored, an Admin needs to explicitly enable it (Percentage,
  50%) via the Policies page after this ships.

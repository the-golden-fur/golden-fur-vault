# Fix: can't disable downpayment for Hotel-type services

Branch: `41-fix-service-downpayment-toggle`

## The request, verbatim

> fix not being able to disable downpayment for hotel type services:
> new row for relation "services" violates check constraint
> "services_downpayment_amount_check"

(One item split out of a larger bundled request - see "Scope note" below.)

## Scope note

The original message also asked for three other, much larger changes:
a "number of promos" cap type on the Promo Cap Configuration page, a full
"..." actions-menu/modal rework of the Services/Service Types/Packages admin
pages, and a real per-transaction downpayment amount in the cashier
Payments Queue's "Mark as Paid" flow. Investigation found a fourth item
(partial/full payment choice in the customer booking flow) is **already
shipped** (see #34/#36). Given how differently sized these are, and that
this repo's history is one PR per cohesive feature, only the bug fix below
was implemented in this pass; the other three are deferred to their own
future requests.

## Root cause

`services.downpayment_amount`/`packages.downpayment_amount` are governed by
`services_downpayment_amount_check`/`packages_downpayment_amount_check`
(added in migration `20260808112`): when `requires_downpayment = false`,
**both** `downpayment_amount` and `downpayment_type` must be `NULL`.

On the admin Services/Packages edit form
(`AdminServicesPage.tsx`/`AdminPackageBuilderPage.tsx`), the "Requires a
downpayment..." toggle only flipped `requiresDownpayment` in form state -
the amount/type inputs simply unmounted when it was off, leaving whatever
value was last typed sitting in state. On save, the update payload gated
`downpayment_type` on the toggle but **not** `downpayment_amount` - so
turning the toggle off on a service that previously required, say, a flat
PHP 500 downpayment sent `{ requires_downpayment: false, downpayment_amount:
500, downpayment_type: null }`, tripping the "both must be null" branch of
the constraint. The same gap existed in the create-form payload on both
pages (type overrides, but not amount, gated on the toggle).

Separately, the server-side validator (`requireDownpaymentAmount` in
`maintenance.validator.ts`, shared by `updateServiceValidator`/
`updatePackageValidator`/`createServiceValidator`/`createPackageValidator`)
only ever validated the "`requires_downpayment` true" branch. A payload
like the one above passed Zod validation cleanly and fell straight through
to the raw Postgres constraint error (a 500, not a friendly 400) - so even
a non-buggy API client sending that exact shape would have hit the same
opaque failure.

## What changed

### Client

- `client/src/features/maintenance/pages/AdminServicesPage/AdminServicesPage.tsx`
  - Update payload: `downpayment_amount` is now gated on
    `form.requiresDownpayment`, same as `downpayment_type` already was.
  - Create payload: the `downpayment_amount`/`downpayment_type` spread is
    now also gated on `form.requiresDownpayment`, not just on whether the
    amount field happens to have a value.
- `client/src/features/maintenance/pages/AdminPackageBuilderPage/AdminPackageBuilderPage.tsx`
  - Same two fixes, mirrored for packages.

### Server

- `server/src/features/maintenance/modules/validators/maintenance.validator.ts`
  - `requireDownpaymentAmount` now also enforces the constraint's other
    branch: when `requires_downpayment === false` is explicitly sent,
    `downpayment_amount`/`downpayment_type` must be `null` or absent -
    otherwise a `400` with a clear message is returned instead of the raw
    DB error. (An _omitted_ `requires_downpayment` on a partial `PATCH`
    that only touches other fields is untouched by this - only an explicit
    `false` triggers the new check, so a PATCH that doesn't mention
    downpayment at all still works as a no-op partial update.)

No migration was needed - the DB constraint was already correct; the bug
was purely in what the client/server sent it.

## Verification

### 1. Client - Services page

1. As Admin/Superadmin, open `/staff/admin/maintenance/services`.
2. Create (or edit an existing) service, check "Requires a downpayment
   before the service can start", set type "Flat amount (PHP)" and amount
   `500`, save. Confirm it saves and shows a "Requires PHP 500.00
   downpayment" badge.
3. Edit that same service again, uncheck "Requires a downpayment..." (do
   **not** clear the amount field first - leave it as-is, mirroring the
   original bug report), save.
4. Confirm the save succeeds (no `services_downpayment_amount_check`
   error), the badge disappears, and re-opening the edit form shows the
   downpayment fields hidden with the toggle off.

### 2. Client - Package Builder page

Repeat steps 2-4 above on `/staff/admin/maintenance/packages` against a
package instead of a service.

### 3. API-level checks (Postman)

See `fix-service-downpayment-toggle.postman_collection.json` in this
folder.

1. Import the collection, fill in `base_url` and an Admin login
   (`admin_identifier`/`admin_password`).
2. Run requests in order, top to bottom. Request 3 sends the exact
   pre-fix buggy payload directly (bypassing the now-fixed client) and
   confirms the server responds `400` with a validation message, not a
   raw `500`. Request 4 sends the fixed client's actual payload shape and
   confirms it succeeds with both fields nulled.

## Test suites

- `server`: `npm run test` (from `server/`) - all passing, including 5 new
  cases in `maintenance.validator.spec.ts` (`updateServiceValidator`/
  `updatePackageValidator` describe blocks) covering the new
  "`requires_downpayment: false` with a stale amount/type is rejected"
  behavior and confirming the true-branch/omitted-field cases are
  unaffected.
- `client`: `npm run test` (from `client/`) - all passing, including 1 new
  case in `AdminServicesPage.spec.ts` that edits a downpayment-flagged
  service, toggles it off, and asserts `updateService` is called with
  `downpayment_amount: null, downpayment_type: null` instead of the stale
  value.

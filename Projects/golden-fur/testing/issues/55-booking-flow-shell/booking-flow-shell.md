# Issue #55 Verification: 8-step booking flow shell + step navigation

**Issue:** #55 — feat(booking): 8-step booking flow shell + step navigation
**Owner:** James
**Branch:** `feat/booking-flow-shell`
**Base:** `dev`
**Depends on:** #51 merged
**Sprint:** Sprint 2 — Epic B — M03 Appointment & Booking

## Overview

Adds the customer-facing booking flow shell at `CustomerBookingFlowPage`
(pet → branch → service/package selection steps, wired here; Slot
Picker/Staff Picker/add-ons/payment plug into later steps in #56–#58), the
shared `BookingStepper` step-navigation chrome, the shared `BookingStatusBadge`
pill (reused by #59/#60), the `booking.types.ts`/`booking.api.ts` client
mirrors of the server's booking contract, and `booking.routes.tsx`. The same
page component is reused for the receptionist walk-in/phone-in variant (AC-5)
— which mode renders is resolved from the route prefix (`/portal/book` vs
`/staff/bookings/new`), not a separate implementation.

## What Changed

- **Added** `client/src/features/booking/booking.types.ts` /
  `client/src/features/booking/api/booking.api.ts` — client mirrors of
  `server/src/features/booking/booking.types.ts` and the booking REST surface.
- **Added** `client/src/features/booking/components/BookingStepper/` — dynamic
  step-count/label chrome; back-navigation to any completed step without
  losing later-step state (AC-2); forward navigation gated by the current
  step's validity.
- **Added**
  `client/src/features/booking/components/shared/BookingStatusBadge/` —
  Confirmed/Completed/Pending/Cancelled/No-show pill.
- **Added** `client/src/features/booking/pages/CustomerBookingFlowPage/` — the
  flow shell itself, this issue's pet/branch/service selection steps, plus the
  receptionist customer-lookup-or-create step (reuses `NewWalkInCustomerForm`
  from #35 unmodified) and the "add a pet" affordance (reuses `PetForm` from
  #32 unmodified).
- **Added** `client/src/features/booking/booking.routes.tsx` — registers
  `/portal/book` (`CustomerAuthGuard`) and `/staff/bookings/new`
  (`StaffAuthGuard`), both pointing at `CustomerBookingFlowPage`.
- **Modified** `client/src/routes.tsx` — mounts `bookingRoutes`.
- **Modified** `client/src/features/maintenance/maintenance.types.ts` /
  `api/maintenance.api.ts` — added `is_vet_branch` to the shared
  `BranchSummary`/`listBranches()` (additive, non-breaking) so this step can
  filter Veterinary out of the category list at Southwoods (AC-3).
- **Modified** `client/vite.config.ts` — added the `/bookings` dev-server
  proxy entry (every other feature's routes already had one; booking's was
  missing).
- **Modified** `client/src/styles/tokens.css` /
  `client/src/styles/variables/spacing.css` — booking status/slot color
  tokens and layout sizing tokens (`--booking-flow-max-width`,
  `--slot-button-min-width`, `--staff-option-card-min-width`,
  `--booking-queue-row-min-height`) for this and the remaining Epic B issues.

### Follow-up fix — no navigation entry point to the new routes

Landing `booking.routes.tsx` alone left the flow unreachable through normal
navigation: the customer portal's `/portal` route was still Epic A's
placeholder `<div>Customer portal</div>` with no links anywhere, and the
staff dashboard's `receptionist`/`admin`/`supervisor` tile configs had a
"Bookings Queue" tile with no `to` (rendered "Coming soon"). Fixed
alongside this issue rather than left as a silent dead end:

- **Added** `client/src/features/customers/pages/CustomerPortalPage/`
  (`.tsx`, `.module.css`, `.spec.ts`) — replaces the inline placeholder with
  three tiles: Book a Service (`/portal/book`), My Bookings
  (`/portal/bookings`), My Profile (`/portal/profile`).
- **Modified** `client/src/features/auth/customer/customerAuth.routes.ts` —
  `/portal` now renders `CustomerPortalPage`.
- **Modified** `client/src/features/staff/dashboards/staffDashboard.config.ts`
  — wired the Receptionist dashboard's existing "Bookings Queue" tile to
  `/staff/bookings/queue`, and added the same tile to the Admin and
  Supervisor dashboards (M03 Process 6: "Receptionist, Admin, or Supervisor
  opens branch dashboard").

### Follow-up fix — the Service step's data source was staff-only (403 for customers)

Manual verification against a real running stack surfaced a bigger gap than
the routing one above: this step originally called
`listServices`/`listPackages`/`listPromos` from
`client/src/features/maintenance/api/maintenance.api.ts` directly. Those hit
`GET /maintenance/*`, which is staff-only **at both layers** — the Express
route (`requireRole([...MAINTENANCE_READ_ROLES]))`, all 8 staff roles, no
customer) and the underlying Postgres RLS policy
(`using (current_staff_role() is not null)`). A logged-in customer got a
403 on every one of those calls; there's no RLS-level fallback (unlike
`branches`, which really is open to any authenticated user) since Epic A's
catalog was built as a staff/admin tool with no customer-facing read path,
even though the M03 Guide's own text assumes "booking step 3 reads directly
from the services and packages tables Epic A creates."

Fixed with a booking-scoped read-through rather than loosening Epic A's
already-merged RLS/route roles:

- **Added** `server/src/features/booking/services/catalog.service.ts`
  (+spec) — `getBookingCatalog({branchId, category?})` calls the existing
  `listServices`/`listPackages`/`listPromos` functions from
  `maintenance/services/*.service.ts` directly (server-side, service-role
  client) and returns their already-active-by-default results. No new RLS
  policy, no Epic A route change.
- **Modified**
  `server/src/features/booking/modules/validators/booking.validator.ts` /
  `booking.controller.ts` / `booking.routes.ts` — registers
  `GET /bookings/catalog` (`jwtMiddleware` only — customer-or-staff, same
  tier as booking creation).
- **Modified** `client/src/features/booking/api/booking.api.ts` — added
  `getBookingCatalog()`; the flow page now calls this instead of the three
  `maintenance.api.ts` functions.

### Follow-up fix — the Staff-step gate itself also called a staff-only endpoint

The `steps` computation originally resolved "is the Staff Picker toggle
enabled" via `GET /bookings/policy` (`resolveEffectivePolicy()` in a
since-deleted `booking.utils.ts`) — also staff-only per #52's own dev notes
("the booking flow itself \[server-side\], not client-exposed, can read
it"). Fixed by moving that resolution into `StaffPickerList` itself, via a
new `onUnavailable` callback prop fired from the endpoint it already calls
(`GET /bookings/staff-picker`, customer-accessible): the flow page
tentatively includes the "Staff" step for Grooming/Veterinary, and
`onUnavailable` flips a `staffPickerUnavailable` flag that removes it from
`steps` once resolved — the AC-1 "absent, not shown-then-hidden" contract
now holds without ever reading `policy_configurations` from a customer
session. `testing/docs/issues/59-customer-booking-management-ui/` and
`60-receptionist-bookings-queue-ui/`'s reschedule panels use the same fix.

### Scope note — supporting server endpoints

`#56` (Slot Picker) and `#59`/`#60` (bookings lists) needed two more small
reads that didn't exist anywhere in the merged `#51`/`#52` backend: a
capacity-by-slot endpoint (`checkCapacity()` was server-internal only,
gated by env-var stub config the client can't reach) and a bookings-list
endpoint (only `GET /bookings/:id` existed). `GET /bookings/availability`
and `GET /bookings` were added as minimal, additive reads to unblock those
issues — see `testing/docs/issues/56-slot-picker-ui/` and
`testing/docs/issues/59-customer-booking-management-ui/` for their own
verification. Neither of those two is part of this doc (#55); the catalog
endpoint above is.

## Automated Verification

```powershell
npm --prefix server test -- --run src/features/booking/services/catalog.service.spec.ts
npm --prefix server run typecheck
npm --prefix server run lint
npm --prefix client test -- --run src/features/booking/components/BookingStepper src/features/booking/components/shared/BookingStatusBadge src/features/booking/components/StaffPickerList src/features/booking/pages/CustomerBookingFlowPage src/features/customers/pages/CustomerPortalPage
npm --prefix client run lint
npm --prefix client exec tsc -b
```

Expected: all listed spec files pass (including
`CustomerBookingFlowPage.spec.ts`'s regression test that asserts
`getBookingCatalog` is called instead of any `/maintenance/*` function),
ESLint reports 0 problems, and both typecheck steps complete cleanly.

## Postman Verification (catalog endpoint)

Needs one **customer** account and `branch_makati_id` from Supabase Studio.

1. Import `booking-flow-shell.postman_collection.json` → fill collection
   variables → Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom:
   1. **Login customer** → 200.
   2. **Customer reads the Makati catalog** → 200; `{ services, packages,
promos }`, all active-only, `services` non-empty (module-3 seed has
      21 services).
   3. **Category filter narrows services** → 200; every returned service's
      `category` equals `Grooming`.
4. No cleanup needed — read-only.

## Manual Browser Verification

Requires the local Supabase stack, the API server, and the Vite client all
running, with the module-1/2/3 seeds applied.

1. Start Supabase (Docker Desktop must be running first):

   ```powershell
   npx supabase start
   ```

   If unsure the seeds are applied: `npx supabase db reset` (wipes local data
   and re-runs every migration + seed).

2. In one terminal: `npm --prefix server run dev`
3. In a second terminal: `npm --prefix client run dev`
4. Open the URL Vite prints (usually `http://localhost:5173`).

**Seeded accounts** (all passwords `password123`):

- Customer: `customer1@goldenfur.com` — pets Max (Dog, M, SC) and Luna (Cat,
  S, LC).
- Receptionist: `makati.receptionist1@goldenfur.com`.

### Step 0 — Reachable from the portal home, not just by URL

1. Log in as `customer1@goldenfur.com`. You land on `/portal`.

Expected: three tiles — **Book a Service**, **My Bookings**, **My
Profile** — not a blank/placeholder page. Click **Book a Service**.

Expected: navigates to `/portal/book` — the same flow shell as if you'd
typed the URL directly. (Also try the **Golden Fur** brand link in the
Navbar from any other portal page — it returns here.)

1. Log out, log in as `makati.receptionist1@goldenfur.com`. From `/staff`
   (redirects to your role dashboard), find the **Bookings Queue** tile.

Expected: it's a real link now (no "Coming soon" badge) and opens
`/staff/bookings/queue` (#60).

### Step 0.5 — No 403s in the console (regression check)

1. As `customer1@goldenfur.com`, open browser DevTools (F12) → **Console**
   and **Network** tabs, then go through the Pet → Branch → Service steps
   of `/portal/book`.

Expected: **zero** 403 responses anywhere in the Network tab — specifically
none for `GET /bookings/policy` or `GET /maintenance/services`
`/packages` `/promos`. The Service step should show real service cards
(e.g. seeded Grooming services like "Bath") sourced from
`GET /bookings/catalog` instead. If you still see 403s here, the fix in
this doc's "Follow-up fix" sections above didn't take.

### Step 1 — Customer flow, dynamic step count (AC-1)

1. Log in as `customer1@goldenfur.com` and navigate to
   `http://localhost:5173/portal/book`.
2. Expected: the stepper shows **Pet, Branch, Service, Date & Time,
   Add-ons, Review & Pay** (6 steps) as its starting shape — no receptionist
   "Customer" step, and Staff/Add-ons steps aren't decided yet since no
   category is chosen.
3. Select pet **Max**, click **Next**; select branch **Makati**, click
   **Next**.
4. On the Service step, select category **Hotel**.
5. Expected: the stepper's step count/labels update immediately (no page
   reload) — **Staff** never appears for Hotel, and **Add-ons** disappears
   too (Grooming-only). — **AC-1**
6. Go back (stepper) to Service and switch category to **Grooming**.
7. Expected: **Staff** and **Add-ons** both reappear in the stepper. — **AC-1**

### Step 2 — Back navigation preserves state (AC-2)

1. With category **Grooming** selected and a service picked, click **Next**
   to reach Date & Time, then use the stepper to click back on **Service**.
2. Expected: your previously-selected service is still highlighted/selected
   — nothing was cleared by navigating back. — **AC-2**
3. Try clicking a stepper label two steps ahead of your current step (e.g.
   **Review & Pay** from **Service**).
4. Expected: nothing happens — forward navigation is blocked until the
   steps in between are completed (the label isn't clickable past what
   you've reached). — **AC-2**

### Step 3 — Southwoods hides Veterinary (AC-3)

1. From the Service step, use the stepper to go back to **Branch** and
   select **Southwoods**.
2. Expected: the Service step's category selector no longer offers
   **Veterinary** as an option at all. — **AC-3**
3. Go back to **Branch** and reselect **Makati** — **Veterinary** reappears.

### Step 4 — Package selection is read-only (AC-4)

1. On the Service step (Makati branch), switch the tab to **Package**.
2. Expected: the seeded **Golden Package** (PHP 600) appears with its 3
   bundled services listed underneath as plain text — no checkboxes, no way
   to edit which services are included. — **AC-4**

### Step 5 — Receptionist entry point (AC-5)

1. Log out, log in as `makati.receptionist1@goldenfur.com`, and navigate to
   `http://localhost:5173/staff/bookings/new`.
2. Expected: the **same** page/component loads, but with an extra
   **Customer** step first — a "Check account" form (email + full name).
3. Enter an email not in the seed data (e.g. `walkin-test@example.com`) and a
   name, click **Check account**, then **Create customer**.
4. Expected: the flow advances straight into the normal **Pet** step (now
   scoped to the new walk-in customer, who has no pets yet) — confirming this
   is the same shell reused, not a forked implementation. — **AC-5**

## Acceptance Criteria Checklist

- [x] **AC-1:** Stepper renders the correct step sequence/count per service
      type, correctly omitting Staff Picker — `BookingStepper.spec.ts`;
      manual Step 1.
- [x] **AC-2:** Back navigation to any completed step preserves later-step
      selections; forward navigation blocked until required fields are
      filled — `BookingStepper.spec.ts`; manual Step 2.
- [x] **AC-3:** Southwoods removes Veterinary from the selectable service
      list — manual Step 3 (no dedicated unit test; covered end-to-end
      since it depends on live `branches.is_vet_branch` data).
- [x] **AC-4:** Package selection shows included services read-only, no edit
      affordance — manual Step 4.
- [x] **AC-5:** The receptionist entry point reuses this shell with an added
      pet/customer lookup-or-create step, not a separate implementation —
      manual Step 5 (same component/file for both routes, verifiable in
      `booking.routes.tsx`).

No Postman collection or SQL file for this issue: it adds no new API route
or DB object of its own (it consumes #51's existing `POST /bookings` and
Epic A's maintenance endpoints, both already covered by their own issues'
testing docs).

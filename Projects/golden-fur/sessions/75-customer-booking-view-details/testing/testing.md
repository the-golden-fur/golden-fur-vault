# "View details" for a customer's booking + real pet/owner names for cashiers

Branch: `feat/customer-booking-view-details` (base: `dev`)

## The request, verbatim

Two independent items from
`Projects/golden-fur/shared/context/Architectural-Change-History.docx`:

> **Add new option to … in customer account > bookings page:**
>
> - Add View Details option
> - Should be able to see all details (e.g. branch, pet, date time, assigned
>   staff/cage, price, payments, etc.)
> - Currently only cancel is available (and reschedule if booking hasn't been
>   confirmed)

> **Fix unknown pet owner and unknown pet when viewing bookings as cashier**
> (backlog screenshot: the staff Booking Details page headed "Grooming
> booking" showing "Unknown pet · Owner Unknown owner")

Both changes touch only the booking _read_ path. No migration.

## Root cause / Context

### Part 1 — "View details" on My Bookings

The customer My Bookings page (`/portal/bookings`) only offered Reschedule /
Cancel in each row's `…` menu, and hid the menu entirely for Completed and
Cancelled bookings. There was no customer-facing way to see the price
breakdown, the assigned staff/cage, or the payment history of a booking.

The staff Booking Details page (`/staff/bookings/:id`) already showed most of
this, but built it from ~7 separate browser calls (`getBooking` + `getPet` +
`getCustomerProfile` + `listBranches` + `listServices` + `listPackages` +
`listDiscounts` + `listPromos`) and never resolved assigned staff or cage.

### Part 2 — "Unknown pet" / "Unknown owner" for a Cashier

`GET /pets/:id` and `GET /customers/:id` gate a non-owner read on
`PET_LOOKUP_ROLES` / `PROFILE_LOOKUP_ROLES`. Those lists include the customer
managers plus Groomer and Veterinarian, but **not Cashier**. A Cashier can
open `/staff/bookings/queue` (which branches explicitly on
`viewerRole !== 'Cashier'`) and a booking's details, and those pages resolve
each row's pet/owner name with the two single-record lookups above — which
all returned 403 for a Cashier, so the UI showed its literal `'Unknown pet'`
/ `'Unknown owner'` fallback strings.

## What changed

### Database

None. No migration in this change.

### Server

- **`booking/services/bookingDetails.service.ts`** (new) — `getBookingDetails({ requesterId, bookingId })`.
  Calls the existing `getBookingById` first, which does the owner-or-staff
  check and the lazy read-time transitions (down-payment expiry, no-show).
  Then, on the service-role client, it hydrates in parallel: branch
  (`name, address, contact_number`), pet (`name, weight_class, coat_type`),
  owner (`customer_profiles.full_name`), per-item service/package names,
  assigned staff (`staff_profiles.display_name`), preferred cage
  (`cages.cage_label` + `size`), the `booking_groups` row when
  `booking_group_id` is set, discount/promo names, a pricing rollup, and the
  `transactions` list. When the booking is part of a group, the discount /
  promo / down payment / total are read from the group row (a grouped booking
  carries 0/null for its own), and the transactions query widens to
  `booking_id = :id OR booking_group_id = :group`. `amount_paid` counts only
  `Fully Paid` + `Partially Paid` transactions; `balance_due = max(0, total −
amount_paid)`. `numeric` columns from PostgREST arrive as strings and are
  coerced before arithmetic. Same "resolve names on the service-role client
  after an auth gate" pattern as `catalog.service.ts`.
- **`booking/booking.controller.ts`** — `getBookingDetailsController`: 401 if
  no `req.user.sub`, else returns `{ details }`; errors go through
  `sendServiceError` (so a non-owner non-staff caller gets the 403 that
  `getBookingById` throws).
- **`booking/booking.routes.ts`** — `GET /bookings/:id/details`,
  `jwtMiddleware` only (same gate as `GET /bookings/:id`; ownership enforced
  inside the service).
- **`booking/booking.types.ts`** — `BookingDetails` and its sub-shapes
  (`HydratedBookingItem`, `BookingDetailsTransaction`, `BookingGroup`, the
  pricing rollup).
- **`customers/pets/pet.controller.ts`** — `'Cashier'` added to
  `PET_LOOKUP_ROLES` (single-record `GET /pets/:id` only).
- **`customers/customer.controller.ts`** — `'Cashier'` added to
  `PROFILE_LOOKUP_ROLES` (single-record `GET /customers/:id` only). Both are
  read-only widenings with the same precedent as Groomer/Veterinarian;
  Cashier still cannot list/create/update/delete customers or pets.

### Client

- **`booking/api/booking.api.ts`** — `getBookingDetails(bookingId, accessToken)`
  → `GET /bookings/:id/details`, returns `BookingApiResult<BookingDetails>`.
- **`booking/booking.types.ts`** — client mirror of `BookingDetails` +
  sub-shapes.
- **`booking/components/BookingDetailsView/`** (new) — pure presentational
  render of a `BookingDetails`: header (pet · owner + status/payment badges),
  Schedule (branch, scheduled window, assigned staff, cage, booked-on),
  Items, Hotel "Care instructions" (per-night tabs, read-only), Pricing
  (subtotal, discount/promo lines when non-zero, total, down payment, a
  "part of a bundled booking" note when grouped), Payments (per-transaction
  rows + Paid / Remaining balance), Status timeline (started / completed /
  paid / cancelled), Special instructions. Shared by the modal and the staff
  page.
- **`booking/components/BookingDetailsModal/`** (new) — wraps the shared
  `Modal`, titled "Booking details", fetches `getBookingDetails` when opened
  (`bookingId` non-null), shows a loading line then `<BookingDetailsView>` or
  an error banner.
- **`booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`** — "View
  details" is now the always-first `…` menu item (`setDetailsBookingId`), so
  the menu renders for every booking including Completed / Cancelled;
  `<BookingDetailsModal>` mounted once at page level.
- **`booking/pages/BookingDetailsPage/BookingDetailsPage.tsx`** — refactored
  from ~7 client fetches to a single `getBookingDetails` call rendered
  through `<BookingDetailsView>`; now also shows assigned staff + cage.
  `.module.css` trimmed to the classes still used (page / content /
  errorBanner / copy / secondaryButton).

### Adjustments from the pre-PR code review

The unbiased review
(`Projects/golden-fur/testing/reviews/feat/customer-booking-view-details/2026-09-07-2011-pre-pr.md`)
raised four user-facing findings, all fixed before commit:

- **Payments withheld from non-billing staff.** `getBookingById` admits any
  staff role, so the new endpoint would have shown payment references /
  methods / amounts to a Groomer/Veterinarian/Pet Assistant — data the
  staff-only `GET /billing/booking/:id/transactions` kept from them. The
  service now resolves the caller's role and returns an empty `transactions`
  list + `payments_visible: false` for any staff role outside
  `BILLING_STAFF_ROLES`; `BookingDetailsView` hides the whole Payments
  section (list + Paid/Remaining rollup) when `payments_visible` is false.
  The owning customer always sees their own payments.
- **Grouped-booking Pricing relabelled.** For a bundled booking the
  per-booking item subtotal never reconciled with the group total; the
  Pricing section now reads "This booking's services / Bundle discount /
  Bundle promo / Bundle total / Bundle down payment" with a leading
  explanatory line.
- **Error propagation.** `resolveTransactions` and `resolveGroup` now throw
  on a query error instead of returning `[]`/`null` (a swallowed error would
  have told a fully-paid customer they still owe the full total).
- **`downpayment_amount`** is now run through the same numeric coercion as
  every other money field (kept `null` when genuinely absent).

## Manual test — step by step

You need the dev API + web app running (`server`: `npm run dev`; `client`:
`npm run dev`, which serves `http://localhost:5173`) against the seeded dev
database. All seed accounts use the password **`password123`**.

### Scenario A — customer opens "View details" on My Bookings

1. Open a web browser and go to `http://localhost:5173/login`.
2. In **Email** type `customer1@goldenfur.com`, in **Password** type
   `password123`, click **Sign in**. You land on the customer portal home.
   If you see a red error banner, stop — the server or seed data is not
   ready.
3. In the left sidebar click **My Bookings**. The address bar now reads
   `http://localhost:5173/portal/bookings` and you see a list of this
   customer's bookings, each row showing a title like "Grooming - <pet>" and
   a branch + date line.
4. Find a row whose title starts with **Grooming**. On the right of that row
   click the **`…`** button (its tooltip is "Options for this Grooming
   booking"). A small menu opens. **"View details" is the first item.** If
   the menu has no "View details" item, the change did not take.
5. Click **View details**. A dialog titled **Booking details** opens on top
   of the page.
   - The top line shows the pet name, then `·` and the owner's name, with a
     status badge and a payment badge.
   - **Schedule** section: Branch, a "Scheduled" from–to time, **Assigned
     staff** (a real name such as "Makati Groomer 1", or "Not assigned"),
     **Cage** (a dash for Grooming), and "Booked on".
   - **Items** section: one line per booked service/package with its price.
   - **Pricing** section: Subtotal, a Discount and/or Promo line only if
     there was one, **Total**, and **Down payment** if the booking required
     one.
   - **Payments** section: one row per payment (e.g. "Down payment" +
     amount + date + method + status), then **Paid** and **Remaining
     balance**. For a Grooming booking with a down payment, Paid should equal
     only the settled down-payment amount, not the full price.
   - **Status timeline**: Started / Completed / Paid dates ("Not yet" where
     it hasn't happened).
     Close the dialog with its **×** (or the **Close** control).
6. Back on the list, find a row whose title starts with **Hotel**. Open its
   **`…`** menu → **View details**. In the dialog:
   - **Cage** in the Schedule section shows a real label such as
     "Makati-M-01 (M)" (or "Assigned at check-in" if none is preferred yet).
   - A **Care instructions** section appears with night tabs (Feeding /
     Walking / Playtime / Medications), marked read-only.
     Close the dialog.
7. Find a row whose status badge reads **Cancelled** (or **Completed**).
   Previously these rows had **no `…` button at all**. Confirm the **`…`**
   button is now present, open it, and confirm **View details** is there and
   opens the dialog. A Cancelled booking's dialog also shows a **Cancelled**
   line (with reason) in the Status timeline.
   - If this customer has no cancelled booking, either cancel a future
     Pending one first (Cancel in the same menu) or check this in Scenario B
     with a staff account instead.

### Scenario B — staff Booking Details shows assigned staff + cage

1. Open a new browser tab (or a private window) and go to
   `http://localhost:5173/staff/login`.
2. In **Username or email** type `makati.receptionist1`, in **Password** type
   `password123`, click **Sign in**. You land on the staff dashboard.
3. In the sidebar open **Receptionist → Bookings Queue** (address bar
   `http://localhost:5173/staff/bookings/queue`). You see a list of
   bookings, each with a **View details** button.
4. On a **Grooming** booking click **View details**. The address bar becomes
   `http://localhost:5173/staff/bookings/<id>` and the page shows a **Back to
   queue** link above the same detail layout as the customer dialog.
   - The **Schedule** section shows **Assigned staff** with a real name and,
     for a Hotel booking, **Cage** with a real label. Before this change the
     staff page never displayed either of those.
5. Click **Back to queue**, open a **Hotel** booking's **View details**, and
   confirm the **Cage** value and the **Care instructions** section render.

### Scenario C — a Cashier sees real pet/owner names, not "Unknown"

1. In the staff tab, sign out (top-right **Sign out**), then go to
   `http://localhost:5173/staff/login` again.
2. In **Username or email** type `makati.cashier1`, in **Password** type
   `password123`, click **Sign in**.
3. Open **Bookings Queue** from the sidebar
   (`http://localhost:5173/staff/bookings/queue`). Cashiers are allowed on
   this page (it renders a reduced view for the Cashier role).
4. Look at each booking row's second grey line. It should read
   **`{pet name} - Owner {owner name}`** with **real names**. Before this
   change a Cashier saw the literal text **"Unknown pet - Owner Unknown
   owner"** on every row.
5. Click **View details** on any booking. On the
   `http://localhost:5173/staff/bookings/<id>` page the header line shows the
   real **pet name · owner name** (not "Unknown pet · Owner Unknown owner"),
   and the Schedule / Items / Pricing / Payments sections all populate.
6. Failure looks like: the word "Unknown" anywhere in the pet/owner text, or
   a network tab showing `403` on `GET /pets/...` or `GET /customers/...`.

### API-level check

See `customer-booking-view-details.postman_collection.json` — it logs in as
`customer1`, calls `GET /bookings/:id/details` for the owning customer
(expects 200 + hydrated `branch` / `pet` / `assigned_staff` / `pricing` /
`transactions`), logs in as a second customer and expects `403` on the same
booking, and logs in as `makati.cashier1` and expects `200` on
`GET /pets/:id` and `GET /customers/:id`.

## Test suites

Run from each package directory on this branch:

- `server`: `npx vitest run` — **1004 passed (90 files)**. Includes the new
  `GET /bookings/:id/details` describe in
  `server/src/features/booking/tests/booking.integration.spec.ts` (401
  unauthenticated, 200 hydrated for the owner, 403 for a different
  non-staff customer, 200 + payments for a Cashier, 200 + payments withheld
  for a Groomer) and the new Cashier-GET-200 cases in
  `customer.integration.spec.ts` and `pets/tests/pet.integration.spec.ts`.
- `client`: `npx vitest run` — **784 passed (153 files)**. Includes new
  `BookingDetailsView.spec.ts` and `BookingDetailsModal.spec.ts`, and updated
  `BookingDetailsPage.spec.ts` + `CustomerBookingsPage.spec.ts` ("View
  details" offered on every booking incl. Cancelled, opens the modal).

Per this session's task hand-off: `npx tsc --noEmit` clean in both repos;
`npx eslint` clean for all changed files (server retains only pre-existing
no-console warnings elsewhere).

## Open items

None.

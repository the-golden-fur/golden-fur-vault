# Bookings Queue Read-Only + Sidebar Reorg

Type: Custom. Revision 1 was client-only; Revision 2 touched the server too (random
staff auto-assignment); Revision 3 (below) is client-only again (shared filter-bar
redesign + Hotel/Daycare picker rework). No DB migration in any revision.
Branch: `32-bookings-queue-readonly-and-sidebar-reorg` (suggested; based off `dev`).

## Scope

### 1. Bookings Queue is now read-only

`ReceptionistBookingsQueuePage` (`/staff/bookings/queue`) no longer has any status- or
payment-changing controls. It keeps only what's genuinely a receptionist's own job:
**View details**, **Reschedule**, **Cancel**, and the page-level **New booking** button.

Removed: the Start/Complete buttons, the Admin/Superadmin status-override dropdown, the
"Mark as Paid" button + advance/onsite modal, and the Admin/Superadmin payment-stage
override dropdown.

This wasn't just a UI simplification - every one of those actions was already duplicated
elsewhere, and having them in Bookings Queue too meant staff could bypass the real flow
(e.g. clicking "Start" on a Hotel booking directly in the queue skipped cage assignment
entirely, since Hotel Queue's check-in already advances the same underlying
`bookings.status` field via `startBooking`/`completeBooking` server-side):

- **Hotel/Daycare** ("Checkin and Checkout"): already handled by Hotel Queue / Daycare
  Queue's own Check In / Check Out tabs (`checkOutHotelStay` etc. already call
  `completeBooking` under the hood - confirmed in
  `server/src/features/hotel/services/checkout.service.ts`).
- **Grooming**: already handled by the Grooming Queue (`transitionGroomingStatus` also
  calls `startBooking`/`completeBooking` under the hood).
- **Veterinary** ("Vet actions... already implemented"): already handled by the
  Veterinary Console (`updateConsultation` also calls `startBooking`/`completeBooking`
  under the hood).
- **Misc** (Initial Assessment/Reassessment - see `PetDetailPanel.tsx`'s "needs an
  Initial Assessment visit" copy): the one category with **no** dedicated queue. Per your
  answer when I flagged this gap, its Start/Complete/status-override moved into the new
  Payments Queue below rather than being dropped.

### 2. New Payments Queue

New page: `PaymentsQueuePage` at `/staff/billing/payments-queue` (billing feature),
same look as Bookings Queue (branch/date/status/service-type filters, search/sort, one
row per booking with View details), holding:

- **Mark as Paid** (`advancePaymentStage`) + the advance/onsite modal - same behavior as
  the old Bookings Queue version, just relocated.
- **Payment status-override dropdown** (`overridePaymentStage`, Admin/Superadmin only) -
  same relocation.
- **Misc-category Start/Complete + status-override** - see above. Gated identically to
  how Bookings Queue used to gate them (`BOOKING_STATUS_OVERRIDE_ROLES` for the dropdown,
  "any role except Cashier" for Start/Complete), just additionally scoped to
  `service_category === 'Misc'` so Hotel/Daycare/Grooming/Veterinary rows never show them
  here either.

No new server endpoints - this page calls the exact same
`booking.api.ts` functions (`advancePaymentStage`, `overridePaymentStage`, `startBooking`,
`completeBooking`, `overrideBookingStatus`) the old Bookings Queue called, just from a
different page.

### 3. Sidebar / dashboard reorg (Admin & Superadmin grouped view only)

Every individual role's own dashboard (Receptionist, Groomer, Veterinarian, Cashier,
Pet Assistant, Supervisor) was already correctly scoped before this change - e.g.
Receptionist's own sidebar already had Bookings Queue, Hotel Queue, Daycare Queue, and
Customer Management. The actual mismatch was in the **Admin/Superadmin dashboard's
section grouping** (`staffDashboard.config.ts`'s `admin` entry), which groups shared
tiles by "which lower-privilege role does this really belong to" - and several tiles
were grouped under the wrong section relative to what that same tile's own
`ALLOWED_VIEWER_ROLES` / that role's own dashboard says. Fixed by moving them into the
section that actually matches:

| Tile                    | Was under    | Now under                       |
| ----------------------- | ------------ | ------------------------------- |
| Bookings Queue          | Management   | **Receptionist**                |
| Customer Management     | Management   | **Receptionist**                |
| Days Off Approval Queue | Management   | **Supervisor**                  |
| Monthly Schedule        | Management   | **Supervisor**                  |
| Hotel Queue             | Receptionist | **Groomer** + **Pet Assistant** |
| Daycare Queue           | Receptionist | **Groomer** + **Pet Assistant** |
| Payments Queue (new)    | -            | **Cashier**                     |

Admin's "Management" section is now just Days Off, Staff Management, Archive - the
tiles that don't map to any single lower-privilege role. The Cashier role's own
dashboard also swaps its old "Bookings Queue" tile for "Payments Queue", since marking
a booking paid was the only reason Cashier had a Bookings Queue tile in the first place.

**Not changed**: Receptionist's own dashboard still has Hotel Queue/Daycare Queue (that
role is the primary intended user per those pages' own `ALLOWED_VIEWER_ROLES` - it's
first in the list); Supervisor's own dashboard still has Bookings Queue, Days Off
Approval Queue, and Monthly Schedule (unaffected, they were already correct there). This
reorg only touches how Admin/Superadmin's grouped view labels the same shared tiles.

## Files changed

**New**: `client/src/features/billing/pages/PaymentsQueuePage/{PaymentsQueuePage.tsx,PaymentsQueuePage.module.css,PaymentsQueuePage.spec.ts}`.

**Edited**:

- `client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx` - stripped Start/Complete/status-override/payment actions.
- `client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.spec.ts` - removed the now-relocated Start/Complete/Mark-as-Paid tests, added one read-only assertion.
- `client/src/features/billing/billing.routes.tsx` - new `/staff/billing/payments-queue` route.
- `client/src/features/staff/config/staffDashboard.config.ts` - admin section regrouping (table above), Cashier tile swap, new `Payments Queue` tile + icon.

## New API surface

None. Every action `PaymentsQueuePage` calls already existed
(`POST /bookings/:id/payment-stage/advance`, `PATCH /bookings/:id/payment-stage`,
`POST /bookings/:id/start`, `POST /bookings/:id/complete`, `PATCH /bookings/:id/status`) -
same role gates as before (`server/src/features/booking/booking.routes.ts`,
unchanged). No migration needed.

## Automated Verification

From `client/`:

```powershell
npx tsc -b
npx vitest run
npx eslint .
```

Expected: typecheck clean, **545/545 tests pass** (118 files), lint clean. Confirmed as
of this writing. `npx vite build` also confirmed clean (pre-existing >500kB chunk-size
warning, unrelated to this batch).

No server changes in this batch - server's own test suite is unaffected.

## Manual Verification

You'll need the `server/` and `client/` dev servers running (`npm run dev` from the repo
root) and staff logins across a few roles - at minimum Receptionist, Cashier, Groomer,
and one of Admin/Superadmin. No migrations to apply.

### 1. Bookings Queue is read-only

1. Log in as Receptionist (or any non-Cashier role) and open **Bookings Queue**
   (`/staff/bookings/queue`). Confirm each row shows: service category, branch/time, pet/
   owner, status badge, payment badge, **View details** button, and - only for a Pending
   row - **Reschedule** / **Cancel**. Confirm there is **no** Start, Complete, status
   dropdown, "Mark as Paid", or payment dropdown anywhere on the page, on any row,
   regardless of that row's status or service category (check at least one Hotel, one
   Daycare, one Grooming, one Veterinary, and one Misc booking if your seed data has
   them).
2. Log in as Admin or Superadmin and repeat - confirm the status-override dropdown is
   also gone (Admin/Superadmin previously saw a dropdown here instead of Start/Complete).
3. Confirm **View details** still navigates to `/staff/bookings/:id`, and Reschedule/
   Cancel still work exactly as before (unchanged logic, just untouched by this batch).

### 2. Payments Queue

1. As Cashier, open **Payments Queue** from the sidebar (should now replace the old
   "Bookings Queue" entry on Cashier's dashboard). Confirm the same filter bar shape as
   Bookings Queue (date range, status, service type, search/sort; branch filter only for
   Superadmin).
2. Find (or create, via a walk-in booking) a **Completed, Unpaid** booking. Confirm
   **Mark as Paid** appears. Click it - confirm the "Normal onsite payment" / "Advance
   payment" modal shows, and picking either advances `payment_stage` and the row's
   payment badge updates in place.
3. Find/create a **Paid in Advance** booking. Confirm clicking Mark as Paid advances
   straight to Paid with **no modal**.
4. Confirm a fully **Paid** booking shows no payment controls at all.
5. Log in as Admin/Superadmin instead of Cashier. Confirm you see a **Payment** status
   dropdown in place of Mark as Paid, and that changing it updates the row immediately.
6. Create or find a **Misc**-category booking (Initial Assessment/Reassessment - book
   one via the booking flow if none exist). Confirm **Start**/**Complete** appear for it
   here (Pending -> Start -> In Progress -> Complete -> Completed), and that a
   non-Misc row (Hotel/Daycare/Grooming/Veterinary) never shows Start/Complete on this
   page, even for the same viewer role.
7. Confirm **View details** works the same as on Bookings Queue.

### 3. Sidebar / dashboard reorg

1. Log in as **Receptionist**. Confirm the sidebar is unchanged from before: Days Off,
   Customer Management, Bookings Queue, Hotel Queue, Daycare Queue.
2. Log in as **Groomer**. Confirm the sidebar has Days Off, Grooming Queue, Hotel Queue,
   Daycare Queue (Hotel/Daycare Queue should already have been there - unchanged).
3. Log in as **Pet Assistant**. Confirm Days Off, Care Log, Hotel Queue, Daycare Queue
   (also unchanged).
4. Log in as **Cashier**. Confirm the sidebar/dashboard now shows **Payments Queue**
   instead of Bookings Queue, alongside Checkout & Billing and Credit Management.
5. Log in as **Admin** or **Superadmin**. Confirm the sidebar's sectioned groups now
   read:
   - **Management**: Days Off, Staff Management, Archive.
   - **Receptionist**: Customer Management, Bookings Queue.
   - **Groomer**: Grooming Queue, Hotel Queue, Daycare Queue.
   - **Veterinarian**: Consultation Queue.
   - **Cashier**: Checkout & Billing, Payments Queue, Credit Management.
   - **Pet Assistant**: Hotel Care Log, Hotel Queue, Daycare Queue.
   - **Supervisor**: Days Off Approval Queue, Monthly Schedule, Branch Reports, Cage
     Occupancy, Transaction History.
6. Click a few of the moved tiles (Bookings Queue under Receptionist, Payments Queue
   under Cashier, Hotel Queue under both Groomer and Pet Assistant, Days Off Approval
   Queue / Monthly Schedule under Supervisor) and confirm each still navigates to the
   correct, already-existing page.
7. Log in as **Supervisor**. Confirm their own (non-admin) dashboard is unchanged: Days
   Off, Customer Management, Days Off Approval Queue, Monthly Schedule, Bookings Queue,
   Hotel Care Log, Branch Reports, Cage Occupancy, Transaction History.

## Revision 2 (same branch, live-review follow-up)

After reviewing Revision 1 live, five more fixes came out of that pass - one direct
correction, four bounded low-risk fixes. A larger, more subjective redesign (icon/chip/
animation filter-bar overhaul; Hotel/Daycare picker inline-button + "..." menu rework)
was deliberately scoped out of this revision and deferred to a later pass.

1. **Correction: Receptionist loses Hotel Queue/Daycare Queue access entirely.**
   Revision 1 kept Receptionist in both pages' `ALLOWED_VIEWER_ROLES` (it was already
   there beforehand) - live review corrected this: Hotel Queue/Daycare Queue are
   Groomer + Pet Assistant only now. Removed from `HotelQueuePage.tsx`/
   `DaycareQueuePage.tsx`'s `ALLOWED_VIEWER_ROLES` and from Receptionist's own
   dashboard tiles in `staffDashboard.config.ts`. Deliberately left server-side
   `HOTEL_ADVANCE_ROLES`/`DAYCARE_ADVANCE_ROLES` untouched (page-access change, not a
   full permissions revocation - matches how every other queue page's client gate
   already works here, e.g. Grooming Queue's own gate is stricter than the server's
   broader booking-status role gate).
2. **"No preference" staff assignment is now random, not always the same person.**
   Turned out auto-assignment already existed (`resolveStaffAssignment` in
   `booking.service.ts` already called `autoAssignStaff` for a no-preference Grooming/
   Veterinary booking) - the actual bug was that it always picked the RPC's
   `display_name`-ordered first eligible staff member, so the same person got every
   no-preference booking. New `pickRandomAvailableStaff` in `staffPicker.service.ts`
   (uniform random index) replaces that ordered pick, used by both `autoAssignStaff`
   and reschedule.service.ts's own equivalent fallback (its "keep the currently
   assigned staff if still eligible" behavior is untouched - only the fallback when
   they're not eligible anymore is now random too).
3. **Removed the "Assigned" filter** (All/Assigned to me/Unassigned) from Bookings
   Queue - the only page that had it. No longer needed now that "no preference" always
   assigns someone rather than leaving Grooming/Veterinary bookings unassigned.
4. **Queue row layout fixed** on Bookings Queue and Payments Queue - both pages'
   `.bookingMain` was one flex-wrap row treating the title, two meta lines, two status
   badges, and the View details button as equal siblings, producing cramped/uneven
   wrapping and a large visual gap before the action row. Restructured into title+badges
   on one line, branch/time on its own line, pet/owner on its own line, and View details
   folded into the same controls row as every other action button (previously
   stranded up in the info block, "miles away" from Mark as Paid on Payments Queue).
5. **Default HTML form controls now themed.** New `client/src/styles/base/forms.css`
   (imported from `global.css`) sets `accent-color` on every checkbox/radio to the
   app's gold accent plus a shared focus-visible outline, and a sensible bordered/
   token-colored fallback for any other bare `input`/`select`/`textarea` - fixes 8
   previously-unstyled checkboxes across the app (e.g. Hotel Check-in's "Owner opted
   in..." toggle) without touching any of those 8 files, since a bare-tag global rule
   never outranks a page's own CSS Module class.

### Files changed (Revision 2)

**Server**: `features/booking/services/staffPicker.service.ts` (`pickRandomAvailableStaff`,
`autoAssignStaff`), `features/booking/services/reschedule.service.ts` (random fallback
pick), `features/booking/services/staffPicker.service.spec.ts` (updated for randomness).

**Client**: `features/hotel/pages/HotelQueuePage/HotelQueuePage.tsx`,
`features/daycare/pages/DaycareQueuePage/DaycareQueuePage.tsx` (both
`ALLOWED_VIEWER_ROLES`), `features/staff/config/staffDashboard.config.ts` (receptionist
tiles), `features/booking/pages/ReceptionistBookingsQueuePage/{ReceptionistBookingsQueuePage.tsx,.module.css}`,
`features/billing/pages/PaymentsQueuePage/{PaymentsQueuePage.tsx,.module.css}`, new
`styles/base/forms.css` + `styles/global.css` (import).

### Automated Verification (Revision 2)

From `client/`:

```powershell
npx tsc -b
npx vitest run
npx eslint .
```

Expect clean typecheck/lint, **545/545 tests pass** (118 files). `npx vite build` also
confirmed clean.

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run
npx eslint .
```

Expect clean typecheck, **752/752 tests pass** (77 files), lint clean (only pre-existing
`no-console` warnings, none in files this revision touched).

### Manual Verification (Revision 2)

1. Log in as **Receptionist** - confirm Hotel Queue and Daycare Queue are gone from the
   sidebar/dashboard, and visiting `/staff/hotel/queue` or `/staff/daycare/queue`
   directly redirects to Settings.
2. Log in as **Groomer** and **Pet Assistant** - confirm both queues are still there and
   still work exactly as before.
3. Book several Grooming or Veterinary "No preference" appointments for the same slot/
   branch (with 2+ eligible staff) - confirm the assignment isn't always the same staff
   member across multiple bookings. Same check via Reschedule on an existing booking
   whose current staff is no longer available for the new slot.
4. Open Bookings Queue - confirm there's no "Assigned" filter anymore (Date/Status/
   Service type/Branch only).
5. Open Bookings Queue and Payments Queue - confirm each row shows title+badges, branch/
   time, and pet/owner each on their own line, and every button (View details plus
   whatever else that row has) sits together in one row directly under that info, not
   separated by a large gap.
6. Open any page with a checkbox (e.g. Hotel Check-in's "Owner opted in to pet status
   notifications" toggle, or the Policy Configuration page) in both light and dark mode -
   confirm it renders with the app's gold accent color instead of a bare
   browser-default checkbox.

## Revision 3 (same branch, Stage B - filter-bar redesign + picker rework)

Client-only. The two pieces deferred out of Revision 2's scope for review:

### 1. Filter/sort UI redesign (icons, transitions, active-filter chips)

`QueueFilterBar` and `SearchSortBar` (the shared toolbar components used by every
"queue" page in the app) now show a small leading icon next to each field's label
(Calendar for Date, Filter for Status, a magnifying glass inside the search input, an
up/down arrow inside the sort select), plus hover/focus-visible transitions on every
control.

New shared `ActiveFilterChips` component renders a Notion-style row of removable pills,
one per **non-default** filter/search/sort value currently active, directly under
the toolbar. Clicking a chip's × resets just that one filter. Each page computes its
own chip list from state it already owns (the shared components stay unaware of what
counts as "default" for a given page), so this rolled out to all 10 pages that use
either shared component: Bookings Queue, Payments Queue, Grooming Queue, Veterinary
Console, Hotel Booking Picker (check-in), Daycare Booking Picker (check-in), Hotel Stay
Picker (checkout), Daycare Session Picker (checkout), the Days Off Approval Queue, and
the shared Catalog Admin page (Services/Packages/etc.).

New `dateRangePresetLabel()` helper (`QueueFilterBar/dateRangePreset.ts`) so a chip's
text always matches the date select's own option label instead of duplicating the
lookup per page.

### 2. Hotel/Daycare picker rework: inline buttons + "..." menu

Per your call on how far this should go: each picker card gets an explicit action
button instead of the whole card being the click target, but the underlying flow is
unchanged (the button calls the exact same `onSelect` the card's click used to call;
Check In still shows the same below-the-list multi-step form, Check Out still shows the
same replaces-the-list confirm/breakdown panel).

- **Check-in pickers** (`HotelBookingPicker`, `DaycareBookingPicker`): each card now has
  a **Check in** button (only shown for checkinable/Pending bookings - unchanged
  eligibility rule) instead of being a clickable `role="button"` div.
- **Checkout pickers** (`HotelStayPicker`, `DaycareSessionPicker`): each card now has a
  **Check out** button instead of being a clickable `<button>` wrapping the whole card.
- Every card also gets a new **"..." (more options)** menu in its header - new shared
  `MoreOptionsMenu` component (kebab icon, opens a small dropdown, closes on outside
  click/Escape, stops its own click from bubbling to anything around it) - currently
  holding one item, **"View booking details"**, which navigates to
  `/staff/bookings/:id` (omitted on Hotel/Daycare's walk-in-only entries that have no
  underlying booking to view, i.e. `booking_id === null`).
- Hotel's pre-existing "Go to checkout →" link on an already-checked-in card is
  unchanged (still there, still works) - just no longer needs its own `stopPropagation`
  now that the card itself has no click handler to stop.

### Files changed (Revision 3)

**New**: `shared/components/ActiveFilterChips/*`, `shared/components/MoreOptionsMenu/*`.

**Edited**: `shared/components/QueueFilterBar/{QueueFilterBar.tsx,QueueFilterBar.module.css,dateRangePreset.ts}`,
`shared/components/SearchSortBar/{SearchSortBar.tsx,SearchSortBar.module.css}`; chip
wiring in `features/booking/pages/ReceptionistBookingsQueuePage/*`,
`features/billing/pages/PaymentsQueuePage/*`,
`features/grooming/pages/GroomerDashboardPage/GroomerDashboardPage.tsx`,
`features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx`,
`features/staff/pages/UnavailabilityApprovalQueuePage/UnavailabilityApprovalQueuePage.tsx`,
`features/catalog/components/CatalogAdminPage/CatalogAdminPage.tsx`; chip wiring +
button/menu rework in `features/hotel/components/{HotelBookingPicker,HotelStayPicker}/*`,
`features/daycare/components/{DaycareBookingPicker,DaycareSessionPicker}/*`.

### Automated Verification (Revision 3)

From `client/`:

```powershell
npx tsc -b
npx vitest run
npx eslint .
npx vite build
```

Expect clean typecheck/lint, **552/552 tests pass** (120 files), clean build. Confirmed
as of this writing (updated `HotelBookingPicker.spec.ts`'s and `HotelStayPicker.spec.ts`'s
card-click assertions to click the new explicit Check in/Check out buttons instead, and
wrapped `HotelStayPicker`'s test render in a `MemoryRouter` now that it calls
`useNavigate`).

No server changes in this revision.

### Manual Verification (Revision 3)

1. Open any queue page (Bookings Queue is a good one) - confirm the Date and Status
   filter labels each show a small icon, and the search box / sort dropdown each show a
   leading icon too. Hover and focus each control - confirm a smooth transition (border
   color / lift), not an instant snap.
2. On Bookings Queue, change the Date preset away from "Today", set a Status filter,
   type something in Search, and change the Sort order. Confirm a row of chips appears
   below the toolbar - one per change - each reading something like "Date: This week" /
   "Status: Pending" / `Search: "buddy"` / the sort option's own label. Confirm changing
   a filter back to its default removes that filter's chip, and clicking a chip's × also
   resets just that one filter (not the others).
3. Repeat step 2's chip check on Payments Queue (also has Service type/Branch chips for
   Superadmin), Grooming Queue, Veterinary Console, and the Days Off Approval Queue
   (search/sort/branch chips only, no date/status there).
4. Open Hotel Queue's Check In tab. Confirm each booking card now shows an explicit
   **Check in** button (for Pending bookings) instead of relying on clicking anywhere on
   the card, and a **"..."** button in the card's top-right. Click "...", confirm a small
   menu opens with **View booking details**, and clicking it navigates to that booking's
   details page. Confirm clicking outside the open menu, or pressing Escape, closes it.
   Confirm clicking "..." does NOT also trigger Check In.
5. Click **Check in** on a card - confirm the same multi-step check-in form (cage
   assignment, feeding, walking, medications) appears below the list, exactly as before.
6. Repeat steps 4-5 on Daycare Queue's Check In tab.
7. Switch to Hotel Queue's Check Out tab (or check a pet in first to land there). Confirm
   each active-stay card shows an explicit **Check out** button and a "..." menu with
   "View booking details". Click **Check out** - confirm the same confirm/breakdown
   panel appears as before (downpayment, extension fee, remaining balance).
8. Repeat step 7 on Daycare Queue's Check Out tab.
9. On a Hotel booking card that's already checked in, confirm the existing "Go to
   checkout →" link still works and still navigates straight to that stay's checkout,
   unaffected by the "..." menu addition next to it.

---
title: Fix the vet staff Forbidden error, fold Bookings Queue into Consultation Queue, and a batch of small UI fixes
date: 2026-09-22
tags: [session-plan, golden-fur]
project: golden-fur
session: 113-vet-consultation-queue-and-ui-polish
branch: not yet created - staged on dev
---

# 113 — Fix the vet staff Forbidden error, fold Bookings Queue into Consultation Queue, and a batch of small UI fixes

## What you asked for

Seven small-to-medium changes bundled from one context doc, most centered on the Veterinarian staff role:

> As a developer, I want the Forbidden error hidden when making a new booking for a patient as a vet staff
>
> As a developer, I want to have a … button for each row in admin settings > config > pets > breeds
>
> As a vet staff, I don't want access to the bookings queue, I want it to be integrated into my consultation queue. Where I can schedule a new consultation for my patients. Clicking on New Consultation builder opens up a filtered booking builder (e.g. filter my customers, no service step auto vet service type, etc.)
>
> As a developer, I want customer made vet service online bookings to not be auto confirmed, it should still be unconfirmed like all other service types
>
> As a cashier, I still want to be able to view the transactions of confirmed bookings (even from the auto confirmed vet service booking) at my transactions page
>
> As a developer, I want to change how tap on mobile opens up the board/gallery view > … options, into hold (from tap → hold)
>
> As a frontend designer, I want the shared search, sort, filter, group by and view options to be applied in the consultation queue page

## What this part of the app does today

A few pieces of vocabulary and screens this plan touches:

- **Golden Fur Staff app** — the internal (non-customer) side of the site, at URLs under `/staff/...`. Different staff accounts have different **roles** (Veterinarian, Receptionist, Cashier, Admin, etc.) and see a different sidebar/dashboard depending on their role.
- **The booking builder** — the multi-step "Book a service" wizard. The exact same component (`CustomerBookingFlowPage`) is reused in two places: `/portal/book` (a customer booking for themselves) and `/staff/bookings/new` (a staff member booking on a customer's behalf, called "receptionist mode" in the code even though Veterinarians and Admins use it too). Its steps, in order, are: Branch → Customer → Pet → **Service Type** → Services → Booking Type → Date & Time → Your bookings → Promos & Coupons → Review. Some steps are skipped for some roles already — e.g. a Receptionist/Admin/Veterinarian never sees the Branch step, because their account is already tied to one branch.
- **Consultation Queue** (`/staff/veterinary/console`) — a Veterinarian's worklist of today's appointments needing a consultation (the medical visit itself: exam notes, medications, procedures).
- **Bookings Queue** (`/staff/bookings/queue`) — a Receptionist-oriented worklist of the day's appointments across every service category, with check-in/cancel actions and a "New booking" button.
- **My Patients** (`/staff/veterinary/my-patients`) — a Veterinarian-only page listing pets they've personally treated, with a reference to the pet's owner (the customer).
- **Settings > Config > Breeds** (Breed Management) — an admin page for managing the list of pet breeds (e.g. "American Shorthair", "Cat").
- **A booking's confirmation state** — shown as a colored badge (Unconfirmed / Confirmed / etc.) on booking lists. It's not a stored value; it's computed on the fly from a few real database columns (`status`, `payment_status`, `booking_source`, `service_category`).
- **Table / List / Board views** — most admin config pages (Discounts, Pet Types, the Rewards spin-wheel's Reward Pool, Transactions, etc.) let you switch between three layouts for the same list of rows: a spreadsheet-style Table, a card-style List, and a Kanban-style Board (grouped into columns). A shared toolbar above the list offers search, sort, filter, and (for Board) "group by".
- **The "..." (kebab) menu** — a small button that opens a dropdown of row actions (Rename, Delete, etc.), used instead of several separate buttons cluttering a row.

## What's wrong / what's missing

1. **Forbidden error.** When a Veterinarian opens the booking builder to book a patient (`/staff/bookings/new`), the Customer step shows a red "Forbidden" error banner instead of a clean list. Under the hood, the app already has logic to restrict a vet to only the customers they've actually treated, but that logic tries to fetch it in a way the server outright refuses for a Veterinarian, so the raw error leaks through before the restriction ever kicks in.
2. **No "..." button on Breeds rows.** Every other similar admin table (Pet Types, Discounts) already shows a single "..." button per row with a dropdown of actions. Breed Management still shows two separate "Rename" / "Delete" buttons side-by-side, which looks inconsistent.
3. **Vet staff shouldn't have a separate Bookings Queue.** A Veterinarian currently sees both "Consultation Queue" and "Bookings Queue" in their sidebar. The ask is to remove "Bookings Queue" for that role and instead let them start a new booking (an initial visit or follow-up) directly from Consultation Queue, via a "New Consultation" button that opens the booking builder already narrowed to their own patients and their own service type.
4. **Vet bookings are mislabeled "Confirmed".** An online (customer-made, self-service, unpaid) vet appointment currently displays as "Confirmed" the moment it's created, while the exact same situation for Grooming/Hotel/Daycare correctly displays as "Unconfirmed" until it's paid. This is inconsistent and misleading — staff can't tell which unpaid vet bookings are actually secured.
5. **Cashier's Transactions page — verify, not fix.** The ask is to make sure fixing #4 doesn't accidentally hide vet-related transactions from the cashier. Investigation shows the Transactions page never filtered on this "Confirmed" label in the first place, so this is a check to run after #4 lands, not a separate code change.
6. **Tap opens the "..." menu on mobile Board/List cards — should be hold instead.** Several admin pages (Discounts, Pet Types, Promos, Services, etc.) show a persistent "..." button on every card in their List/Board views. A single tap opens it — which is fine on desktop but, on a crowded mobile card grid, is easy to trigger by accident. Three other pages (Cages, Staff Management, Customer Management) already solved this by removing the visible button entirely and requiring a press-and-hold (or right-click, on desktop) instead — the rest haven't been brought in line yet.
7. **Consultation Queue's toolbar is a one-off, not the shared one.** Every other similar list page (Transactions, Reward Pool, Breeds, Discounts, etc.) shares one search/sort/filter/group-by/view-switcher toolbar component. Consultation Queue instead has its own older, more limited toolbar (a date-range dropdown, a status dropdown, and a search box) with no filter builder, no group-by, and no Table/List/Board switcher.

## What we're going to change

1. **Fix the Forbidden error by not calling the "list all customers" endpoint for a Veterinarian.**
   - _Where the bug actually is:_ `client/src/features/booking/components/CustomerPicker/CustomerPicker.tsx` — its `load()` function (around line 64) always calls `listCustomers(accessToken)`, which hits `GET /customers`. That endpoint's server-side check, `server/src/features/customers/customer.controller.ts` (`CUSTOMER_LIST_ROLES`, lines 92-95), deliberately excludes the Veterinarian role — a vet is only supposed to look up patients they've treated, not browse every customer. `CustomerPicker` already accepts a `restrictToCustomerIds` prop (used from `CustomerBookingFlowPage.tsx` around lines 542-569, fed by `listMyPatients`) that's *meant* to narrow the list down to a vet's own patients — but that filtering happens client-side, after the doomed fetch already 403'd and put "Forbidden" in the error banner.
   - _The fix:_ when `CustomerPicker` is given a `restrictToCustomerIds` set (i.e. it's being used by a Veterinarian), it should stop calling the broad `listCustomers`/`GET /customers` endpoint altogether, and instead fetch just those specific customers by id — reusing `getCustomerProfile` (`client/src/features/customers/api/customer.api.ts`, `GET /customers/:id`), which Veterinarians are already allowed to call (`PROFILE_LOOKUP_ROLES` in `customer.controller.ts`, lines 67-72). Fetch each id in `restrictToCustomerIds` (e.g. via `Promise.all`) instead of the one list call.
   - _Why this approach over the alternatives:_ loosening the server's list-endpoint role check would let a Veterinarian browse the full customer list again, which is exactly what the existing restriction was built to prevent. Adding a brand-new server endpoint is possible but unnecessary — the single-customer endpoint a vet is already allowed to call is enough.

2. **Give Breed Management a "..." row menu, matching Pet Types.**
   - _Files:_ `client/src/features/maintenance/pages/AdminBreedsPage/AdminBreedsPage.tsx` — `renderBreedActions()` (lines 351-395) currently renders two separate `<button>`s. Replace them with the shared `MoreOptionsMenu` component (`client/src/shared/components/MoreOptionsMenu/MoreOptionsMenu.tsx`), passing `items: [{label: 'Rename', ...}, {label: 'Delete', ...}]`.
   - _Why this shape:_ `client/src/features/maintenance/pages/AdminPetTypesPage/AdminPetTypesPage.tsx` (`renderPetTypeActions`, lines 450-469) already does exactly this for its own rows — copy that pattern so Breeds looks and behaves the same way in Table, List, and Board view (all three currently call the same `renderBreedActions`).

3. **Fold Bookings Queue into Consultation Queue for Veterinarians.**
   - _Remove the sidebar link:_ `client/src/features/staff/config/staffDashboard.config.ts` — delete the "Bookings Queue" tile (lines 483-488) from the `veterinarian` section only. No other role's config is touched, so Receptionist/Admin/Cashier keep their own Bookings Queue access untouched.
   - _Block direct navigation too:_ `client/src/features/booking/pages/ReceptionistBookingsQueuePage/ReceptionistBookingsQueuePage.tsx` currently has no role allow-list of its own, so a Veterinarian could still reach it by typing the URL. Add a viewer-role check that redirects a Veterinarian away, the same way `client/src/features/veterinary/pages/MyPatientsPage/MyPatientsPage.tsx` (`ALLOWED_VIEWER_ROLES`, line 43) already gates its own page.
   - _Add "New Consultation" to Consultation Queue:_ in `client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx`, add a button (next to the page header, same spot `ReceptionistBookingsQueuePage.tsx` puts its own "New booking" button, lines 805-816) that navigates to `/staff/bookings/new`, passing along that this is a vet-initiated booking (e.g. React Router's `navigate(path, { state: { lockedServiceCategory: 'Veterinary' } })`).
   - _Make the booking builder honor that:_ in `CustomerBookingFlowPage.tsx`, read that navigation state (the component already imports `useLocation`, line 487) and, when a locked category is present: (a) pre-set the `category` state (line 610) to `'Veterinary'` instead of leaving it blank, and (b) skip the "Service Type" step entirely — the `steps` array (built around lines 1835-1888) already has precedent for conditionally omitting a step (see `isBranchLockedStaff` skipping the Branch step at line 1841); add the same kind of condition around `list.push({ key: 'category', ... })`. Once item 1 above is fixed, the existing `treatedCustomerIds`/`restrictToCustomerIds` wiring already narrows the Customer step to the vet's own patients — no extra work needed there.

4. **Stop labeling unpaid online vet bookings "Confirmed".**
   - _Client display:_ `client/src/features/booking/bookingConfirmation.ts`, `deriveBookingConfirmationState()` (lines 33-57). Line 52 currently reads `booking.service_category !== 'Veterinary' &&` as part of deciding whether a booking is "awaiting payment" (→ Unconfirmed). Remove that clause so an unpaid, online, Pending vet booking is treated exactly like an unpaid Grooming/Hotel/Daycare one. Update the explanatory comment above (lines 23-26), which currently documents Veterinary as an intentional exception.
   - _Server notification timing:_ `server/src/features/booking/services/booking.service.ts`, `isConfirmedAtCreation` (lines 1260-1261) currently reads `bookingSource === 'Walk-in' || input.service_category === 'Veterinary'` — this is what fires the "your booking is confirmed" notification immediately, which would contradict the display now saying "Unconfirmed". Drop the `|| input.service_category === 'Veterinary'` half so only Walk-in bookings (which are always staff-created and already paid/settled on the spot) get the immediate notification.
   - _What NOT to change (flagging this explicitly, since it's a judgment call):_ two other Veterinary special-cases in the same file — `requiresUpfrontCharge` (line 1035, no downpayment is charged for vet visits) and the check-in payment gate in `startBooking()` (around lines 1899-1902, vet bookings can be checked in without a payment already recorded) — should stay as-is. Those implement the actual business rule "a vet visit is priced during the visit, not upfront," which is separate from whether the booking's status badge is allowed to say "Confirmed" before anyone has paid anything. Confirm this reading with whoever wrote the ticket before implementing, in case they intended a bigger change.

5. **Transactions page — verification only, no code change expected.** `client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx` and its server query (`server/src/features/reports/services/transactionHistory.service.ts`, lines 25-109) never filtered on the confirmation-state label from item 4, or on `service_category` in a way that would exclude Veterinary — a Cashier can already query any `service_category` including Veterinary. After item 4 ships, manually re-check (see `testing/testing.md`, to be filled in at implementation time) that a paid vet booking's transaction still shows up normally on this page.

6. **Change tap-to-open into press-and-hold for the remaining Board/List "..." menus.**
   - _The pattern to copy already exists:_ `client/src/shared/components/MoreOptionsMenu/CardContextMenu.tsx` wraps a card with no visible button at all; right-click opens the menu on desktop, and a 500ms press-and-hold (without dragging more than 10px) opens it on touch — a plain tap passes through untouched. It's already used by `AdminCagesPage.tsx`, `StaffManagementPage.tsx`, and `CustomerManagementPage.tsx`.
   - _Where it's still missing:_ every other page whose Board/List card rendering shows a visible `MoreOptionsMenu` button directly (a tap-to-open trigger) needs to switch to wrapping its card in `CardContextMenu` instead, for the List and Board views only — Table view's per-row "..." column button is a normal, explicit control and should stay tap-to-open as-is. This is the same one-line change repeated per page, so rather than listing every file: apply it to each admin config page's `render*Card` function (Breed Management from item 2, `AdminDiscountManagementPage.tsx`, `AdminPetTypesPage.tsx`, `AdminPromoConfigPage.tsx`, `AdminServicesPage.tsx`, `AdminServiceTypesPage.tsx`, `AdminPackageBuilderPage.tsx`, plus the hotel/vet/customer card renderers found during exploration — `HotelBookingPicker.tsx`, `HotelStayPicker.tsx`, `VetCatalogPage.tsx`, `CustomerBookingsPage.tsx`, `MyPatientsPage.tsx`) — swap the visible `MoreOptionsMenu` for a `CardContextMenu` wrapper only when the page's current view is List or Board.

7. **Bring Consultation Queue onto the shared search/sort/filter/group-by/view toolbar.**
   - _File:_ `client/src/features/veterinary/pages/VeterinaryConsolePage/VeterinaryConsolePage.tsx`. It currently renders its own older `QueueFilterBar` + `SearchSortBar` (around lines 432-450) above a plain `<ul>` of rows (from line 470) — there's no filter builder, no group-by, and no Table/List/Board switcher.
   - _Swap in:_ `client/src/shared/components/FilterSortBar/FilterSortBar.tsx` (search box, filter builder, sort, and a slot for `ViewSwitcher`) paired with `ViewSwitcher.tsx`, `DataTable.tsx`, `DataList.tsx`, `DataBoard.tsx`, and the `useGroupBy` hook — the same set `AdminSpinWheelConfigPage.tsx` (Reward Pool) and `TransactionHistoryTable.tsx` already use. The existing Date-range preset and Status dropdown become `filterFields` entries in `FilterSortBar` instead of their own bespoke controls; the existing per-row "View Details" action (already built as a `MoreOptionsMenuItem[]`, around line 474) carries over into `DataTable`'s row-actions column for Table view, and into a `CardContextMenu`-wrapped card for List/Board view (tying this together with item 6, since Consultation Queue's List/Board would be new card-based views subject to the same tap→hold rule).

## Words you might not know

- **RBAC (role-based access control)** — the app deciding what a user can see or do based on their role (Veterinarian, Cashier, etc.), enforced both in the UI (hiding a button) and on the server (rejecting the request even if the UI didn't hide it).
- **403 Forbidden** — an HTTP error code a server sends back meaning "I understood your request, but you're not allowed to do that." Different from 401 ("I don't know who you are").
- **Endpoint** — a specific URL + HTTP method the server responds to, e.g. `GET /customers`.
- **Component** — a reusable piece of UI in React, the library this app's frontend is built with. `MoreOptionsMenu` and `CardContextMenu` are both components.
- **Prop** — a value passed into a React component from its parent, e.g. `restrictToCustomerIds` passed into `CustomerPicker`.
- **Hook (React)** — a function like `useState` or `useLocation` that lets a component hold onto data or read browser/routing info. Not to be confused with a git hook.
- **State (React)** — data a component remembers between renders (e.g. which customer is currently selected). "Navigation state" (`location.state`) is a small, different kind of state React Router lets one page pass to another when navigating.
- **Long-press** — pressing and holding a finger on a touchscreen without moving it, held for some minimum time (here, 500 milliseconds) before it counts as a distinct gesture from a tap.
- **Kanban board** — a layout with items grouped into columns (e.g. one column per status), which you can visually scan or drag between. This app's "Board" view is a lightweight version of that idea.
- **Booking status vs. confirmation state** — `status` (Pending / In Progress / Completed / Cancelled / No-show) is a real column stored in the database. "Confirmation state" (Unconfirmed / Confirmed / etc., shown as a colored badge) is *computed* from `status` plus `payment_status`, `booking_source`, and `service_category` — it's never stored, so it can't drift out of sync with the real payment record.
- **`service_category`** — which kind of service a booking is for: Grooming, Hotel, Daycare, or Veterinary.
- **`booking_source`** — whether a booking was made online by the customer themselves, or as a Walk-in typed in by staff.
- **payment_status** — Pending / Fully Paid / Partially Paid, derived from that booking's actual payment transactions.

## How you'll know it worked

This is a plan-only document — no code has been changed yet. Once this plan is implemented, the click-by-click manual test steps and the automated test suite results will be written into `testing/testing.md` in this same session folder (`Projects/golden-fur/sessions/113-vet-consultation-queue-and-ui-polish/testing/testing.md`).

**Update — implementation is now done**, on branch `feat/vet-consultation-queue-integration`. All 7 items above landed as planned; the one addition beyond this plan's own scope was fixing a second, independent copy of item 4's "Confirmed at creation" special case, found inside `bookingGroup.service.ts`'s multi-booking checkout path (the plan's own exploration had only found the `booking.service.ts` copy) — same fix, same reasoning, applied to both. See `testing/testing.md` for the click-by-click manual test (grouped A-G, one per item), the file-by-file "What changed", and the actual test-suite pass counts.

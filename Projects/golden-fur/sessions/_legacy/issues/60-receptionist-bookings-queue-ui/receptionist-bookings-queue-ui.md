# Issue #60 Verification: Receptionist Bookings Queue UI

**Issue:** #60 — feat(booking): Receptionist Bookings Queue UI
**Owner:** James
**Branch:** `feat/receptionist-bookings-queue-ui`
**Base:** `dev`
**Depends on:** #51, #56 merged
**Sprint:** Sprint 2 — Epic B — M03 Appointment & Booking

## Overview

Adds `ReceptionistBookingsQueuePage` at `/staff/bookings/queue` —
date/service-type/status-filterable list of bookings, additionally
branch-filterable for Superadmin (AC-2, same conditional-render pattern
`AdminStaffListPage` uses for its Superadmin-only branch filter),
reschedule/cancel actions reusing `SlotPicker`/`StaffPickerList` in
receptionist (3-color) mode, and a "New booking" shortcut into #55's flow
shell in receptionist mode.

This issue is the second consumer of #59's new `GET /bookings` endpoint —
see `testing/docs/issues/59-customer-booking-management-ui/` for that
endpoint's customer-scope verification; this doc covers its staff/branch-
filtered scope.

## What Changed

- **Added**
  `client/src/features/booking/pages/ReceptionistBookingsQueuePage/`
  (`.tsx`, `.module.css`, `.spec.ts`).
- **Modified** `client/src/features/booking/booking.routes.tsx` — registers
  `/staff/bookings/queue` (`StaffAuthGuard`).

### Follow-up simplification — reschedule panel's Staff Picker gate

Originally resolved via a `GET /bookings/policy` fetch (valid here — staff
callers can read it, unlike #55/#59's customer surfaces which 403'd on the
same call). Simplified anyway for one consistent pattern across all three
reschedule panels: the queue's reschedule panel now always attempts to
mount `StaffPickerList` for Grooming/Veterinary, and its `onUnavailable`
callback (reading the already-fetched `GET /bookings/staff-picker`
response) hides it and flips a local `staffPickerUnavailable` flag when the
toggle is off. See `testing/docs/issues/55-booking-flow-shell/`'s
"Follow-up fix" section for the full writeup and the customer-facing 403 it
was fixing there.

### Scope note — a known display limitation

`GET /bookings` returns raw `pet_id`/`customer_id` (no nested pet/customer
name — no bulk-lookup-by-id endpoint exists for either, and adding one was
out of scope for reusing an existing pattern rather than adding more new
server surface than #56/#59 already needed). The queue currently displays a
truncated customer/pet id instead of a name. Flagging this plainly for a
later Sprint-5-adjacent issue to pick up (e.g. alongside M08's cashier
checkout, which will need the same customer/pet display data) rather than
silently working around it with more scope creep here.

## Acceptance Criteria Map

| AC                                                                       | Automated                               | Manual |
| ------------------------------------------------------------------------ | --------------------------------------- | ------ |
| AC-1 Queue lists branch bookings, filterable by date/service type/status | `ReceptionistBookingsQueuePage.spec.ts` | Step 2 |
| AC-2 Superadmin additionally sees a branch filter                        | `ReceptionistBookingsQueuePage.spec.ts` | Step 3 |
| AC-3 Reschedule/cancel succeed via #54's endpoints, reflect immediately  | manual                                  | Step 4 |
| AC-4 "New booking" opens #55's flow shell in receptionist mode           | `ReceptionistBookingsQueuePage.spec.ts` | Step 5 |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/booking/pages/ReceptionistBookingsQueuePage
npm --prefix client run lint
```

## Postman Verification

Needs one **Receptionist** account (branch-scoped) and one **Superadmin**
account.

1. Import `receptionist-bookings-queue-ui.postman_collection.json` → fill
   collection variables → Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom:
   1. **Login receptionist** / **Login superadmin** → 200 each.
   2. **AC-1 Receptionist lists bookings for their own branch, filtered by
      today's date** → 200; every row's `branch_id` equals the
      receptionist's own branch (client-side default — the endpoint itself
      doesn't force this for staff callers, per #50 AC-3's "any
      authenticated staff role can SELECT all bookings").
   3. **AC-1 Filter by service_category=Grooming and status=Confirmed** →
      200; every row matches both filters.
   4. **AC-2 Superadmin lists across both branches (no branch_id filter)** →
      200; rows may span both `branch_makati_id` and `branch_southwoods_id`.
4. No cleanup needed — this endpoint is read-only.

## Manual Browser Verification

Same startup steps as `testing/docs/issues/55-booking-flow-shell/`.

**Seeded accounts** (all passwords `password123`):
`makati.receptionist1@goldenfur.com`, `makati.superadmin1@goldenfur.com`
(Superadmin requires MFA enrollment on first login — see #55's doc).

### Step 1 — Create a booking to see in the queue

1. Log in as `customer1@goldenfur.com`, create a Grooming booking for pet
   **Max** at Makati, today or in the next few days, any staff preference.

### Step 2 — Filters (AC-1)

1. Log in as `makati.receptionist1@goldenfur.com`, go to
   `http://localhost:5173/staff/bookings/queue`.

Expected: the queue loads scoped to Makati by default (no branch filter
control visible for a Receptionist), showing today's bookings with
**Date**, **Service type**, and **Status** filter controls above the list.
— **AC-1**

2. Change the **Date** filter to the date you booked in Step 1 (if not
   today).

Expected: the booking from Step 1 appears, showing service type, branch,
scheduled time, a truncated customer/pet id, and a status badge — no page
reload (check DevTools Network tab: only an XHR fires, not a document
navigation). — **AC-1**

3. Set **Service type** to `Hotel`.

Expected: the Grooming booking disappears from the list (filtered out). Set
it back to `All service types` to see it again. — **AC-1**

### Step 3 — Superadmin branch filter (AC-2)

1. Log out, log in as `makati.superadmin1@goldenfur.com`, go to
   `/staff/bookings/queue`.

Expected: an extra **Branch** filter control appears (defaulting to "All
branches") that a Receptionist never sees. — **AC-2**

2. Set **Branch** to `Southwoods`.

Expected: the Makati booking from Step 1 disappears (branch-filtered); set
back to `All branches` (or `Makati`) to see it again.

### Step 4 — Reschedule/cancel from the queue (AC-3)

1. As the Superadmin (or log back in as the Receptionist), click
   **Reschedule** on the booking.

Expected: the same inline `SlotPicker`/`StaffPickerList` panel as #59's
customer-facing reschedule, but in **receptionist (3-color) mode** — you'll
see green/amber/red-grey backgrounds on the slot grid instead of plain
available/unavailable. — **AC-3**

2. Pick a new slot and (if Grooming) a staff member, click **Confirm new
   time**.

Expected: the row updates in place in the queue immediately — no full page
reload. — **AC-3**

3. Click **Cancel** on the row, confirm.

Expected: status badge flips to **Cancelled** immediately, in place. —
**AC-3**

### Step 5 — "New booking" shortcut (AC-4)

1. Click **New booking** at the top of the queue.

Expected: navigates to `/staff/bookings/new` — #55's flow shell in
receptionist mode (customer lookup-or-create step first). — **AC-4**

## Acceptance Criteria Checklist

- [x] **AC-1:** Queue lists all bookings at the receptionist's branch,
      filterable by date/service type/status —
      `ReceptionistBookingsQueuePage.spec.ts`; manual Step 2.
- [x] **AC-2:** Superadmin additionally sees a branch filter, matching the
      Staff Directory's existing pattern —
      `ReceptionistBookingsQueuePage.spec.ts`; manual Step 3.
- [x] **AC-3:** Reschedule/cancel from the queue succeed via #54's endpoints
      and reflect immediately in the list without a full page reload —
      manual Step 4.
- [x] **AC-4:** A "New booking" action opens #55's flow shell in
      receptionist (walk-in/phone-in) mode —
      `ReceptionistBookingsQueuePage.spec.ts`; manual Step 5.

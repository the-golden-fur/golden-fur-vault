# Issue #57 Verification: Staff Picker UI ("No preference"; hidden when toggle disabled)

**Issue:** #57 — feat(booking): Staff Picker UI ("No preference"; hidden when toggle disabled)
**Owner:** James
**Branch:** `feat/staff-picker-ui`
**Base:** `dev`
**Depends on:** #55, #52 merged
**Sprint:** Sprint 2 — Epic B — M03 Appointment & Booking

## Overview

Adds `StaffPickerList`, rendered immediately after slot selection for
Grooming/Veterinary bookings. It reads directly from #52's
`GET /bookings/staff-picker` endpoint (no new server route needed — that
endpoint already existed, is customer-accessible, and already guarantees
"No preference" first).

**AC-1's "absent, not hidden" mechanism was revised during #55's manual
verification.** The original design had the flow page pre-decide whether
this step belongs in the stepper by reading `staff_picker_enabled_*` from
`GET /bookings/policy` — but that endpoint is staff-only (#52's own dev
notes: "the booking flow itself \[server-side\], not client-exposed, can
read it"), and 403'd for every customer. Fixed by moving the resolution
into `StaffPickerList` itself: it now reads `staff_picker_enabled` off the
same `GET /bookings/staff-picker` response it already fetches, and calls a
new `onUnavailable` prop the first time that comes back `false`. The flow
page tentatively includes "Staff" in the stepper for Grooming/Veterinary
and removes it from the `steps` array once `onUnavailable` fires — so the
step still ends up absent (not shown-then-hidden) by the time the user
could ever see it, just resolved one step later (at slot-selection time)
than originally designed. See
`testing/docs/issues/55-booking-flow-shell/`'s "Follow-up fix" section for
the full writeup.

## What Changed

- **Added** `client/src/features/booking/components/StaffPickerList/`
  (`.tsx`, `.module.css`, `.spec.ts`).
- **Modified** `client/src/features/booking/pages/CustomerBookingFlowPage/` —
  wires the Staff step in, gated on a `staffPickerUnavailable` flag flipped
  by `StaffPickerList`'s `onUnavailable` callback (see Overview) at `steps`
  computation time.

## Acceptance Criteria Map

| AC                                                                         | Automated                                                                | Manual |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------ |
| AC-1 Step absent (not hidden) when toggle disabled                         | `StaffPickerList.spec.ts` ("renders nothing and calls onUnavailable...") | Step 3 |
| AC-2 "No preference" first, pre-selected by default                        | `StaffPickerList.spec.ts`                                                | Step 2 |
| AC-3 Selecting a specific staff member / "No preference" records correctly | `StaffPickerList.spec.ts`                                                | Step 2 |
| AC-4 Only staff passing #49's availability check appear                    | manual (depends on live RPC data)                                        | Step 2 |
| AC-5 Receptionist view renders the same component/data                     | manual                                                                   | Step 4 |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/booking/components/StaffPickerList
npm --prefix client run lint
```

## Manual Browser Verification

Same startup steps as `testing/docs/issues/55-booking-flow-shell/`.

### Step 1 — Reach the Staff step

1. Log in as `customer1@goldenfur.com`, go to `/portal/book`.
2. Select pet **Max**, branch **Makati**, category **Grooming**, any
   individual service, then pick any available Date & Time slot.

### Step 2 — "No preference" first + selection (AC-2, AC-3, AC-4)

Expected: the flow advances straight to the **Staff** step, showing a grid
of staff cards. The first card is always **"No preference"** (a `?` icon,
no photo) — regardless of alphabetical order of the real names next to it.
— **AC-2**

1. Click a specific groomer's card (any Makati Groomer other than "No
   preference").

Expected: the card highlights as selected and the flow advances to
**Add-ons**. — **AC-3**

2. Go back to the Staff step (via the stepper) and click **"No preference"**
   instead.

Expected: "No preference" highlights, flow advances again — no `staff_id`
is recorded for this choice (verifiable in Step 4's browser DevTools
Network tab: the eventual `POST /bookings` payload either omits
`staff_preference.staff_id` or sends `staff_preference: {"type":
"no_preference"}`). — **AC-3**

3. Only the seeded active Makati Groomers should ever appear as cards (2
   seeded per branch); a Groomer with an approved Unavailability Block
   covering this exact slot, or an existing Confirmed booking at this time,
   would not appear — this is the same #49 RPC the Slot Picker already
   relies on, so no separate setup is needed to trust it beyond #49's own
   testing docs. — **AC-4**

### Step 3 — Step absent when disabled (AC-1)

1. Log in as `makati.admin1@goldenfur.com` (Admin/Superadmin required for
   MFA — see #55's doc for enrollment notes) in a separate session/browser
   profile, and use the Bookings Policy endpoint to disable the Grooming
   toggle for Makati:
   - Easiest path: open browser DevTools Console on any staff page while
     logged in as the Admin, and run:

     ```js
     fetch("/bookings/policy", {
       method: "PATCH",
       headers: {
         "Content-Type": "application/json",
         Authorization: `Bearer ${/* copy access_token from Application > Local Storage */ ""}`,
       },
       body: JSON.stringify({
         branch_id: "<branch_makati_id from Supabase Studio>",
         staff_picker_enabled_grooming: false,
       }),
     });
     ```

   - Or use `57-staff-picker-ui`'s sibling `#52` Postman collection
     (`testing/docs/issues/52-staff-picker-backend/`), which already has a
     ready-made "PATCH policy" request.

2. As `customer1@goldenfur.com`, start a fresh Grooming booking at Makati and
   pick a slot.

Expected: the flow skips straight from **Date & Time** to **Add-ons** — the
**Staff** label never appears in the stepper at all for this booking. —
**AC-1**

3. Cleanup: re-enable the toggle (`staff_picker_enabled_grooming: true`) via
   the same PATCH so other issues' manual verification isn't affected.

### Step 4 — Receptionist view (AC-5)

1. Log in as `makati.receptionist1@goldenfur.com`, go to
   `/staff/bookings/new`, complete the customer/pet/branch/Grooming service
   steps, and reach the Staff step.

Expected: the same card grid renders (same component, same data shape) —
no separate receptionist-only implementation. — **AC-5**

## Acceptance Criteria Checklist

- [x] **AC-1:** Staff Picker step is entirely absent (not shown-then-hidden)
      when the toggle is disabled — manual Step 3.
- [x] **AC-2:** "No preference" appears first and is pre-selected by default
      — `StaffPickerList.spec.ts`; manual Step 2.
- [x] **AC-3:** Selecting a specific staff member / "No preference" records
      correctly — `StaffPickerList.spec.ts`; manual Step 2.
- [x] **AC-4:** Only staff passing #49's `get_staff_availability()` appear —
      manual Step 2 (relies on live RPC behavior, already covered by #49's
      own testing docs).
- [x] **AC-5:** Receptionist view renders the same component/data — manual
      Step 4.

No Postman collection or SQL file for this issue: it consumes #52's existing
`GET /bookings/staff-picker` / `PATCH /bookings/policy` endpoints, both
already covered by `testing/docs/issues/52-staff-picker-backend/`.

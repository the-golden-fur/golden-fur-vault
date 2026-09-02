# Issue #56 Verification: Slot Picker UI (customer + colour-coded receptionist views)

**Issue:** #56 — feat(booking): Slot Picker UI (customer + colour-coded receptionist views)
**Owner:** James
**Branch:** `feat/slot-picker-ui`
**Base:** `dev`
**Depends on:** #55, #51 merged
**Sprint:** Sprint 2 — Epic B — M03 Appointment & Booking

## Overview

Adds `SlotPicker` — one component, two render modes gated by viewer role:
customer mode shows only available/unavailable per slot; receptionist/admin
mode adds the 3-color coverage overlay (available/green,
partial/amber, full/red-grey). Wired into `CustomerBookingFlowPage` as the
Date & Time step (#55's shell). Hotel/Daycare bookings, which skip the Staff
Picker step, proceed directly from this step to add-ons.

### Supporting server endpoint (new in this issue)

Neither the Slot Picker nor anything else in the merged `#51`/`#52` backend
exposed a way to read per-slot capacity ahead of booking submission —
`checkCapacity()` was server-internal only, and its Hotel/Daycare stub
numbers are gated behind env vars the client can't reach. Added
`GET /bookings/availability`, a thin read that generates a day's candidate
slots from the branch's `operating_hours` and runs the same
`checkCapacity()`/`get_staff_availability()` logic #51/#49 already use at
submission time, read-only and ahead of it — exactly the "queries
availability" behavior the original #51 Guide dev notes described.

## What Changed

- **Added** `server/src/features/booking/services/availability.service.ts`
  (+spec) — `getDaySlots()`: generates back-to-back candidate slots across a
  day from `branches.operating_hours`/`timezone`, then computes
  `available`/`level` per slot (Grooming/Veterinary via the #49 RPC +
  active-roster count; Hotel/Daycare via the same overlap-count logic as
  `capacity.service.ts`, whose two internal query helpers were exported —
  not otherwise changed — for reuse here).
- **Modified**
  `server/src/features/booking/modules/validators/booking.validator.ts` —
  added `availabilityQueryValidator`.
- **Modified** `server/src/features/booking/booking.controller.ts` /
  `booking.routes.ts` — registers `GET /bookings/availability`
  (`jwtMiddleware` only; read-only, no role gate beyond authentication).
- **Added** `client/src/features/booking/components/SlotPicker/` (`.tsx`,
  `.module.css`, `.spec.ts`).
- **Modified** `client/src/features/booking/pages/CustomerBookingFlowPage/` —
  wires the Slot Picker into the Date & Time step; selecting a slot
  auto-advances to Staff Picker (Grooming/Veterinary, when enabled) or
  straight to Add-ons/Payment otherwise (AC-4).
- **Modified** `client/src/styles/tokens.css` — `--color-slot-available-*` /
  `--color-slot-partial-*` / `--color-slot-full-*` token pairs (both themes).

## Acceptance Criteria Map

| AC                                                            | Automated            | Manual |
| ------------------------------------------------------------- | -------------------- | ------ |
| AC-1 Customer view: available/unavailable only, no color code | `SlotPicker.spec.ts` | Step 2 |
| AC-2 Receptionist/Admin view: 3-color overlay                 | `SlotPicker.spec.ts` | Step 3 |
| AC-3 Empty state with a way to pick another date              | `SlotPicker.spec.ts` | Step 4 |
| AC-4 Selecting a slot advances to the correct next step       | manual (flow-level)  | Step 5 |

## Automated Verification

```powershell
npm --prefix server test -- --run src/features/booking/services/availability.service.spec.ts
npm --prefix server run typecheck
npm --prefix server run lint
npm --prefix client test -- --run src/features/booking/components/SlotPicker
npm --prefix client run lint
```

## Postman Verification

Needs one **customer** account and `branch_makati_id` from Supabase Studio
(Table Editor → `branches`).

1. Import `slot-picker-ui.postman_collection.json` → fill collection
   variables (`base_url`, `customer_account_email`, `customer_password`,
   `branch_makati_id`) → Save.
2. Start the server: `npm --prefix server run dev`
3. Run top to bottom:
   1. **Login customer** → 200.
   2. **AC-1/AC-4 Grooming availability, one week out** → 200; response is
      `{ slots: [...] }`, each slot has `start`/`end`/`available`/`level`/
      `eligible_staff_count`, and (fresh seed data) every slot should be
      `level: "available"` since no bookings exist yet.
   3. **Hotel availability (level derives from cage capacity, not staff)** →
      200; Hotel slots omit `eligible_staff_count` entirely (that field only
      applies to the Grooming/Veterinary staff-count path).
   4. **Hotel availability missing pet_weight_class** → 400 (validator
      rejects; Hotel requires the weight class).
   5. **Unknown branch_id** → 404 (branch not found).
4. No cleanup needed — this endpoint is read-only.

## Manual Browser Verification

Same startup steps as `testing/docs/issues/55-booking-flow-shell/` (Supabase,
server, and client all running, module-1/2/3 seeds applied).

### Step 1 — Reach the Date & Time step

1. Log in as `customer1@goldenfur.com`, go to `/portal/book`.
2. Select pet **Max**, branch **Makati**, category **Grooming**, any
   individual service, click through to the **Date & Time** step.

### Step 2 — Customer mode has no color coding (AC-1)

Expected: a date field + Previous/Next day buttons, and a grid of time
buttons. Each button shows only a time, and unavailable slots are simply
greyed out/disabled — no green/amber/red-grey distinction is visible
anywhere. — **AC-1**

### Step 3 — Receptionist mode shows the 3-color overlay (AC-2)

1. Log out, log in as `makati.receptionist1@goldenfur.com`, go to
   `/staff/bookings/new`, and reach the same Date & Time step (any category
   that uses staff, e.g. Grooming).

Expected: the same slot grid now shows green/amber/red-grey backgrounds per
slot. On a freshly-seeded database every Grooming slot within operating
hours should be green (`available`) since no bookings exist yet — to see
amber/red-grey, complete Step 5 below once or twice first (each confirmed
booking makes that exact slot/staff-member unavailable), then revisit this
step and re-check the same date/time. — **AC-2**

### Step 4 — Empty state (AC-3)

Both seeded branches (`module-1-staff-auth` seed) are open every day of the
week (just shorter hours on weekends), so there's no closed-day date to pick
in the browser to trigger the "no slots at all" message directly. The
component has two related empty states — `SlotPicker.spec.ts` covers both
directly, and the "all slots full" variant is reachable in the browser:

1. Pick a Grooming date/time and, using two different browser sessions (or
   the Postman collection below) as **two different customers**, book the
   _same_ slot with _every_ seeded Makati Groomer (2 accounts) via
   `/portal/book`.
2. Revisit that exact date on the Date & Time step.

Expected: the previously-available slot is now greyed out; if it was the
only slot generated for that narrow a window, the "No open slots on this
date" message appears with the date nav still usable. — **AC-3** (also
directly covered by `SlotPicker.spec.ts`'s empty-state test, which exercises
both message variants without needing this setup).

### Step 5 — Selecting a slot advances the flow (AC-4)

1. Back on a Grooming booking, click any available (green, if receptionist
   mode) slot.

Expected: the flow immediately advances to the **Staff** step (no extra
click needed). — **AC-4**

1. Start a new Hotel booking instead and click an available slot.

Expected: the flow advances straight to **Add-ons**/**Review & Pay** (no
Staff step exists for Hotel). — **AC-4**

## Acceptance Criteria Checklist

- [x] **AC-1:** Customer view shows only available/unavailable — no staff
      names or partial-availability color coding — `SlotPicker.spec.ts`;
      manual Step 2.
- [x] **AC-2:** Receptionist/Admin view shows the 3-color coverage overlay
      for the same data — `SlotPicker.spec.ts`; manual Step 3.
- [x] **AC-3:** A date with zero available slots shows a clear empty state
      with a way to pick another date — `SlotPicker.spec.ts`; manual Step 4.
- [x] **AC-4:** Selecting a slot advances to Staff Picker (Grooming/Vet, when
      enabled) or straight to add-ons (Hotel/Daycare/toggle-disabled) —
      manual Step 5.

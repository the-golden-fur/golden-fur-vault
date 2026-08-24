# Issue #69 Verification: Daycare check-in/checkout UI

**Issue:** #69 — feat(daycare): Daycare check-in/checkout UI
**Owner:** Alarie
**Branch:** `feat/daycare-ui`
**Base:** `dev`
**Depends on:** #65 merged
**Sprint:** Sprint 3 Epic A — M06 Daycare Management

## Overview

`DaycareCheckInPage` (`/staff/daycare/check-in`) — two entry points (an existing confirmed Daycare booking for today, or a walk-in against an existing or freshly-registered pet) — and `DaycareCheckoutPage` (`/staff/daycare/checkout/:sessionId?`) — itemized charge breakdown after checkout.

## What Changed

- **Added** `client/src/features/daycare/daycare.types.ts`, `client/src/features/daycare/api/daycare.api.ts` (+spec) — client mirror of #65's `DaycareSession`, `checkInDaycareSession()`/`checkOutDaycareSession()`.
- **Added** `client/src/features/daycare/pages/DaycareCheckInPage/DaycareCheckInPage.tsx` (+spec) — role gate (`Receptionist`/`Admin`/`Supervisor`/`Superadmin`); "Existing booking" tab lists today's Confirmed Daycare bookings at the viewer's branch; "Walk-in" tab searches an existing customer by email, picks one of their pets, or reuses `PetForm` (M02, unmodified) to register a new one.
- **Added** `client/src/features/daycare/pages/DaycareCheckoutPage/DaycareCheckoutPage.tsx` (+spec) — checks out a session by id and shows the charge itemized by hour.
- **Added** `client/src/features/daycare/daycare.routes.tsx`; **modified** `client/src/routes.tsx` (registers it) and `staffDashboard.config.ts` (Receptionist dashboard's "Daycare Check-in" tile now links to `/staff/daycare/check-in`).

### Decision flagged for the reviewer: how the checkout screen gets a session id

`#65`'s backend exposes only `POST /daycare/check-in` and `POST /daycare/sessions/:id/checkout` — there is no "list active sessions at my branch" endpoint. Adding one would be a new server route, outside this issue's (client-only) Affected Files. Instead: `DaycareCheckInPage`'s success screen shows a **"Go to checkout"** button that navigates straight to `/staff/daycare/checkout/:sessionId` with the just-created session's id; `DaycareCheckoutPage` also accepts the id typed/pasted in manually (pre-filled when reached via that link, editable otherwise). This covers the realistic same-day check-in → checkout flow without inventing new backend surface. **Raise with Alarie if a "browse active sessions" list is actually needed this sprint** — it would need a new `GET` route added to `daycare.routes.ts` first.

### Decision flagged for the reviewer: the checkout breakdown's hour count is for display only

The backend returns only the final `computed_charge`, not an itemized breakdown. `DaycareCheckoutPage` re-derives the succeeding-hour count client-side from `check_in_at`/`check_out_at` (mirroring `daycareBilling.service.ts`'s own formula) purely to label the itemized rows — the **total shown is always the server's own `computed_charge`**, never recalculated, so AC-2's "total matches the backend's computed_charge exactly" holds by construction even in the reviewer-flagged 2h15m edge case from #65's own verification doc.

## Acceptance Criteria Map

| AC                                                                                                            | Automated                                           | Manual UI                          |
| ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ---------------------------------- |
| AC-1 check-in accepts an existing booking or a new walk-in session                                            | `DaycareCheckInPage.spec.ts`                        | steps D3, D4                       |
| AC-2 checkout screen shows charge broken down by hours; total matches the backend's `computed_charge` exactly | `DaycareCheckoutPage.spec.ts`                       | step D5                            |
| AC-3 check-in after cutoff shows a clear message and blocks the action — no session created                   | `daycare.api.spec.ts`, `DaycareCheckInPage.spec.ts` | step D6 (time-dependent, see note) |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/daycare
npm --prefix client run lint
npm --prefix client run build
```

Expected: 3 test files / 9 tests pass; lint 0 errors/warnings; `tsc -b && vite build` succeeds with no type errors.

## Manual UI Verification

### Prerequisites

- Server running (`npm --prefix server run dev`) with migrations through `040` pushed.
- Client running (`npm --prefix client run dev`).
- One **Receptionist** account at Makati (Sprint 1 seed data, `makati.receptionist1@goldenfur.com` / `password123`).
- A **Confirmed Daycare booking** at Makati for **today** (create via `/staff/bookings/new`, or reuse #51's booking collection with today's date).
- At least one existing customer with a registered pet, for the walk-in test.

### D. Steps

1. Log in to the staff portal as the Receptionist. From the dashboard, click **Daycare Check-in** (or navigate to `/staff/daycare/check-in`).
2. **Existing booking tab** (default): confirm today's Confirmed Daycare booking appears in the list with the pet's name and time. Select it and click **Check in** → success screen appears with **"Go to checkout"** and **"Check in another pet"** buttons (AC-1).
3. Click **Check in another pet**, switch to the **Walk-in** tab, search by the existing customer's email, select the customer, pick one of their pets, and click **Check in** → success screen appears again (AC-1).
4. Repeat the walk-in flow once more, but click **Register a new pet** instead of picking an existing one — fill out the reused `PetForm` fields and submit; the new pet becomes selectable immediately, then check in (AC-1, pet-registration reuse).
5. From either success screen, click **Go to checkout** → the checkout page loads with the session id pre-filled. Click **Check out** → the breakdown shows "First hour ₱100" (and, if more than an hour has elapsed, a "N succeeding hours × ₱50" line) plus a **Total** that matches the number visible in Supabase Studio → Table Editor → `daycare_sessions.computed_charge` for that row exactly (AC-2).
6. **Time-dependent AC-3 check**: only after 4:00 PM Philippine time (Asia/Manila, UTC+8), repeat step 3 (walk-in check-in) — expect the check-in to be blocked with the message _"Check-in unavailable after 4:00 PM"_ and no new row in `daycare_sessions` for that pet/timestamp. Before 4 PM local time this step will succeed instead (201) — that's expected, not a failure; re-test after 4 PM, or use the automated `daycare.api.spec.ts` test to exercise the blocked-message rendering directly.

### E. Cleanup

Supabase Studio → Table Editor → `daycare_sessions` → filter by the `pet_id`/`booking_id` used above → delete the rows. Delete any pet registered solely for the walk-in test from `pets` if desired.

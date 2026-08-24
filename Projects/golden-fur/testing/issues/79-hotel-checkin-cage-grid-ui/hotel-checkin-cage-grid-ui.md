# Issue #79 Verification: Hotel check-in form UI + cage status grid UI

**Issue:** #79 — feat(hotel): Hotel check-in form UI + cage status grid UI
**Owner:** James
**Branch:** `feat/hotel-checkin-cage-grid-ui`
**Base:** `dev`
**Depends on:** #75, #78 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

`HotelCheckInPage` at `/staff/hotel/check-in` — select today's confirmed Hotel booking, capture structured feeding/walking/medication instructions, accept or manually override the server-suggested cage, toggle the notification opt-in, and submit. `CageStatusGrid` (embedded in the check-in page, and reused wherever cage status needs to be shown) renders the four size groups with status-colour badges and doubles as the manual cage-override control.

### Decision flagged for the reviewer: no walk-in mode

Unlike `DaycareCheckInPage` (#69), which supports both an existing booking and a brand-new walk-in session, `HotelCheckInPage` only supports an **existing confirmed booking**. Modules-Features' M05 Process 1 explicitly starts "Pet arrives for Pet Hotel stay (**confirmed booking with downpayment recorded**...)" — Hotel always requires the 50% downpayment collected at booking time (M03 Process 1), so there is no walk-in path to build here; a walk-in customer would go through the normal M03 booking flow first (which does have a receptionist-on-behalf-of-walk-in mode already), then check in the same way. **Raise with Alarie if a direct walk-in-to-check-in shortcut was actually intended.**

### Decision flagged for the reviewer: `CageStatusGrid`'s "select any other Available cage" affordance

The Guide's dev notes say "the UI displays the server-suggested size/cage prominently but never disables the override control." The suggested-size radio list covers overriding _within_ the suggested size category; `CageStatusGrid` embedded below it additionally lets the receptionist click **any** Available cage of **any** size, satisfying "manually override to a different available cage size/unit" from AC-4 literally (not just a same-size swap).

## What Changed

- **Added** `client/src/features/hotel/hotel.types.ts`, `client/src/features/hotel/api/hotel.api.ts` (+spec) — full client mirror of #75/#76/#77/#78's response shapes and every hotel endpoint (used across #79/#80/#81, added together here since it's one shared file).
- **Added** `client/src/features/hotel/components/CageStatusGrid/CageStatusGrid.tsx` (+CSS module) — grouped-by-size grid with `--color-cage-status-*` badges; Admin-only Under Maintenance toggle per card; `onSelectCage`/`selectedCageId` props double as the check-in page's override control.
- **Added** `client/src/features/hotel/pages/HotelCheckInPage/HotelCheckInPage.tsx` (+CSS module) — booking picker, cage suggestion + `CageStatusGrid` override, feeding/walking/medication sections (inline sub-forms, matching the Guide's Directory Structure which lists no separate `CareInstructionForm`/`CageSizeSelector`/`NotificationOptInToggle` files), notification opt-in checkbox, submit.
- **Added** `client/src/features/hotel/hotel.routes.tsx`; **modified** `client/src/routes.tsx` (registers `/staff/hotel/check-in`, `/staff/hotel/checkout(/:stayId)`, `/staff/hotel/care-log` — the latter two back #81/#80) and `client/src/features/staff/config/staffDashboard.config.ts` (Receptionist's "Hotel Check-in" tile now links to `/staff/hotel/check-in`; added a "Hotel Checkout" tile).
- **Modified** `client/src/styles/tokens.css` — added the 4 new `--color-cage-status-*` token pairs (both `customer` and `staff` theme blocks), per Sprint4-EpicA-Design.xlsx → Styles.

## Acceptance Criteria Map

| AC                                                                                                                | Automated                                                                                                                                                                                                      | Manual UI   |
| ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| AC-1 check-in form captures all care instruction fields; validates required fields before submission              | `hotel.validator.ts` server-side (`checkInValidator`, `.min(1)` on required text fields) — the client gates submission on cage selection only and surfaces the server's 400 as a banner on empty required text | step D3, D4 |
| AC-2 notification opt-in toggle saves correctly to hotel_stays                                                    | `hotel.api.spec.ts`                                                                                                                                                                                            | step D5     |
| AC-3 cage status grid shows correct status colour per size; updates without a page reload after check-in/checkout | manual — `refreshSignal` prop design                                                                                                                                                                           | step D6     |
| AC-4 correct cage size suggestion based on weight_class; manual override to any other available cage              | `cageAssignment.service.spec.ts` (backend)                                                                                                                                                                     | step D4     |
| AC-5 Admin sees the Under Maintenance toggle; non-Admin roles do not                                              | manual (role branch in `CageStatusGrid.tsx`)                                                                                                                                                                   | step D6     |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/hotel
npm --prefix client run lint
npx tsc -b --noEmit
```

(Run from `client/` for the `tsc` command, or use `npm --prefix client run build`.)

## Manual UI Verification

### Prerequisites

- Server running (`npm --prefix server run dev`) with migrations through `053` pushed and the `module-4-hotel` seed applied (`npm run seed:module-4`).
- Client running (`npm --prefix client run dev`).
- One **Receptionist** account.
- A **Confirmed Hotel booking** for **today**, for a pet with a known `weight_class`.

### D. Steps

1. Log in to the staff portal as the Receptionist.
2. From the staff dashboard, click **Hotel Check-in** (or navigate to `/staff/hotel/check-in`).
3. Select the confirmed booking from the list — the form's remaining sections appear.
4. Confirm the suggested cage size and its available cages are listed; confirm the `CageStatusGrid` below shows the full grid and clicking a **different** Available cage (any size) updates the selection (AC-4).
5. Fill in at least one feeding time, one walk time, leave medications empty (or confirm pre-fill if you set up a current M07 prescription first), check the notification opt-in box, and submit.
6. Confirm the success screen appears with a **Go to checkout** link; navigate back to the check-in page and confirm the grid now shows the checked-in cage as **Occupied** without a manual reload (AC-3). Log in as an Admin in a second session and confirm the **Mark Under Maintenance** button is visible on cage cards there but was not visible for the Receptionist (AC-5).

### E. Cleanup

Supabase Studio → delete the `care_log_entries` / `care_*_instructions` / `hotel_stays` rows created above, and reset the used cage's `status` back to `Available` if it wasn't released via checkout.

# Issue #81 Verification: Checkout flow UI

**Issue:** #81 — feat(hotel): Checkout flow UI
**Owner:** James
**Branch:** `feat/hotel-checkout-ui`
**Base:** `dev`
**Depends on:** #78 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

`HotelCheckoutPage` at `/staff/hotel/checkout` (and `/staff/hotel/checkout/:stayId`) — a checkout summary showing the downpayment already collected, any calculated extension fee (or "None"), and the reconciled remaining balance, visually distinguished (larger/bolder) so there's no ambiguity about which figure the future Sprint 5 cashier flow will collect.

### Decision flagged for the reviewer: no "browse active stays" list

Mirrors `DaycareCheckoutPage`'s (#69) own scope note: #78's backend has no "list active stays at my branch" endpoint (only `POST /hotel/stays/:id/checkout`), so this screen is reached with a known stay id — either passed via the route (`HotelCheckInPage`'s "Go to checkout" link, immediately after check-in) or entered/pasted manually. A dedicated browse-list endpoint would need a new GET route, outside this issue's (client-only) Affected Files.

## What Changed

- **Added** `client/src/features/hotel/pages/HotelCheckoutPage/HotelCheckoutPage.tsx` (+CSS module) — manual/route-supplied stay ID field, submit, breakdown display. Mirrors `DaycareCheckoutPage.tsx`'s structure (role gate, manual-ID prerequisite note, breakdown `<dl>`) with the addition of the extension-fee line and the bolder remaining-balance row.
- **Modified** `client/src/routes.tsx` / `client/src/features/hotel/hotel.routes.tsx` — registers `/staff/hotel/checkout` and `/staff/hotel/checkout/:stayId`.
- **Modified** `client/src/features/staff/config/staffDashboard.config.ts` — added a "Hotel Checkout" tile to the Receptionist dashboard, linking to `/staff/hotel/checkout`.

## Acceptance Criteria Map

| AC                                                                                                                  | Automated                                                                                                | Manual UI              |
| ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ---------------------- |
| AC-1 shows downpayment collected, any extension fee (or "None"), and the correctly reconciled remaining balance     | `hotel.api.spec.ts` (`checkOutHotelStay`)                                                                | step D3, D4            |
| AC-2 submitting checkout updates the cage's status to Available, reflected on the Cage Status Grid without a reload | covered by #79's `CageStatusGrid` design (`refreshSignal` prop) — same-page refetch, not cross-page push | step D5 (separate tab) |
| AC-3 checkout on an already-Completed stay is blocked with a clear message                                          | `checkout.service.spec.ts` (backend 409)                                                                 | step D6                |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/hotel
npm --prefix client run lint
npx tsc -b --noEmit
```

## Manual UI Verification

### Prerequisites

- Server + client running, migrations through `053` pushed.
- A checked-in Hotel stay (#75/#79) — note its `hotel_stays.id`.
- One **Receptionist** account.

### D. Steps

1. Log in as the Receptionist.
2. From the staff dashboard, click **Hotel Checkout** (or navigate directly to `/staff/hotel/checkout/<stay-id>` right after check-in via the "Go to checkout" link on the success screen — the field pre-fills).
3. If navigating manually, paste the stay's ID into the field and click **Check out**.
4. Confirm the summary shows the downpayment line **always** (even if extension fee is "None"), and the remaining balance is visually larger/bolder than the downpayment line (AC-1).
5. In a second tab, open the Cage Status Grid (`/staff/hotel/check-in`, the grid section) and confirm the checked-out cage now shows **Available** (AC-2 — note: this is a manual re-navigation/refetch, not a live cross-tab push; no realtime layer exists in this client, same limitation flagged in #68's verification doc for the Grooming queue).
6. Attempt checkout again with the same stay ID → confirm a clear "already checked out" error message appears, not a silent failure or crash (AC-3).

### E. Cleanup

None required beyond what #75/#79's docs already cover — a completed checkout is a normal, permanent record.

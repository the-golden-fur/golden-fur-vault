# Hotel checkout now shows the bill before you confirm

Branch: `feat/hotel-checkout-bill-preview`

## The request, verbatim

> when checking out hotel, it doens't show the computed bill like whats happening in daycare when checking out
>
> attached image is the daycare, i want the same for hotel

(Screenshot: `context/daycare-checkout-dialog-reference.png`.)

## Root cause / Context

Daycare's check-out confirmation calls `GET /daycare/sessions/:id/checkout-preview`, a read-only bill calculation, and draws it with `DaycareBillBreakdown`. Hotel had no equivalent. Its late-night fee and pay-at-checkout repricing lived only inside `checkOutHotelStay`, mixed in with the writes that save the checkout. So the only way to learn the amount was to check the pet out. Staff then saw a one-line "Remaining balance" message.

## What changed

### Server

- `features/hotel/services/checkout.service.ts`
  - The bill math is pulled into shared helpers that write nothing:
    - `resolveLateCharge`: late Manila days and their rate (long-stay regular rate, else the booked nightly rate, else the ₱500 fallback)
    - `priceItemsForNights`: pay-at-checkout repricing. `repriceItemsForNights` now calls it and then writes.
    - `hotelBillBreakdown`: the itemized bill
    - `loadCheckoutStay`: the stay lookup and the 404/403/409 guards
  - `checkOutHotelStay` uses these helpers with its query order unchanged, so every existing test passes as before. Its result now also carries `bill`.
  - The new `previewHotelCheckout(stayId, branchId)` returns the bill if checked out now: `breakdown`, `downpayment_collected`, `added_at_checkout`, and `amount_due` (Pending on Transactions plus what checkout would add). It skips the Boarding Checklist gate, which only blocks the checkout itself.
- `features/billing/services/payAtCheckoutCharge.service.ts`: the new `quotePayAtCheckoutCharge` makes the same reads as `postPayAtCheckoutCharge` (booking discount and promo, a group's checked-out members, what's already posted) and returns the bill without writing. This keeps a pay-at-checkout preview equal to what checkout then posts.
- `hotel.controller.ts` and `hotel.routes.ts`: the new `GET /hotel/stays/:id/checkout-preview` uses the same middleware and `HOTEL_ADVANCE_ROLES` as the checkout route.
- `hotel.types.ts`: adds `HotelBillBreakdown`, `HotelCheckoutPreview` and `CheckoutResult.bill`.

### Client

- `features/hotel/components/HotelBillBreakdown/`: a new component, the Hotel counterpart of `DaycareBillBreakdown`, and it reuses that component's CSS module. It lists the stay's nights × rate, any discount/promo, and any late nights × rate, then the Total. Below that come the downpayment, what's added at checkout, and "To collect at the cashier".
- `features/hotel/api/hotel.api.ts`: adds `getHotelCheckoutPreview`. `hotel.types.ts` mirrors the server types.
- `features/reports/components/CageOccupancyReport/CageOccupancyReport.tsx`: the confirm dialog fetches the Hotel preview for Hotel occupants and shows "If checked out now (as of …)", the same as Daycare. After checkout, a "<pet> was checked out" popup shows the itemized bill instead of the one-line banner.
- `features/hotel/pages/HotelQueuePage/HotelCheckoutPanel.tsx`: the confirm step shows the preview (or "Working out the bill…" while it loads). The result view shows the returned bill.

## Manual test: step by step

Start the dev servers (`server`: `npm run dev`, `client`: `npm run dev`). You need a Hotel stay that is **checked in and past its checkout date**. For example, the Southwoods stay checked in Oct 15 and due Oct 16.

**A. Cage Occupancy confirm dialog**

1. Go to `http://localhost:5173` and click **Staff Login**. Sign in as a Southwoods receptionist or front desk user (seed password `password123`). You should land on the **Dashboard**.
2. Open **Reports → Cage Occupancy**. Click the occupied Hotel cage, then **Check out** in its details popup.
3. The dialog **"Check out <pet>?"** should show "Working out the bill…", then "If checked out now (as of <time>):" with:
   - `Hotel stay - 1 night × ₱500`: ₱500
   - `Late checkout - 3 nights × ₱500` (in red): ₱1500
   - **Total** ₱2000, Downpayment already collected ₱250, Added to the bill at checkout ₱1500, **To collect at the cashier** ₱1500

   If no bill appears, open DevTools and look for a failed `checkout-preview` request.
4. Click **Not yet**. Nothing should be saved: the cage still reads Occupied.
5. Optional, and it really checks the pet out: open it again and click **Check out**. A **"<pet> was checked out"** popup should list the same lines.

**B. Hotel Queue → Check-out tab**

1. Open **Hotel → Queue**, then the **Check-out** tab, and pick the same stay.
2. Under Cage / Checkout due / Downpayment, the same bill should appear before **Check out now**.

API-level checks are in `testing/hotel-checkout-bill-preview.postman_collection.json`.

**Read-only check run this session against dev data:**
- The Makati stay (5 nights at the ₱750 long-stay rate, due today) previewed as on time: total ₱3,750, nothing added.
- The Southwoods stay previewed as 1 night × ₱500 plus 3 late nights × ₱500 = ₱1,500 to collect.
- The Rex test stay had already been checked out from the app at 08:17. Its saved `extension_fee` of ₱1,700 (2 nights × ₱850) matches the preview math.

## Test suites

- `server`:
  - `npm run test`: 1946/1946 passing (152 files). That includes 8 new `previewHotelCheckout` cases and 3 new `quotePayAtCheckoutCharge` cases.
  - `npm run typecheck`: clean.
  - `npm run lint`: 0 errors. The warnings are the existing `no-console` ones.
- `client`:
  - `npm run test`: 1979/1982 passing (280 files). The 3 failures are in `mfa.api.spec.ts` and `staffAuth.api.spec.ts`, and they fail identically on clean `dev` because of the local `.env`. They're unrelated to this change.
  - New tests: `HotelBillBreakdown.spec.tsx` (3), 2 in `CageOccupancyReport.spec.ts` and 1 in `HotelCheckoutPanel.spec.ts`.
  - `npm run typecheck`: clean. `npm run lint`: clean.

## Open items

- For a grouped (multi-pet) booking, the preview's `breakdown.discount` is the booking's own discount, while `amount_due` uses the group's figures, which is the same as checkout. The two can look inconsistent for grouped stays, but the cashier figure is correct.

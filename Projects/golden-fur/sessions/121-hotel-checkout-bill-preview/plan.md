---
title: Show the hotel bill before checking a pet out
date: 2026-10-19
tags: [session-plan, golden-fur]
project: golden-fur
session: 121-hotel-checkout-bill-preview
branch: feat/hotel-checkout-bill-preview
---

# 121 — Show the hotel bill before checking a pet out

## What you asked for

You asked for Hotel checkout to show the computed bill before staff confirm, the same way Daycare checkout already does.

> when checking out hotel, it doens't show the computed bill like whats happening in daycare when checking out
> attached image is the daycare, i want the same for hotel

(The screenshot shows the Daycare "Check out Large?" dialog. Under "If checked out now (as of 8:21 AM):" it lists "First hour ₱100" and "Total ₱100".)

## What this part of the app does today

Staff check a pet out of a **cage** (the kennel it sleeps in) in one of two places:

- **Cage Occupancy page**: a grid of every cage in the branch. Clicking an occupied cage and choosing "Check out" opens a **confirm dialog**, a small "are you sure?" popup with "Not yet" and "Check out" buttons.
- **Hotel Queue page, Check-out tab** (`HotelCheckoutPanel`): staff pick an active stay from a list, then press "Check out now".

For a **Daycare** pet (day care, billed by the hour), the confirm dialog first asks the server "what would this bill be if checked out right now?" and lists every line. That request is a **preview endpoint**, a URL that only calculates and saves nothing: `GET /daycare/sessions/:id/checkout-preview`. The bill is drawn by a React component called `DaycareBillBreakdown`.

For a **Hotel** pet (an overnight stay, billed per night), there's no such preview.

## What's wrong / what's missing

When a hotel pet is checked out, staff see no amounts before they confirm. A pet picked up two days late owes two extra nights, but the dialog never says so. Staff learn the amount only afterwards, from a one-line message. They can't warn the owner or catch a mistake before it's saved.

The math does exist: `checkOutHotelStay` in `server/src/features/hotel/services/checkout.service.ts` works out the late-night fee. But it does that only while actually saving the checkout, so nothing can ask for the number without also checking the pet out.

## What we're going to change

1. **Move the hotel bill math into a helper that saves nothing.** _Which files:_ `server/src/features/hotel/services/checkout.service.ts`. _Why:_ preview and checkout should call the same function, so the number staff see beforehand is always the number that gets charged. Today one step (`repriceItemsForNights`, which recalculates a pay-at-checkout bill) both calculates and writes to the database, so it's split into a "calculate" part and a "save" part.
2. **Add a hotel preview function and URL.** _Which files:_ `checkout.service.ts`, `hotel.controller.ts`, `hotel.routes.ts`, `hotel.types.ts` (server). _Why:_ this mirrors Daycare's `previewDaycareCheckout`. `GET /hotel/stays/:id/checkout-preview` returns:
   - the booked nights and nightly rate
   - any late nights and their rate
   - the downpayment already collected
   - what checkout would add to the bill
   - "To collect at the cashier", calculated the same way the cashier screen does

   Only the same staff roles that can check a hotel pet out can call it.
3. **Teach the web app to call the preview.** _Which files:_ `client/src/features/hotel/api/hotel.api.ts`, `client/src/features/hotel/hotel.types.ts`. _Why:_ the screens need a function that fetches it, written the same way as `getDaycareCheckoutPreview`.
4. **Build a `HotelBillBreakdown` component.** _Which files:_ new folder `client/src/features/hotel/components/HotelBillBreakdown/`. _Why:_ it draws the hotel bill, for example "Hotel stay - 3 nights × ₱850 ₱2,550", "Late checkout - 2 nights × ₱850 ₱1,700", then Total and "To collect at the cashier". It borrows Daycare's stylesheet so the two dialogs look the same.
5. **Show it in the cage dialog.** _Which files:_ `client/src/features/reports/components/CageOccupancyReport/CageOccupancyReport.tsx`. _Why:_ the dialog already fetches a preview for Daycare pets. It will now fetch the hotel one for Hotel pets and show "If checked out now (as of …)". After checkout, the result popup will list the bill line by line, as Daycare's does, instead of a single sentence.
6. **Show it on the Hotel Queue check-out tab.** _Which files:_ `client/src/features/hotel/pages/HotelQueuePage/HotelCheckoutPanel.tsx`. _Why:_ this is the other place hotel checkout happens, so it should show the same bill before "Check out now".
7. **Tests.** Server tests for the preview cover:
   - an on-time stay
   - a stay two nights late
   - the long-stay rate
   - a pay-at-checkout stay
   - a request from the wrong branch
   - a stay that's already checked out

   They also check that the preview saves nothing and that its numbers match what checkout charges. Client tests cover the new component and both screens.

**Test data note:** the "Rex" stay inserted earlier this session (checked in Oct 14, due out Oct 17) skipped the unpaid payment record that a normal booking creates. Until that record is added, "To collect at the cashier" would show only the late fee. Adding it is a change to the dev database, so I'll ask before doing it.

## Words you might not know

- **Endpoint / route**: a URL on the server that the web app calls to get or change data.
- **Preview**: here, a calculation the server runs and returns without saving anything.
- **Component**: a reusable piece of screen in React, the library the web app is built with.
- **Pay at checkout**: a booking whose price is only an estimate until the pet leaves, then billed for the nights actually stayed.
- **Long-stay rate**: a cheaper per-night price for long bookings. Nights past the booked end are charged at the regular rate instead.
- **Transactions**: the payment records the cashier screen reads. "To collect" is the total of the unpaid ones.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks. In short: open Rex's cage at Makati and press Check out. The dialog should list 3 nights × ₱850 = ₱2,550, a late checkout of 2 nights × ₱850 = ₱1,700, and a total of ₱4,250.

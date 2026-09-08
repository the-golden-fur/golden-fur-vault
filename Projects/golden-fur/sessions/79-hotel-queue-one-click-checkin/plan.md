---
title: One-click check-in from the Hotel Queue
date: 2026-09-08
tags: [session-plan, golden-fur]
project: golden-fur
session: 79-hotel-queue-one-click-checkin
branch: feat/hotel-queue-one-click-checkin
---

# 79 — One-click check-in from the Hotel Queue

## What you asked for

Make the Hotel Queue's "Check in" button actually check the pet in, instead
of opening a long form, and stop showing a separate landing page afterwards.

> On http://localhost:5173/staff/hotel/queue:
>
> - Clicking on check in on hotel queue should immediately check in the pet,
>   does not open http://localhost:5173/staff/hotel/queue/check-in/<id>
> - Move http://localhost:5173/staff/hotel/queue/check-in/<id> to the "..."
>   button > View booking details with an edit option at the bottom
> - Do not open this page with go to checkout and check in another pet
>   options after checking it, just return to the queue and show a modal if
>   success or fail
>
> you may update the documentation in golden-fur-vault repo if needed
> you may file and promote notes to library, i'll leave decision making to you
> and make the pr after

## What this part of the app does today

**Golden Fur** is a pet-services booking app. One of the services is a pet
**hotel** (overnight boarding). Staff work the **Hotel Queue** — a screen at
`/staff/hotel/queue` with two tabs, **Check In** and **Check Out**.

- The **Check In** tab shows a list of confirmed hotel bookings whose pets
  haven't arrived yet. Each booking is a card with the pet's name, the
  owner, the dates, and a **Check in** button.
- **"Check in"** in this app means: assign the pet a **cage**, record the
  **care instructions** (what to feed it, when to walk it, any medication),
  create a **stay** record, and flip the booking's status from _Pending_ to
  _In Progress_.
- Until this change, clicking **Check in** opened a whole separate page
  (`/staff/hotel/queue/check-in/<booking id>`) — a five-section form for the
  cage and the care instructions. The form pre-filled itself from whatever
  the customer typed when they booked, and it was **read-only** until you
  pressed an **Edit** button at the bottom. After you submitted it, the page
  changed to a "Pet checked in successfully" screen with two buttons:
  **Go to checkout** and **Check in another pet**.

## What's wrong / what's missing

For the normal case — the customer already filled in the care instructions
at booking time, and any available cage will do — that form is pure
friction. Staff open it, glance at it, and press **Check in** without
changing anything. Then they get a landing page with two choices they
didn't ask for. The advisor demo flagged this as too many clicks for what
should be a single action.

## What we're going to change

1. **The row's "Check in" button checks the pet in on the spot.** — _Which
   files:_ `client/src/features/hotel/components/HotelBookingPicker/HotelBookingPicker.tsx`,
   `client/src/features/hotel/pages/HotelQueuePage/HotelQueuePage.tsx`,
   new `client/src/features/hotel/pages/HotelQueuePage/buildQuickCheckInPayload.ts`
   — _Why:_ the check-in API already accepts a request with **no cage**
   (it picks the first free cage of the right size) and **no medication
   list** (it copies the pet's current vet prescription). So the button can
   send the booking's own saved care instructions and let the server fill
   in the rest. No new backend work.

2. **Show the result in a small pop-up (a "modal") over the queue.** —
   _Which files:_ `HotelQueuePage.tsx` (+ `HotelQueuePage.module.css`) —
   _Why:_ the request asks for "a modal if success or fail". On success it
   says "Pet checked in successfully." and the just-checked-in booking drops
   off the list; on failure it shows the server's reason (e.g. "No available
   cage of the suggested size (S)").

3. **Move the old form to the "..." menu as "View booking details".** —
   _Which files:_ `HotelBookingPicker.tsx`,
   `client/src/features/hotel/pages/HotelCheckInFormPage/HotelCheckInFormPage.tsx`
   — _Why:_ staff who _do_ need to change the cage or fix a care
   instruction before check-in still need the form. It keeps its own URL
   (`/staff/hotel/queue/check-in/<id>`); only the way you reach it changed —
   the "..." kebab menu on each row, item **View booking details**. The
   page is retitled **Booking details**. Its **Edit** toggle at the bottom
   is unchanged.

4. **Drop the "Go to checkout / Check in another pet" landing screen.** —
   _Which files:_ `client/src/features/hotel/pages/HotelQueuePage/HotelCheckInPanel.tsx`
   (+ `.module.css`), `HotelCheckInFormPage.tsx` — _Why:_ after a check-in
   from the details page, it now redirects straight back to the queue with a
   marker in the URL (`?checkedIn=success`) so the queue shows the same
   success modal. No intermediate screen either way.

## Words you might not know

- **cage** — a numbered enclosure in the hotel, sized S/M/L. A pet is
  assigned one at check-in and it's marked _Occupied_ until checkout.
- **stay** — the database row representing "this pet is physically here
  now". Created at check-in, closed at checkout.
- **care instructions** — structured feeding / walking / playtime /
  medication rows attached to a stay, which generate the daily task
  checklist staff work from.
- **payload** — the bundle of data the browser sends to the server for one
  request.
- **modal** — a pop-up box that sits on top of the page and blocks the rest
  of it until you dismiss it.
- **prescription auto-fill** — if the request leaves the medication list
  out entirely, the server copies the medications from the pet's most
  recent completed vet consultation.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.

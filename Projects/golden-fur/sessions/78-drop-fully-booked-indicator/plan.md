---
title: Remove the "fully booked" pop-up from the new-booking flow
date: 2026-08-31
tags: [session-plan, golden-fur]
project: golden-fur
session: 78-drop-fully-booked-indicator
branch: fix/drop-fully-booked-indicator
---

# 78 — Remove the "fully booked" pop-up from the new-booking flow

## What you asked for

Stop showing a "this looks fully booked" warning while a customer (or a
receptionist) is making a new booking, because it fires when it shouldn't.

> Remove the fully booked indicator when starting a new booking:
>
> - I believe this runs when all staff are selected in bookings
> - EVEN THOUGH, they're scheduled on different dates
> - This does not mean that on X date, X staff are unavailable
> - Either drop how fully booked works or rewire its functionality

## What this part of the app does today

**The new-booking flow** is the multi-step wizard at `/portal/book` (a
customer booking from home) and `/staff/bookings/new` (a receptionist
booking on someone's behalf). One of its steps is the **availability
step**, where you pick a date and a time.

The date/time control on that step is a component called the **Slot
Picker**. It asks the server for that one day's list of candidate
appointment times and marks each one _available_ or _Unavailable_. For a
Grooming or Veterinary booking, a time is "available" only if at least one
staff member of the right role is free for that exact time window — the
server works this out with a database function called
`get_staff_availability`.

On top of that, the page had a **"fully booked" pre-check**: every time the
Slot Picker finished loading a day, it told the page "this day has N
candidate times, and X of them are open". If a day had candidate times but
_none_ were open, the page popped up a blocking dialog — **"This looks
fully booked"** — and then asked the server to search the next **14 days**
for the first open slot, so it could say "the earliest opening we found
is…".

## What's wrong / what's missing

The pop-up is a second, redundant guess layered on top of information the
Slot Picker already shows correctly. The Slot Picker itself, on any day
with no open times, already prints **"No open slots on this date. Try
another date above."** right in the calendar — accurate, per-date, no
modal.

The pop-up, by contrast:

- **Blocks the flow.** It's a full-screen dialog the user has to dismiss.
- **Reads as a false alarm.** It says "fully booked" for what is often just
  a busy day, or a day when the branch's only groomer is on approved leave
  — neither of which is the customer's problem to be scared about.
- **Is expensive.** Each time it fires it runs up to 14 more server
  round-trips to find the next open day.

The date-scoping itself is correct — `get_staff_availability` only counts a
staff member's bookings that _overlap the requested time window_, so a
booking on a different date genuinely doesn't count against today. But the
pop-up's _behaviour_ (a scary blocking claim) is what the request is
about, and the simplest, safest fix is to remove it rather than keep
tuning a heuristic.

## What we're going to change

Delete the "fully booked" pre-check end to end — the pop-up and everything
that existed only to feed it.

1. **Remove the pop-up and its state from the booking wizard** — _Which
   files:_ `client/src/features/booking/pages/CustomerBookingFlowPage/CustomerBookingFlowPage.tsx`
   (and its `.module.css`) — _Why:_ the `fullyBookedNotice` /
   `isCheckingAvailability` state, the `handleSlotAvailabilityChange`
   handler, the `getNextAvailableSlot` call, the modal JSX, and the
   "Checking availability…" button label all only ever served this
   feature.
2. **Remove the Slot Picker's `onAvailabilityChange` prop** — _Which
   files:_ `client/src/features/booking/components/SlotPicker/SlotPicker.tsx`
   — _Why:_ the booking wizard was its only caller; with the pop-up gone it
   reports to nobody.
3. **Remove the client API call** — _Which files:_
   `client/src/features/booking/api/booking.api.ts` — _Why:_
   `getNextAvailableSlot` (and its request/response types) called the
   dead endpoint.
4. **Remove the server endpoint and its service** — _Which files:_
   `server/src/features/booking/booking.routes.ts` (the
   `GET /bookings/availability/next-slot` route),
   `booking.controller.ts` (`nextAvailableSlotController`),
   `services/availability.service.ts` (`findNextAvailableSlot` +
   `DEFAULT_LOOKAHEAD_DAYS` + its two interfaces),
   `modules/validators/booking.validator.ts`
   (`nextAvailableSlotQueryValidator`) — _Why:_ nothing else calls any of
   it.
5. **Update the tests** that exercised the removed behaviour, in the two
   client spec files.

Nothing that _shows real availability_ changes — the Slot Picker's own
per-slot "Unavailable" marks and its "No open slots on this date" message
are untouched.

## Words you might not know

- **component** — a reusable piece of UI in React (the framework this app's
  front end is built with). The Slot Picker is one component.
- **prop** — an input you pass into a React component, like a function
  argument. `onAvailabilityChange` was a prop.
- **endpoint / route** — a URL the front end calls to get or change data on
  the server (`GET /bookings/availability/next-slot`).
- **validator** — a small schema that checks an incoming request's shape
  before the server acts on it. Written with a library called Zod here.
- **RPC / database function** — code that runs _inside_ the database.
  `get_staff_availability` is one; it decides which staff are free for a
  time window.
- **modal / dialog** — a pop-up box that sits on top of the page and
  usually blocks interaction with everything behind it until you close it.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.

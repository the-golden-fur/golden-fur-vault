---
title: Notify a customer when another customer's downpayment beats them to the same slot
date: 2026-09-11
tags: [session-plan, golden-fur]
project: golden-fur
session: 83-slot-conflict-notifications
branch: staged on dev
---

# 83 — Notify a customer when another customer's downpayment beats them to the same slot

## What you asked for

Let two customers pencil-book the same date/time/staff/cage slot while neither has paid their downpayment yet, and when one of them pays first, tell the other one — in their notifications and with a popup the moment they open their dashboard — that their booking needs a new slot, with a working link to the actual booking.

> When making another booking, after an online booking was made by another customer, I can no longer choose the date/time slots he chosen (even though downpayment was still not paid). As a customer, I want to be able to select the same date time, staff/cage slots as a customer who DID NOT YET pay his downpayment for his online booking. Should be able to select the same slots (date time, preferred staff, etc.) if downpayment is still not paid (unconfirmed booking status). If one of the two customers were able to pay their downpayment first, notify the other customer to adjust his booking date time, staff or cage (e.g. tell them that the selected booking time is currently unavailable, please update your booking details). As a customer who failed to pay his downpayment before another customer, I want to be notified that my chosen slot for X booking is no longer available, and I want to be prompted immediately when I open into my dashboard to adjust them. If there are multiple bookings where I failed to pay my downpayment in time, I want you to list all of them in the popup modal, and record it in my notifications. I want the list items to be linked to the actual booking record.

(Verbatim match confirmed against `Projects/golden-fur/shared/context/Architectural-Change-History.pdf`, page 5, "In Progress" list, owner: Matthew.)

## What this part of the app does today

A few terms first, then the current behavior.

- **Booking** — one row in the app's `bookings` table. It covers all four service types (Grooming, Hotel, Daycare, Veterinary) — there is only one `bookings` table, not four.
- **Downpayment** — a partial payment (e.g. 50%) a customer can pay online instead of paying in full, to hold a Grooming/Hotel/Daycare/Veterinary appointment.
- **Pencil booking** — the app's own term (in code comments) for an online booking that still owes its downpayment. Its `status` is `'Pending'` and `payment_status` is `'Pending'`. This is what the request calls "unconfirmed."
- **PayMongo** — the payment provider (GCash/Maya). When a customer pays, PayMongo calls back to the app's server (a **webhook**, an HTTP request the payment provider sends automatically) to say "this payment succeeded."
- **Capacity check** — the app's logic that decides whether a given date/time (plus staff, for Grooming/Veterinary, or cage size, for Hotel/Daycare) still has room. It lives in `server/src/features/booking/services/capacity.service.ts`.

**The "don't block an unpaid slot" behavior already exists in the code**, added in a batch of migrations from 20260829 (code comments call it "advisor addendum A3/A4"). Every place that counts how full a slot is — the Slot Picker's availability endpoint, the Staff Picker, the pre-booking capacity check, the post-booking race re-check — explicitly skips any booking that is still `Pending` + unpaid + downpayment-required. That skip is one shared filter, `SLOT_HOLD_PAID_OR_FILTER` (`server/src/features/booking/booking.types.ts:128`), used consistently in `capacity.service.ts`, `staffPicker.service.ts`, and the `get_staff_availability` Postgres function. In plain terms: **today, two different customers can already both pencil-book the same date/time/staff/cage, as long as neither has paid.** A code comment at `server/src/features/booking/services/booking.service.ts:983-986` says this explicitly: "multiple customers may pencil-book the same slot; whoever pays first reserves it."

What does **not** exist yet: anything that reacts when one of those two customers actually pays. Today, `applyFirstBookingPaymentSideEffects` (`booking.service.ts:2035`) — the function both the PayMongo webhook and the cashier's "mark as paid" screen call after a payment settles — only re-checks and confirms the *paying* customer's own booking. It never looks at whether some *other* still-unpaid pencil booking was quietly counting on that same slot. That other customer finds out only if and when they themselves try to pay (they'd get a "that slot filled up" error at that point) — nothing tells them proactively, nothing shows on their dashboard, and nothing is recorded in their notifications.

## What's wrong / what's missing

1. **Before doing anything else: re-confirm the reported symptom still reproduces.** The code strongly suggests the "I can no longer choose that slot" bug is already fixed by the existing `SLOT_HOLD_PAID_OR_FILTER` work. See "How you'll know it worked" step 1 — do this first. If it's already fixed, skip straight to building the notification feature below (steps 2 onward); don't spend time re-fixing something that isn't broken. If it still reproduces, that means there's a leftover code path the migrations missed (most likely candidate per this session's research: `resolveStaffAssignment`, the Grooming/Veterinary staff-assignment step during booking creation, which wasn't checked in this pass) — flag it back before continuing.
2. When customer A pays their downpayment and wins a slot, customer B's still-pending booking for the same slot is left untouched — no flag on the booking, no notification, nothing on B's dashboard.
3. There's no way today to mark a booking as "needs the customer to pick a new slot."
4. The notifications table has a fixed list of notification types (a Postgres enum), and none of them mean "your slot was taken." A new one is needed.
5. The customer dashboard (the Customer Portal home page, `/portal`) has no "something needs your attention" popup at all today — nothing like it exists yet for customers (staff have an equivalent pattern for MFA setup, which this plan reuses as a model).
6. The notification bell/list already stores a link back to the booking that triggered it (`related_booking_id`), but nothing in the app actually uses that link to navigate anywhere yet — clicking a notification today only marks it read.
7. Customers don't have a page at a URL like `/portal/bookings/123` — viewing a booking's details on the customer side opens a modal instead, from the existing "My Bookings" page. Any new "link to the booking" has to open that same modal, not a page that doesn't exist.

## What we're going to change

1. **Add two new columns to `bookings`**: `slot_conflict_at` (a timestamp, null unless the booking currently needs a new slot) and `conflict_notice` (a short text explanation to show the customer). _Which files:_ a new migration under `supabase/migrations/`, following the existing `bookings` column-adding migrations (e.g. `20260829147_m03_bookings_downpayment_due_at.sql`) as the template. _Why:_ we need somewhere durable to mark "this pencil booking just lost its slot" so it survives page reloads and can be queried later, without touching `status` (the booking stays `Pending` — the customer is meant to edit it, not have it auto-cancelled).

2. **Add one new notification type**: `booking_slot_conflict`, added to the `notification_event_type` Postgres enum. _Which files:_ a new migration that does `ALTER TYPE public.notification_event_type ADD VALUE 'booking_slot_conflict'` (must be its own migration — Postgres won't let a value be used in the same transaction it's added in — following the same pattern as the existing `staff_assigned`/`message_received` additions), plus mirroring the new value into the `NOTIFICATION_EVENT_TYPES` array in both `server/src/features/notifications/notifications.types.ts` and its client-side counterpart. _Why:_ the notifications table's `event_type` column is enum-backed; there's no free-text option.

3. **Detect "who just lost their slot" and flag them, right when a payment settles.** _Which files:_
   - `server/src/features/booking/services/capacity.service.ts` — add a small helper that finds other bookings competing for the same slot: same branch, same service category, still `Pending`/unpaid/downpayment-required, overlapping the paid booking's date/time window, excluding the paid booking itself. (For Grooming/Veterinary, narrow this to bookings that wanted the *same* staff member; for Hotel, narrow it to the *same* pet weight-class/cage-size category — reuse the existing `filterSameSizeRows` helper for that; Daycare needs no extra narrowing, since its capacity is a shared per-branch session count.)
   - `server/src/features/booking/services/booking.service.ts` — add an orchestrator function (e.g. `flagSlotConflictsForOthers`) that takes the just-paid booking, calls the new helper above to get the candidate list, and for each candidate re-runs the **existing, already-battle-tested** `checkCapacity(...)` function (`capacity.service.ts:213`) as if that candidate were the one trying to submit/pay right now. If `checkCapacity` says "not available," that candidate just lost the race — set its new `slot_conflict_at`/`conflict_notice` columns and send it a notification (next step). This deliberately reuses `checkCapacity` rather than inventing new capacity math, so the "did this candidate actually lose?" answer is guaranteed consistent with every other capacity decision in the app.
   - Call `flagSlotConflictsForOthers` from inside `applyFirstBookingPaymentSideEffects` (`booking.service.ts:2035`), right after the paying booking's own capacity re-check succeeds (after line ~2076). Wrap it the same way the existing confirmation-notification code right below it is wrapped — in a try/catch that logs but never blocks or fails the payment itself.
   - `server/src/features/booking/services/bookingNotifications.service.ts` — add a new sender, `sendSlotConflictNotification(booking, reason)`, following the exact shape of the existing `sendBookingConfirmedNotification`/`sendBookingRescheduledNotification` functions in that file: sets `relatedBookingId: booking.id`, uses the new `booking_slot_conflict` event type, and writes a message like "Your Grooming booking for Max on Sep 11, 2026 3:00 PM is no longer available — another customer's payment claimed that staff slot first. Please update your booking's date, time, or staff."

4. **Let the customer clear the flag by fixing their booking.** The app already has a working "customer edits their own pending booking's date/time/staff" flow — `POST /bookings/:id/reschedule`, in `server/src/features/booking/services/reschedule.service.ts`. Add one small change there: on a successful reschedule, clear `slot_conflict_at`/`conflict_notice` back to null. _Why:_ once the customer has picked a new slot (which the reschedule endpoint already re-validates for capacity on its own), the warning no longer applies. Note: the reschedule endpoint currently does not accept a cage-preference change (only creation does) — if a Hotel/Daycare customer needs to change their *cage size preference*, not just date/time, that field needs to be added to `rescheduleBookingValidator` in `server/src/features/booking/modules/validators/booking.validator.ts` as part of this same change, since the request explicitly asks for "adjust his booking date time, staff **or cage**."

5. **New endpoint: "give me my own conflicted bookings."** _Which files:_ `server/src/features/booking/booking.service.ts` (a small `listConflictedBookingsForCustomer(customerId)` query — bookings where `customer_id` = the requester, `status = 'Pending'`, `slot_conflict_at is not null`), a controller function, and a route (e.g. `GET /bookings/conflicts/mine`) registered in `server/src/features/booking/booking.routes.ts` next to the existing customer-scoped routes, customer-role only. _Why:_ the dashboard popup (next step) needs one cheap call that returns exactly "what do I need to fix," not the customer's entire booking history filtered client-side.

6. **The dashboard popup.** _Which files:_
   - `client/src/features/booking/api/booking.api.ts` — add `listMyConflictedBookings(accessToken)` calling the new endpoint.
   - A new modal component (e.g. `client/src/features/customers/components/SlotConflictModal/SlotConflictModal.tsx`) that lists every conflicted booking (pet, service, the date/time that's now unavailable, the `conflict_notice` text), each row linking to that booking.
   - `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.tsx` — the Customer Portal home page (what a customer lands on at `/portal`, right after logging in) — fetch the conflict list on page load (alongside the profile fetch it already does) and render the new modal, open by default, whenever the list isn't empty. Model this on how `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` already always-mounts an `MfaSetupModal` driven by a boolean computed from a mount-time fetch — same shape, customer side.
   - Each list item needs to "link to the actual booking record." Customers don't have a `/portal/bookings/:id` page — the existing "My Bookings" page (`client/src/features/booking/pages/CustomerBookingsPage/CustomerBookingsPage.tsx`) opens a `BookingDetailsModal` from in-page state instead. Add the same `?open=<bookingId>` query-param pattern that `client/src/pages/NotificationsPage/NotificationsPage.tsx` already uses (see its `openNotification` handling) to `CustomerBookingsPage.tsx`, so a link to `/portal/bookings?open=<id>` auto-opens that booking's details on arrival. Point both the new modal's list items and the notification bell/list's click handler (which currently ignores `related_booking_id` entirely — see item 7 below) at this same URL pattern.

7. **Make notification clicks that reference a booking actually navigate there.** _Which files:_ `client/src/features/notifications/components/NotificationList/NotificationList.tsx` (and/or wherever its `onSelect` is wired in `NotificationBell.tsx`/`NotificationDropdown.tsx`) — when a clicked notification has a `related_booking_id`, navigate to `/portal/bookings?open=<id>` (for a customer) in addition to marking it read, instead of only marking it read. This benefits the new `booking_slot_conflict` notifications immediately, and quietly fixes the same dead link for every other existing booking-related notification type too (confirmed, rescheduled, etc.) as a side effect.

## Words you might not know

- **Migration** — a small SQL file that changes the database's structure (adds a column, a table, etc.). Kept forever in `supabase/migrations/` so every environment (your laptop, staging, production) can replay the exact same history.
- **Enum** — a database column type restricted to a fixed list of allowed text values (e.g. a booking's `status` can only ever be `'Pending'`, `'In Progress'`, `'Completed'`, `'Cancelled'`, or `'No-show'` — nothing else). Postgres enums can only grow (new values added), never shrink, without a much bigger migration.
- **Webhook** — an HTTP request one server sends to another automatically when something happens, instead of the second server having to repeatedly ask "did it happen yet?" PayMongo sends golden-fur's server a webhook the moment a payment succeeds.
- **RPC** — "remote procedure call": a database function the app's server calls directly (through Supabase) instead of writing raw SQL every time. `get_staff_availability` is one of these.
- **Race condition** — a bug/situation where the outcome depends on which of two things happens first, and both "racers" might briefly think they've succeeded before one of them is told otherwise. Two customers pencil-booking the same slot and then one paying first is exactly this.

## How you'll know it worked

See `testing/testing.md` for the full click-by-click checks (scenarios A–F
there map onto the numbered items below). Implementation finished this
session; every automated test suite (server + client, full runs) is green
and both new migrations are applied to the dev database, but **no manual
click-through of the steps below has been done yet** — see testing.md's
"Manual test" header note and "Open items". At minimum, that file needs to
cover:

1. **Re-confirm step 1 above first**, before anything else: as two different customer accounts, both create an Online Grooming booking (or Hotel/Daycare/Veterinary) for the exact same branch/date/time/staff (or same weight-class cage window), leaving the downpayment unpaid on both. Today's code suggests the second booking should succeed without complaint. If it's blocked instead, stop and report that — it means there's a real leftover bug beyond what this plan covers.
2. Pay the downpayment on customer A's booking (sandbox PayMongo, or the cashier "mark as paid" screen). Confirm: customer B's booking now shows `slot_conflict_at` set (check via Postman/SQL), customer B has a new `booking_slot_conflict` notification with `related_booking_id` pointing at their booking, and customer A's own booking confirms normally with no side effects.
3. Log in as customer B, land on `/portal`. Confirm the popup appears immediately, unprompted, listing the conflicted booking with correct pet/date/time and the explanatory text.
4. Click the list item. Confirm it navigates to the "My Bookings" page and opens that exact booking's details.
5. Reschedule that booking to a genuinely free slot. Confirm `slot_conflict_at` clears and the dashboard popup no longer appears on the next login.
6. Repeat with a second simultaneously-conflicted booking for the same customer B, to confirm the popup lists multiple bookings, not just one.
7. Click the same-shaped notification from the bell/dropdown (not the dashboard popup) and confirm it also navigates to the booking.

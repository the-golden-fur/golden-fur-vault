# Issue #98 Verification: wire booking_confirmed, booking_rescheduled, booking_cancelled

**Issue:** #98 — feat(notification): wire booking_confirmed, booking_rescheduled, booking_cancelled
**Owner:** Matthew
**Branch:** `feat/notification-booking-events`
**Base:** `dev`
**Depends on:** #97; Sprint 5 Epic B #91 (cancellation_logs writes) merged
**Sprint:** Sprint 6 Epic A — M11 Notification

## Overview

Wires the three booking-lifecycle events for real. `booking_confirmed` replaces the old `sendBookingCreatedNotificationStub()` console.info call; `booking_rescheduled` and `booking_cancelled` are net-new call sites (no stub existed for either).

### Deviations from the Guide, flagged for the reviewer

- **Sprint 5 Epic B landed mid-branch.** The Guide's Handoff State assumed Epic B (`cancellation_logs`, credit issuance) was already merged before this epic started. When work on this issue began, it was not — `cancellation.service.ts` still carried a `TODO(Sprint 5, M09/M10)` marker and no `cancellation_logs` table existed. Epic B (#88-#95) merged to `dev` (`140a0c4`) while this issue was in progress; the notification wiring below was written against the real, now-merged `cancellation.service.ts` (which writes a real `cancellation_logs` row and calls `issueCredit()`), not the stale stub. `booking_cancelled`'s notification is positioned immediately after that credit-issuance block, reading its actual `creditIssued`/`downpayment` outcome — matching the Guide's original intent exactly, once the dependency was actually available.
- **Extracted to `bookingNotifications.service.ts`.** All three senders (`sendBookingConfirmedNotification`, `sendBookingRescheduledNotification`, `sendBookingCancelledNotification`) live in one new module rather than inline in each of `booking.service.ts`/`reschedule.service.ts`/`cancellation.service.ts`. This is a testability-driven choice: each function does 2-4 extra Supabase lookups (customer email, branch/staff name) that the pre-existing unit tests for those three services have no reason to model in their sequential mock queues. Extracting lets those tests mock the sender wholesale (one `vi.mock` line) instead of re-deriving queue offsets across ~20 existing test cases.

## What Changed

- **Added** `server/src/features/booking/services/bookingNotifications.service.ts` — the three senders above.
- **Modified** `server/src/features/booking/services/booking.service.ts` — `sendBookingCreatedNotificationStub()` deleted; `createBooking()` now calls `sendBookingConfirmedNotification(booking)`.
- **Modified** `server/src/features/booking/services/reschedule.service.ts` — `rescheduleBooking()` calls `sendBookingRescheduledNotification(booking, updated)` after the existing `writeCancellationLog()` call.
- **Modified** `server/src/features/booking/services/cancellation.service.ts` — `cancelBooking()` calls `sendBookingCancelledNotification(...)` immediately after the credit-issuance block, passing the real `noticePeriodMet`/`policyViolation`/`creditAmount` outcome.
- **Modified** `server/src/features/booking/services/booking.service.spec.ts`, `reschedule.service.spec.ts`, `cancellation.service.spec.ts`, `booking.integration.spec.ts` — added `vi.mock('./bookingNotifications.service.ts', ...)` so pre-existing tests are unaffected by the new Supabase calls.

## Acceptance Criteria Map

| AC                                                                                                    | Automated                                                                                                                                          | Manual            |
| ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 booking creation produces email + in-app notification with assigned staff name                   | `booking.service.spec.ts` mocks the sender and asserts booking creation still succeeds unchanged; sender's own staff-name lookup verified manually | Section D, step 2 |
| AC-2 reschedule confirmation reports old + new schedule                                               | same mocking pattern; manual step verifies message content                                                                                         | step 3            |
| AC-3 cancellation message reflects the cancellation_logs outcome (credit issued/amount, or forfeited) | `cancellation.service.spec.ts` (Epic B) already covers `credit_issued` computation; this issue's sender consumes that same value                   | step 4            |
| AC-4 none of the three original endpoints changes its response shape or fails because of this issue   | full server suite: 734/734 passing                                                                                                                 | —                 |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/booking
```

Expected: typecheck clean; all booking suites pass, including `booking.integration.spec.ts`'s HTTP-surface tests for create/reschedule/cancel.

## Manual Verification

### Prerequisites

`npm run dev` in `server/`; a seeded customer with a real `account_email`; `RESEND_API_KEY` configured.

### D. Steps

1. `supabase db reset` (migrations through `101` applied). Seed a Grooming booking with an assigned staff member.
2. Create the booking via `POST /bookings` — confirm both an email (Resend dashboard) and `select * from notifications where event_type = 'booking_confirmed' order by created_at desc limit 1;` show the assigned staff's `display_name` in `message`.
3. `POST /bookings/:id/reschedule` with a new `scheduled_start`/`scheduled_end` — confirm the resulting notification's `message` names both the old and new date/time.
4. `POST /bookings/:id/cancel` on a Hotel booking with a downpayment, with enough notice to qualify for credit — confirm the notification message includes the issued credit amount; repeat with insufficient notice — confirm no credit line appears.

### E. Cleanup

None — seeded test bookings/notifications may be left in place or cleared via `supabase db reset` before the next verification pass.

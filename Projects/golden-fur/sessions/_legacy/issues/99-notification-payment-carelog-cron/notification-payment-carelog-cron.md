# Issue #99 Verification: wire payment_confirmed, care_log_completed; appointment_reminder CRON

**Issue:** #99 — feat(notification): wire payment_confirmed, care_log_completed; appointment_reminder CRON
**Owner:** Matthew
**Branch:** `feat/notification-payment-carelog-cron`
**Base:** `dev`
**Depends on:** #97; Sprint 5 Epic A #82 (transactions) merged; Sprint 4 Epic A #76 (care_log_entries) merged
**Sprint:** Sprint 6 Epic A — M11 Notification

## Overview

Wires the remaining three events: `payment_confirmed` (net-new, checkout), `care_log_completed` (replaces `fireCareLogCompletedEvent()` stub, same `notify_opt_in` gate), and `appointment_reminder` (genuinely new daily 8:00 AM in-process scheduler).

### Deviations from the Guide, flagged for the reviewer

- **`payment_confirmed` trigger field — needs reviewer confirmation before merge.** The Guide flags this as an open Spec Tension: Modules-Features names `transactions.payment_status = 'Fully Paid'`, but the "staff-queue-overhaul" custom change introduced an independent `bookings.payment_stage` field that may be the more current signal in practice. This issue implements the trigger against `transactions.payment_status = 'Fully Paid'`, per the Guide's own explicit assumption — **do not merge without reviewer sign-off on which field is authoritative.**
- **No new CRON dependency added.** The Guide's Prerequisites anticipated needing `node-cron` or equivalent. The app already has one working precedent for "no background job runner" — `maintenance/jobs/promoExpiry.job.ts`'s in-process `setTimeout` scheduler. `appointmentReminder.job.ts` mirrors that exact shape instead of introducing a new npm dependency.
- **Extracted `care_log_completed`'s sender** into `hotel/services/careLogNotifications.service.ts` (same testability rationale as #98's `bookingNotifications.service.ts`) — the pre-existing `careLogCompletion.service.spec.ts` mocks it wholesale rather than asserting on the now-removed `console.info` stub call.

## What Changed

- **Added** `server/src/features/notifications/services/appointmentReminder.job.ts` — `runAppointmentReminderJob()` (queries bookings with `scheduled_start` tomorrow and status Pending/In Progress) + `startAppointmentReminderScheduler()` (daily 8:00 AM `setTimeout` loop).
- **Added** `server/src/features/hotel/services/careLogNotifications.service.ts` — `sendCareLogCompletedNotification()`.
- **Modified** `server/src/features/hotel/services/careLogCompletion.service.ts` — `fireCareLogCompletedEvent()` deleted; `completeCareLogEntry()` calls the new sender, still gated on `hotel_stays.notify_opt_in` (query extended to select `pet_id` alongside it).
- **Modified** `server/src/features/billing/services/checkoutAggregation.service.ts` — `checkoutBooking()` calls the new payment_confirmed sender when the persisted transaction's `payment_status === 'Fully Paid'`.
- **Modified** `server/src/app.ts` — starts `startAppointmentReminderScheduler()` alongside the existing promo-expiry scheduler.
- **Modified** `server/src/features/hotel/services/careLogCompletion.service.spec.ts` — mocks `careLogNotifications.service.ts`; AC-3 test rewritten to assert the sender is called with the right args instead of `console.info`.

## Acceptance Criteria Map

| AC                                                                                                  | Automated                                                                                                 | Manual            |
| --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 a transaction reaching the confirmed trigger condition produces payment_confirmed, any channel | not yet unit-tested for the new call site (see Open Items)                                                | Section D, step 2 |
| AC-2 care_log_completed only fires when notify_opt_in is true, gating unchanged                     | `careLogCompletion.service.spec.ts` — both notify_opt_in branches covered                                 | step 3            |
| AC-3 CRON fires at 8:00 AM for bookings scheduled tomorrow only                                     | not yet unit-tested (see Open Items); logic verified by code inspection of `tomorrowRange()`              | step 4            |
| AC-4 a CRON run with zero matches completes without error, zero notifications                       | code inspection: `runAppointmentReminderJob` returns `bookings.length` (0) cleanly on an empty result set | step 4            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/hotel/services/careLogCompletion.service.spec.ts
npx vitest run src/features/billing/services/checkoutAggregation.service.ts 2>&1 || echo "no existing spec file for this service"
```

Expected: typecheck clean; `careLogCompletion.service.spec.ts` 6/6 passing.

## Manual Verification

### Prerequisites

`npm run dev` in `server/`; a Hotel booking with `notify_opt_in = true` and a checked-in stay with pending care log entries; a booking scheduled for tomorrow.

### D. Steps

1. **CONFIRM WITH THE REVIEWER** whether `transactions.payment_status` or `bookings.payment_stage` should actually drive `payment_confirmed` before treating this issue as done.
2. Complete a cashier checkout (`POST /billing/checkout`) that resolves to `payment_status = 'Fully Paid'` — confirm a `payment_confirmed` notification + email fires.
3. `PATCH /hotel/care-log-entry/:id/complete` on an entry belonging to a `notify_opt_in = true` stay — confirm a `care_log_completed` notification fires naming the pet; repeat on a `notify_opt_in = false` stay — confirm no notification fires but the entry is still marked complete.
4. Temporarily lower `RUN_HOUR`/`RUN_MINUTE` in `appointmentReminder.job.ts` (or call `runAppointmentReminderJob(new Date())` directly from a scratch script) against a booking scheduled exactly tomorrow — confirm one notification fires; run again with zero matching bookings — confirm it completes with no error and no notifications.

### E. Cleanup

Revert any temporary `RUN_HOUR`/`RUN_MINUTE` change made for step 4 testing before committing.

## Open Items

- No dedicated unit test suite for `appointmentReminder.job.ts` or the new `payment_confirmed` call site in `checkoutAggregation.service.ts` was added in this pass. Recommended follow-up: mirror `promoExpiry.job.spec.ts`'s shape for the CRON, and extend `checkoutAggregation.service.spec.ts` (if one exists) for the payment_confirmed trigger — once the Spec Tension above is resolved.

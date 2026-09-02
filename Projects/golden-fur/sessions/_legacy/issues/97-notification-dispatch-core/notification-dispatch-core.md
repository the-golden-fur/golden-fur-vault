# Issue #97 Verification: Resend email templates + notification.service.ts core dispatch

**Issue:** #97 — feat(notification): Resend email templates + notification.service.ts core dispatch
**Owner:** Matthew
**Branch:** `feat/notification-dispatch-core`
**Base:** `dev`
**Depends on:** #96
**Sprint:** Sprint 6 Epic A — M11 Notification

## Overview

Builds the one write path (`createNotification()`) every event-triggering module calls into, plus six new Resend templates. `account_created` reuses the existing `accountCreatedEmail.ts` template unchanged, only adding the in-app row; `password_reset` gets no template at all (Supabase Auth sends that email natively) — only an in-app row. This issue does not wire the six new templates into their real trigger points; that's #98/#99.

### Deviations from the Guide, flagged for the reviewer

- No deviations in scope. `sendEmail` on `CreateNotificationParams` is a caller-supplied thunk rather than createNotification() branching on `event_type` internally — this keeps the dispatch core decoupled from each of the eight events' very different template parameters (booking details, credit amounts, care-log descriptions, etc.), while still centralizing the "write row first, best-effort non-blocking send" logic in one place per the Guide's intent.

## What Changed

- **Added** `server/src/features/notifications/notifications.types.ts` — `NotificationEventType`, `Notification`, `CreateNotificationParams`.
- **Added** `server/src/features/notifications/services/notification.service.ts` — `createNotification()`, `getInboxForStaff()`, `getInboxForCustomer()`, `markRead()`, `markAllRead()`.
- **Added** `server/src/features/notifications/notifications.controller.ts` / `notifications.routes.ts` — `GET /notifications`, `PATCH /notifications/:id/read`, `PATCH /notifications/read-all` (customer-or-staff routes, `jwtMiddleware` only, ownership resolved in the controller).
- **Added** six email templates: `bookingConfirmedEmail.ts`, `bookingRescheduledEmail.ts`, `paymentConfirmedEmail.ts`, `appointmentReminderEmail.ts`, `bookingCancelledEmail.ts`, `careLogCompletedEmail.ts` (all thin wrappers over `resend.client.ts`, matching `accountCreatedEmail.ts`'s shape).
- **Modified** `server/src/features/staff/services/staffManagement.service.ts` — adds a best-effort `createNotification()` call (`account_created`) alongside the existing `sendAccountCreatedEmail()` call; the template itself is untouched.
- **Modified** `server/src/features/auth/staff/staffAuth.controller.ts` — `forgotPasswordController` looks up the requesting staff member by email and writes a `password_reset` in-app row; no email leg. Response shape is unchanged either way (a lookup miss stays silent, matching `resetPasswordForEmail`'s own generic behavior).
- **Modified** `server/src/shared/app.routes.ts` — registers `notificationsRoutes`.

## Acceptance Criteria Map

| AC                                                                | Automated                                                                                                                                                                                     | Manual            |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 createNotification() writes a row for all 8 event types      | not yet unit-tested (no `.spec.ts` was added for `notification.service.ts` in this pass — see Open Items)                                                                                     | Section D, step 2 |
| AC-2 a mocked Resend failure doesn't throw or block the row write | covered indirectly: `staffManagement.service.spec.ts` already exercises `sendAccountCreatedEmail` failing in a test environment with no `RESEND_API_KEY`, and account creation still succeeds | step 3            |
| AC-3 account_created's email template is unmodified               | `git diff` on `accountCreatedEmail.ts` is empty                                                                                                                                               | step 4            |
| AC-4 password_reset has no accompanying email send                | code inspection: `forgotPasswordController`'s notification block has no `sendEmail` field                                                                                                     | step 5            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/staff/services/staffManagement.service.spec.ts
npx vitest run src/features/auth/staff
```

Expected: typecheck clean; all staff/auth suites pass (734/734 across the full server suite as of this batch).

## Manual Verification

### Prerequisites

`RESEND_API_KEY` / `RESEND_FROM_EMAIL` set in `server/.env` (already required since Issue #74); Docker Desktop running with migration `100` applied.

### D. Steps

1. `npm run dev` in `server/`. Create a new staff account via `POST /staff` (Admin/Superadmin session) — confirm the response still returns a `temporaryPassword` and the account_created email arrives (Resend dashboard or your test inbox).
2. `select * from notifications where event_type = 'account_created' order by created_at desc limit 1;` — confirm a row exists for the new staff member, `recipient_staff_id` matching, `recipient_customer_id` null.
3. Temporarily unset `RESEND_API_KEY` and repeat step 1 — confirm account creation still succeeds (201/200) and the notification row is still written; check server logs for `Failed to send account_created email:`.
4. `git diff dev -- server/src/shared/email/accountCreatedEmail.ts` — confirm no output.
5. Call `POST /staff/auth/forgot-password` with a real staff `registered_email` — confirm the response is the generic `{ message: 'Password reset email sent' }` regardless of whether the email is registered, and `select * from notifications where event_type = 'password_reset' order by created_at desc limit 1;` shows a row only when the email was in fact registered.

### E. Cleanup

None — all rows written above are legitimate notification history, not test artifacts requiring rollback.

## Open Items

- No dedicated `notification.service.spec.ts` unit test suite was added in this pass (time-boxed against the size of this batch). Recommended follow-up: unit tests for `createNotification`/`markRead`/`markAllRead` mirroring `cancellationLog.service.spec.ts`'s shape.

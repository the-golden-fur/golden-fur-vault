# Issue #96 Verification: notifications table + notification_event_type enum

**Issue:** #96 — chore(db): notifications table + notification_event_type enum
**Owner:** Matthew
**Branch:** `chore/notifications-schema`
**Base:** `dev`
**Depends on:** Sprint 1 (staff_profiles, customer_profiles); Sprint 2 Epic B (bookings)
**Sprint:** Sprint 6 Epic A — M11 Notification

## Overview

Schema-only issue: creates `notification_event_type` (8 values) and `notifications` from scratch, correcting a stale "Merged" tag in Modules-Overview's DB Entities Inventory — neither existed anywhere in `supabase/migrations/` before this issue (confirmed by reading `booking.service.ts`'s `sendBookingCreatedNotificationStub()` and `careLogCompletion.service.ts`'s `fireCareLogCompletedEvent()`, both explicit `TODO(Sprint 6, M11)` stubs prior to this epic).

### Deviations from the Guide, flagged for the reviewer

- **Migration numbering, twice over.** The Guide assumed a latest of `20260805097`; the actual latest when this branch started was `20260804093`. Mid-branch, Sprint 5 Epic B (#88-#95) merged to `dev` and took `094-099` for itself. This migration is therefore renumbered to `20260805100` (not `098` as the Guide planned, nor `094` as a naive first renumbering would have produced).
- Everything else (columns, CHECK constraint, RLS shape) matches the Design sheet exactly.

## What Changed

- **Added** `supabase/migrations/20260805100_m11_create_notifications_schema.sql` — `notification_event_type` enum (8 values); `notifications` table with `recipient_staff_id`/`recipient_customer_id` (exactly-one-of via `CHECK (num_nonnulls(...) = 1)`), `event_type`, `title`, `message`, `related_booking_id`, `is_read`, `created_at`; RLS (staff/customer SELECT and UPDATE scoped to their own recipient column, no INSERT policy for either role).

## Acceptance Criteria Map

| AC                                                                              | Automated                                                                                           | Manual            |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 table + enum exist with every column/value                                 | schema exists at migration-apply time; exercised indirectly by #97's `notification.service.spec.ts` | Section D, step 2 |
| AC-2 exactly-one-recipient CHECK enforced                                       | not exercised by vitest (DB-layer concern)                                                          | step 3            |
| AC-3 RLS restricts SELECT to own recipient; no INSERT policy for staff/customer | not exercised by vitest                                                                             | step 4            |
| AC-4 FKs to staff_profiles/customer_profiles/bookings valid                     | not exercised by vitest                                                                             | step 5            |

## Automated Verification

From `server/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/notifications
```

Expected: typecheck clean; #97's `notification.service.ts` unit tests (once added — see #97's doc) exercise the exact insert shape this table must accept.

## Manual Verification

### Prerequisites

Docker Desktop running; Supabase CLI available in `PATH`.

### D. Steps

1. Run `supabase db reset`. Confirm migration `100` applies cleanly after `099` (Sprint 5 Epic B's last migration).
2. In the Supabase SQL Editor: `select column_name, data_type from information_schema.columns where table_name = 'notifications' order by ordinal_position;` — confirm all 8 columns are present, and `event_type`'s type is `notification_event_type`.
3. `insert into notifications (recipient_staff_id, recipient_customer_id, event_type, title, message) values ('<a real staff id>', '<a real customer id>', 'booking_confirmed', 'x', 'y');` (via the service-role SQL Editor) — confirm it's rejected (both recipients set). Retry with both `null` — confirm it's also rejected.
4. As a staff session, `select * from notifications;` — confirm only rows where `recipient_staff_id = auth.uid()` are visible. Attempt a raw `insert into notifications (...) values (...)` as that same staff session — confirm RLS rejects it (no INSERT policy for `authenticated`).
5. Attempt an insert with a non-existent `recipient_staff_id` or `related_booking_id` via the service-role client — confirm the FK constraint rejects it.

### E. Cleanup

Roll back any manual test row inserted in step 3/5 with `delete from notifications where id = '<the test row's id>';` if an insert unexpectedly succeeded (it shouldn't).

# Issue #101 Verification: customer portal notification tab UI

**Issue:** #101 — feat(notification): customer portal notification tab UI
**Owner:** James
**Branch:** `feat/customer-notification-tab`
**Base:** `dev`
**Depends on:** #96 and #100 merged
**Sprint:** Sprint 6 Epic A — M11 Notification

## Overview

Adds a Notifications tab to the customer portal, rendering through the same `NotificationList` component #100's staff dropdown uses, scoped to the customer's own inbox.

### Deviations from the Guide, flagged for the reviewer

- **`CustomerPortalPage` has no pre-existing tab mechanism** (it's a plain welcome message + Sprint 5 Epic B's credit-balance cards, not a tabbed page). Rather than inventing a new route/page not in the Guide's Files list, a lightweight `Overview` / `Notifications` tab toggle (local `useState`, no router change) was added directly inside `CustomerPortalPage.tsx` — matching the Guide's literal "gains a Notifications tab" wording and its single-file Files-sheet entry for this issue.
- The shared `GET /notifications` endpoint resolves the caller's own inbox from their JWT identity (staff vs. customer), not a query parameter — so this page needs no customer-id plumbing at all; it's the same call `NotificationBell` makes.

## What Changed

- **Modified** `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.tsx` — tab toggle (`Overview` / `Notifications`), notification fetch + optimistic mark-read/mark-all-read state, renders `NotificationList`.
- **Modified** `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.module.css` — tab styles, mark-all-read button.
- **Modified** `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.spec.ts` — mocks `notifications.api.ts` (needed regardless of this issue, since the page now calls it unconditionally on mount).

## Acceptance Criteria Map

| AC                                                                    | Automated                                                                                                         | Manual            |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ----------------- |
| AC-1 tab shows every notification for that customer, newest-first     | `CustomerPortalPage.spec.ts` (4/4 passing, including the pre-existing #95 credit tests unaffected by this change) | Section D, step 2 |
| AC-2 mark-all-as-read clears the badge the same way it does for staff | code inspection: identical `markAllNotificationsRead` call + optimistic state pattern as `NotificationBell`       | step 3            |
| AC-3 a customer cannot see another customer's notifications           | enforced server-side (RLS + `recipient_customer_id` scoping in `notification.service.ts`, #96/#97)                | step 4            |

## Automated Verification

From `client/`:

```powershell
npx tsc --noEmit
npx vitest run src/features/customers/pages/CustomerPortalPage
```

Expected: typecheck clean; 4/4 tests pass, no unhandled rejections.

## Manual Verification

### Prerequisites

`npm run dev` in both `client/` and `server/`; a customer login with at least one seeded notification row (`insert into notifications (recipient_customer_id, event_type, title, message) values ('<customer id>', 'booking_confirmed', 'Test', 'Test notification');`).

### D. Steps

1. Log in as that customer, land on `/portal`.
2. Click the "Notifications" tab — confirm the seeded row appears, newest-first, with an unread count next to the tab label.
3. Click the row to mark it read, then "Mark all as read" — confirm the count clears to zero.
4. Log in as a _different_ customer with no notifications of their own — confirm their Notifications tab is empty (does not show the first customer's row).

### E. Cleanup

`delete from notifications where title = 'Test';`

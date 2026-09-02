# Issue #100 Verification: staff notification bell + dropdown UI

**Issue:** #100 — feat(notification): staff notification bell + dropdown UI
**Owner:** James
**Branch:** `feat/staff-notification-bell`
**Base:** `dev`
**Depends on:** #96
**Sprint:** Sprint 6 Epic A — M11 Notification

## Overview

Staff-facing bell icon in the Navbar with an unread-count badge, opening a dropdown listing notifications newest-first. Built against `#96`'s schema alone — `#97`'s real dispatch isn't required for the bell to show whatever rows already exist.

### Deviations from the Guide, flagged for the reviewer

- **`NotificationBell` slot lives on `Navbar`/`AppShell`, not a new layout component.** The Guide didn't specify exactly where the bell physically mounts. `Navbar`/`AppShell` are shared between the staff and customer shells (`role: 'staff' | 'customer'`); a new `notificationBell?: ReactNode` prop was added to both, populated only by `StaffAuthGuard` (customers get #101's sidebar tab instead, never a bell).
- No new hue: `--color-notification-unread-bg/-text` alias the existing amber tier exactly as specified in the Design sheet's Styles section (`#fbefd2`/`#8a6a1a` light, `#4d3413`/`#ffd27a` dark).

## What Changed

- **Added** `client/src/features/notifications/notifications.types.ts`, `api/notifications.api.ts`.
- **Added** `components/NotificationBell/NotificationBell.tsx` — unread badge, opens the dropdown, optimistic mark-read/mark-all-read local state updates.
- **Added** `components/NotificationDropdown/NotificationDropdown.tsx` — panel wrapper (heading + mark-all-as-read + `NotificationList`).
- **Added** `components/NotificationList/NotificationList.tsx` — shared list rendering, reused by #101's customer tab.
- **Modified** `client/src/shared/components/Navbar/Navbar.tsx`, `AppShell/AppShell.tsx` — new `notificationBell` slot.
- **Modified** `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` — passes `<NotificationBell accessToken={accessToken} />`.
- **Modified** `client/src/styles/tokens.css` — adds `--color-notification-unread-bg/-text` (light + dark).

## Acceptance Criteria Map

| AC                                                                                                     | Automated                                                                                          | Manual              |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | ------------------- |
| AC-1 bell shows correct unread count on load, updates immediately after a read action, no page refresh | `npx tsc --noEmit` confirms the optimistic-update state shape compiles; behavior verified manually | Section D, step 2-3 |
| AC-2 clicking the bell opens a dropdown listing notifications newest-first                             | server orders by `created_at desc` (`notification.service.ts`)                                     | step 2              |
| AC-3 clicking a row marks it read, unread count decrements by exactly one                              | code inspection: `handleSelect` patches local state + calls `markNotificationRead`                 | step 3              |
| AC-4 mark-all-as-read clears the badge to zero, marks every row read                                   | code inspection: `handleMarkAllRead` maps every item to `is_read: true`                            | step 4              |

## Automated Verification

From `client/`:

```powershell
npx tsc --noEmit
npx eslint src/features/notifications src/shared/components/Navbar src/shared/components/AppShell
```

Expected: both clean, no errors.

## Manual Verification

### Prerequisites

`npm run dev` in both `client/` and `server/`; a staff login with at least one seeded `notifications` row (insert directly via SQL Editor if #97/#98 haven't fired any real events yet: `insert into notifications (recipient_staff_id, event_type, title, message) values ('<staff id>', 'account_created', 'Test', 'Test notification');`).

### D. Steps

1. Log in as staff. Confirm the bell in the top navbar shows an unread-count badge matching the number of unread rows for that staff member.
2. Click the bell — confirm the dropdown opens, listing notifications newest-first.
3. Click an unread row — confirm it's visually marked read immediately (no refetch/flash) and the badge count decrements by one. Refresh the page — confirm the read state persisted (`select is_read from notifications where id = '<row id>';`).
4. Click "Mark all as read" — confirm the badge clears to zero and every row in the dropdown shows as read.

### E. Cleanup

Delete any manually-inserted test notification row from the Prerequisites step: `delete from notifications where title = 'Test';`.

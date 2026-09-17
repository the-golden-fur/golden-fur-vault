---
title: Notifications — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, notifications]
project: golden-fur
---

Notifications is the bell/inbox feature: a shared inbox row (and, where a
template exists, an email) that fires whenever something happens elsewhere in
the app — a booking is confirmed, a payment is recorded, a care log wraps up,
and so on. It's purely reactive — nothing in this feature originates an
event, it just reacts to one and respects the recipient's own email/in-app
preference toggles.

**Part of:** [[M11-notification]]

## Client-side (`client/src/features/notifications/`)

### components/

- **`NotificationBell/NotificationBell.tsx`** — The bell icon rendered in
  both the staff and customer portal headers. On mount it fetches the
  recipient's inbox via `listNotifications`, counts unread rows for the
  badge, and toggles the dropdown open/closed. Clicking a notification
  optimistically marks it read (updates local state immediately, then calls
  the API) and, if the notification carries a `related_booking_id`,
  navigates straight to that booking — staff go to
  `/staff/bookings/:id`, customers to `/portal/bookings?open=:id`. Which
  route prefix to use is inferred from the `notificationsHref` prop rather
  than a separate role prop.
- **`NotificationDropdown/NotificationDropdown.tsx`** — The panel the bell
  opens. Pure presentational wrapper around `NotificationList` plus a header
  with a "Mark all as read" button (disabled when unread count is 0) and a
  "View all" link to the full notifications page. Owns no fetch logic itself.
- **`NotificationList/NotificationList.tsx`** — The actual list-rendering
  component, shared by both the dropdown and the customer portal's full
  notifications page (so there's only one place that draws a notification
  row). Handles the loading/error/empty states, formats timestamps, and
  highlights unread rows with a dedicated CSS token pair. The caller (bell or
  portal page) owns the actual "mark read" API call — this component just
  calls `onSelect`.
- `*.module.css` files — plain CSS Modules styling (badge, panel layout,
  unread highlight color); no logic worth documenting per-file.

### api/

- **`api/notifications.api.ts`** — Thin fetch wrappers around the server's
  five REST endpoints: `listNotifications`, `markNotificationRead`,
  `markAllNotificationsRead`, `starNotification`, `deleteNotification`. All
  of them take the caller's access token and return a
  `{ data, error }` shape, never throwing.

### notifications.types.ts

- Client mirror of the server's event-type union and the `Notification`
  shape. Note this file currently lists 12 event types (it also has
  `booking_slot_conflict` and `spin_wheel_earned`, added after the module
  note's original 10), matching the server's `notifications.types.ts`.

## Server-side (`server/src/features/notifications/`)

### Controller & routes

- **`notifications.controller.ts`** — Five thin controllers
  (`listNotificationsController`, `markNotificationReadController`,
  `starNotificationController`, `deleteNotificationController`,
  `markAllNotificationsReadController`). Each resolves whether the requester
  is staff or a customer via `getStaffRoleOrNull`, then calls the matching
  service function scoped to that recipient id — there's no separate
  staff-only vs. customer-only route, ownership is resolved here instead.
- **`notifications.routes.ts`** — Mounts the five routes under
  `/notifications`, all behind `jwtMiddleware` only (no role gate, since
  ownership is resolved in the controller). `read-all` is registered before
  `/:id/read` so Express doesn't capture `"read-all"` as an `:id` param.

### Service

- **`services/notification.service.ts`** — The core of this feature.
  `createNotification()` is the single write path every other feature in the
  app calls into: it looks up the recipient's `notification_preferences`
  (on `staff_profiles` or `customer_profiles`, defaulting both channels to
  `true` if unset), inserts the `notifications` row only if `in_browser` is
  enabled, and — independently — invokes the caller-supplied `sendEmail()`
  thunk only if `email` is enabled. A failed email send is caught and logged,
  never rethrown; a failed row insert does throw, and callers are expected to
  wrap their own `createNotification()` call in a try/catch. Also exports
  `notifyStaffRoleAtBranch()` (fan out to every staff member with a given
  role at a branch — e.g. "notify the Receptionist"), the inbox readers
  (`getInboxForStaff`/`getInboxForCustomer`), and the mutation helpers
  (`markRead`, `setNotificationStarred`, `setNotificationDeleted`,
  `markAllRead`) — all scoped to the caller's own recipient column so one
  person's notification id can't touch another's row.
- **`services/appointmentReminder.job.ts`** — The 15-minute polling
  scheduler. `runAppointmentReminderJob()` queries Pending bookings due for
  a reminder within a 3-day lookahead, resolves each customer's configured
  offset (15 min/1h/3h/1 day/2 days, default 1 day), and claims each due
  booking with a conditional `UPDATE ... WHERE reminder_sent_at IS NULL` so
  concurrent ticks can't double-send. `startAppointmentReminderScheduler()`
  wraps it in a self-rescheduling `setTimeout` loop, logging and continuing
  on error rather than crashing the process.
- **`services/careLogDailyReport.job.ts`** — An hourly poller (only actually
  runs from 21:00 local time onward) that sends one end-of-day email per
  active hotel stay, bucketing that day's care-log tasks into
  Completed/Missed/Still scheduled. Uses an upsert-with-`ignoreDuplicates`
  claim on a `care_log_daily_reports` table (keyed by stay + date) so a
  server restart mid-evening doesn't produce duplicate summaries, and checks
  both a per-branch policy flag (`care_log_daily_report_enabled`) and the
  customer's own `care_log_completed` email preference via
  `isEmailNotificationEnabled()` before sending.

### Types & validators

- **`notifications.types.ts`** — `NOTIFICATION_EVENT_TYPES` (the 12-value
  enum mirror, with inline comments noting which migration added each of the
  four "custom change" additions past the original 8), the
  `NotificationPreferences`/`NotificationEventPreference` shapes used for the
  Settings > Preferences grid, the `REMINDER_OFFSET_MINUTES_OPTIONS` preset
  list, and `CreateNotificationParams`/`Notification` — the two shapes every
  other feature's notification call sites build against.

## How it connects

Every other feature that wants to notify someone imports
`createNotification()` (or `notifyStaffRoleAtBranch()`) from
`notification.service.ts` rather than writing to the `notifications` table
directly — booking confirm/reschedule/cancel, staff-assignment, payment
confirmation, care-log completion, account creation, and the messaging
feature's own `message_received` event all go through this one function. See
[[M11-01-event-triggered-notification-dispatch]] for the full dispatch flow
and [[M11-02-appointment-reminder-polling-sweep]] for the reminder job's
claim-then-send mechanics. The messaging feature (no M-code of its own — see
[[features/messaging/code/overview|the Messaging Code Guide]]) is a
*consumer* of this module: it calls `createNotification` with `eventType:
'message_received'` and a `relatedThreadId`, it doesn't provide the delivery
mechanism itself.

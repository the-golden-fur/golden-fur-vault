# 49 - Notifications Modal + Staff Assignment Alert

Two related asks:

1. On the notifications page, remove the inline "reading box" (the master-
   detail side panel used for message threads) - clicking any item (system
   notification or message thread) now opens it as a modal instead, with a
   "Fullscreen" button in the modal that switches the same content to a
   full-page view.
2. Notify a staff member (e.g. a groomer) when a customer picks them as
   their preferred staff for a booking.

---

## Important decisions made along the way

- **One unified "opened item" concept, two URL params**: the existing
  `?thread=<id>` param (drives the pre-existing thread-detail fetch effect,
  unchanged) now also drives the modal/full-page instead of the old side
  panel; a new `?open=<id>` param covers the same behavior for plain system
  notifications, which previously had no detail view at all beyond the list
  row's own preview text. A third param, `?view=full`, layers on top of
  either one to mean "show this as a full page, not a modal" - this is what
  the Fullscreen button sets. All three are cleared together when the modal
  is closed or the folder changes, and the URL stays shareable/bookmarkable
  either way (a `?open=<id>&view=full` link opens straight to that
  notification's full-page view).
- **System notifications already carried their full message** -
  `notification.message` was never truncated for the list row's preview, so
  the new modal/full-page detail view needed no new API call; it just
  renders `title`/`message`/timestamp/sender that were already being
  fetched.
- **`staff_assigned` fires only for an explicit customer pick, not
  auto-assignment**: `resolveStaffAssignment()` in `booking.service.ts`
  already distinguishes `preferenceType: 'specific'` (customer picked
  someone) from `'no_preference'` (auto-assigned to whoever's next
  eligible). Notifying the assignee on every auto-assigned booking would be
  noise - every eligible staff member is an equally arbitrary pick there -
  so the new notification only fires on `'specific'`.
- **Reused the existing `createNotification()` write path** - no new insert
  path, no Postgres trigger. `staff_assigned` is the 10th
  `notification_event_type` value, added the same way `message_received`
  was (its own migration, since Postgres forbids using an `ADD VALUE`
  enum value in the transaction that added it).

---

## 1. Database schema

**What changed:** a 10th `notification_event_type` enum value,
`staff_assigned`.

**Files:**
`supabase/migrations/20260819137_custom_notification_event_type_add_staff_assigned.sql`.

---

## 2. Server: staff assignment notification

**What changed:** new `sendStaffAssignedNotification(booking)` in
`bookingNotifications.service.ts`, same non-blocking try/catch shape as its
three siblings (`sendBookingConfirmedNotification`,
`sendBookingRescheduledNotification`, `sendBookingCancelledNotification`).
Looks up the customer's name and the pet's name for the message text, then
calls the existing `createNotification()` with `recipientStaffId:
booking.assigned_staff_id` and the new `staff_assigned` event type. Called
from `booking.service.ts`'s `createBooking()` right after
`sendBookingConfirmedNotification(booking)`, gated on
`staffResolution.preferenceType === 'specific'`. Also added to
`NOTIFICATION_EVENT_TYPES` (server + client mirror) and to the staff column
of `NotificationPreferencesGrid.tsx` so staff can toggle email/in-browser
for it from Settings > Preferences, same as every other event type.

**Files:**
`server/src/features/booking/services/bookingNotifications.service.ts` (+
`sendStaffAssignedNotification`),
`server/src/features/booking/services/booking.service.ts` (call site),
`server/src/features/notifications/notifications.types.ts` (+
`staff_assigned`),
`client/src/features/notifications/notifications.types.ts` (mirror),
`client/src/pages/SettingsPage/tabs/NotificationPreferencesGrid.tsx` (+
staff-facing toggle row).

**Verify manually:**

1. Apply the migration (see "Migrations" below).
2. As a customer, create a Grooming or Veterinary booking and explicitly
   pick a specific staff member in the staff picker (not "No preference").
3. Log in as that staff member - confirm a new "You were selected as
   preferred staff" notification appears in their bell/Inbox, naming the
   customer, the pet, and the scheduled date/time.
4. Create a second booking with "No preference" selected (or with the
   staff picker disabled) - confirm the auto-assigned staff member does
   **not** get a `staff_assigned` notification.
5. As that staff member, open Settings > Preferences - confirm "Customer
   selected you as preferred staff" appears as a togglable row with
   Email/In-browser switches, and that turning In-browser off suppresses
   the notification row on the next specific-preference booking (the email
   leg isn't wired for this event - no `sendEmail` thunk was passed - so
   only the in-browser toggle has an observable effect here).

---

## 3. Client: notifications page modal + fullscreen

**What changed:** `NotificationsPage.tsx`'s old two-column layout (list +
always-visible `ThreadDetail` side panel, side panel only ever populated
for message threads) is now a single-column list. Clicking any row - system
notification or message thread - opens a `Modal` (reusing the existing
generic `Modal` component, same one `ComposeModal` uses) showing that
item's full detail: system notifications render their title/message/
timestamp inline; message threads render the same `ThreadDetail` component
that used to live in the side panel, unchanged. The modal has a
"Fullscreen" button that swaps the same detail content into a full-page
view (own `<main>`, no list, no modal backdrop, with a Back button) driven
by a `?view=full` URL param, rather than growing a second, separate route.

**Files:**
`client/src/pages/NotificationsPage/NotificationsPage.tsx`,
`client/src/pages/NotificationsPage/NotificationsPage.module.css`.

**Verify manually:**

1. Open `/staff/notifications` (or `/portal/notifications` as a customer).
   Confirm the page is now a single list column - no side panel next to it.
2. Click a System-folder notification - confirm it opens as a modal
   showing the full title/message/timestamp, and that the row was marked
   read (same as before).
3. Click a Mail or Announcement item - confirm it opens as a modal showing
   the same thread history + reply box `ThreadDetail` always showed, and
   that replying from inside the modal still works and updates the list's
   preview/timestamp.
4. With either kind of item open in the modal, click "Fullscreen" - confirm
   the modal closes and the same content now fills the page (no list, no
   backdrop) with a "Back" button; clicking Back returns to the list with
   the item closed. Confirm the URL while fullscreen is bookmarkable
   (reload the page at that URL and confirm it reopens straight into the
   full-page view).
5. Close a modal via the X button and via clicking the backdrop - confirm
   both return to the plain list with nothing selected.

---

## Migrations

One migration: `20260819137_custom_notification_event_type_add_staff_assigned.sql`.
Must run on its own (not batched with any other statement in the same
transaction) - same constraint `message_received`'s migration documents.

- **With Supabase CLI access:** `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access:** Supabase Dashboard -> **SQL Editor** ->
  **New query** -> paste
  `notifications-modal-and-staff-assignment.sql` from this folder -> **Run**.
  Afterwards, confirm with:

  ```sql
  select exists (
    select 1 from pg_enum
    where enumlabel = 'staff_assigned'
      and enumtypid = 'public.notification_event_type'::regtype
  ) as has_staff_assigned_value;
  ```

  Should return `true`.

## Postman

Not applicable - this request added no new API routes (the notification
fires as a side effect of the existing `POST /bookings` create flow) and
touched no other testable endpoint.

## Test suites

- `server`: `npx tsc --noEmit` clean; full suite (`npm test`) - **863
  tests pass** (84 files), including the existing `booking.service`/
  `bookingNotifications` specs unchanged (no new unit specs added - the
  new `sendStaffAssignedNotification` mirrors its three already-covered
  siblings closely enough that live verification per the steps above was
  judged sufficient).
- `client`: `npx tsc --noEmit` clean; full suite (`npm test`) - **671
  tests pass** (136 files).

## Suggested branch name

`feat/notifications-modal-and-staff-assignment`

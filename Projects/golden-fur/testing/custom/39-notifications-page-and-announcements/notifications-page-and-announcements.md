# 39 - Notifications Page + Admin Announcements/Messaging

Two related asks:

1. A dedicated, expandable notifications page reachable from the navbar
   bell for both staff (`/staff/notifications`) and customers
   (`/portal/notifications`), instead of staff having only a bell dropdown
   and customers only an inline "Notifications" tab.
2. Admin/Superadmin can send **announcements** to targeted recipients,
   chosen by role checkboxes (Customers + each staff role) with a
   per-send excluded-user list, built as a real messaging system
   (threads + replies) rather than a one-way broadcast row.

---

## Important decisions made along the way

- **Scope boundary**: threads are only ever created via the
  Admin/Superadmin announcement-composition flow
  (`POST /messages/announcements`). There is no general "start a DM with
  anyone" composer. Once a thread exists, every participant (staff or
  customer) can reply within it.
- **One new event type, not two**: `notification_event_type` gained a
  single `message_received` value covering both an announcement's initial
  delivery and every reply in its thread - `notifications.related_thread_id`
  is what a client follows to open the right thread, not the event type.
- **Branch scoping for staff targeting**: an Admin's checked staff-role
  checkboxes resolve to staff at the Admin's own branch only; a Superadmin's
  resolve globally (matching `GET /staff`'s existing branch rule). Customer
  targeting is always global - customers have no `branch_id`.
- **RLS is documentation, not enforcement, on the 3 new tables** - same as
  the existing `notifications` table. Every write in this codebase already
  runs through the server's service-role Supabase client; a thread reply's
  authorization (must be an existing participant) is checked in
  `messaging.controller.ts` before the insert, mirroring how
  `notifications.controller.ts` resolves ownership before `markRead`.
- **Customer portal tab -> routed page**: the customer portal's old inline
  "Notifications" tab (`CustomerPortalPage.tsx`) is removed; customers now
  reach `/portal/notifications` via a new sidebar entry and a new navbar
  bell (customers previously had no bell at all - only staff did).

---

## 1. Database schema

**What changed:** three new tables (`message_threads`,
`message_thread_participants`, `messages`), a 9th
`notification_event_type` enum value (`message_received`), and a nullable
`notifications.related_thread_id` column pointing at the thread a
`message_received` notification is about.

**Files:**
`supabase/migrations/20260814123_custom_create_messaging_schema.sql`,
`supabase/migrations/20260814124_custom_notification_event_type_add_message_received.sql`,
`supabase/migrations/20260814125_custom_notifications_related_thread_id.sql`.

---

## 2. Server: announcements + threaded replies

**What changed:** a new `server/src/features/messaging/` feature.
`createAnnouncement` resolves the checked role checkboxes + excluded-user
list into a concrete recipient set (branch-scoped for staff unless the
sender is Superadmin), creates the thread with every recipient as a
participant, writes the announcement body as the thread's first message,
then best-effort notifies every recipient via the **existing**
`createNotification` (extended with an optional `relatedThreadId`, not
duplicated). `replyToThread` lets any participant reply, notifying every
_other_ participant the same way. `markThreadRead` marks both the
participant's own read-state and any still-unread `notifications` row tied
to that thread, so the bell badge and the thread's own unread state can't
drift depending on which UI surface (bell dropdown vs. Messages tab) the
user read it from.

**Files:**
`server/src/features/messaging/{messaging.types,messaging.controller,messaging.routes}.ts`,
`server/src/features/messaging/services/messaging.service.ts`,
`server/src/features/notifications/notifications.types.ts` (+
`message_received` event type, `related_thread_id` field),
`server/src/features/notifications/services/notification.service.ts` (+
`relatedThreadId` param), `server/src/shared/app.routes.ts` (mount).

**Verify manually:**

1. As Admin/Superadmin, `POST /messages/announcements` targeting a couple
   of staff roles + Customers, with one explicit excluded id. Confirm the
   excluded user gets nothing and every other matching staff/customer gets
   a `message_received` notification row.
2. As a non-admin staff member, attempt the same POST - confirm 403.
3. As one of the recipients, `GET /messages/threads` shows the new thread;
   `POST /messages/threads/:id/messages` (reply) succeeds for a
   participant and is visible to every other participant via
   `GET /messages/threads/:id`; a non-participant staff member gets 403 on
   reply and 404 on `GET /messages/threads/:id` (not leaked).
4. `PATCH /messages/threads/:id/read` clears both the thread's own unread
   state and the originating bell notification's `is_read`.

---

## 3. Client: notifications page, messages tab, announcement composer

**What changed:** a new `client/src/features/messaging/` feature
(`ThreadList`, `ThreadDetail`, `AnnouncementComposer`, reusing the existing
`listStaff`/`listCustomers` endpoints for the exclusion picker - no new
directory endpoint). A new shared `NotificationsPage` (`{role}` prop, same
pattern `SettingsPage` uses) renders at both `/staff/notifications` and
`/portal/notifications`, with an Inbox tab (the existing event-notification
list) and a Messages tab (thread list + detail, master-detail layout);
selecting an inbox row whose event type is `message_received` jumps
straight into that thread instead of just marking it read. A new
`AnnouncementComposerPage` (`/staff/notifications/new`) self-gates
Admin/Superadmin the same way `SettingsPage`'s Config tab does (via
`getMfaStatus('staff', ...)`, which already returns the caller's own
staff role - UX-only, real enforcement is the server's `requireRole`).
`NotificationBell`/`NotificationDropdown` gain a "View all" link to the new
page. Customers get a `NotificationBell` in their navbar for the first
time (`CustomerAuthGuard.tsx`), and a "Notifications" sidebar entry
(`customerPortal.config.ts`); the old inline Notifications tab is removed
from `CustomerPortalPage.tsx`, which is Overview-only now.

**Files:**
`client/src/features/messaging/**` (new),
`client/src/pages/NotificationsPage/*` (new),
`client/src/pages/AnnouncementComposerPage/*` (new),
`client/src/features/notifications/components/NotificationDropdown/NotificationDropdown.tsx` (+ "View all" link),
`client/src/features/notifications/components/NotificationBell/NotificationBell.tsx` (+ `notificationsHref` prop),
`client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` (+ `notificationsHref`),
`client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx` (+ new bell),
`client/src/shared/components/Navbar/Navbar.tsx` (stale doc-comment fix),
`client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.{tsx,module.css,spec.ts}` (tab removed),
`client/src/features/customers/config/customerPortal.config.ts` (+ sidebar entry),
`client/src/features/auth/staff/staffAuth.routes.ts`,
`client/src/features/auth/customer/customerAuth.routes.ts` (route registration).

**Verify manually:**

1. As staff, click the navbar bell - confirm a "View all" link at the
   bottom opens `/staff/notifications`. Repeat as a customer - confirm the
   customer navbar now also shows a bell, and it links to
   `/portal/notifications`. Also confirm the customer sidebar has a
   "Notifications" entry, and `/portal` itself no longer has a
   Notifications tab.
2. As Admin/Superadmin, click "New announcement" on the Notifications
   page, fill in a subject/message, check a couple of staff-role boxes and
   "Customers", exclude one specific person from the list that appears,
   and send. Confirm you land back on the Messages tab with the new thread
   visible.
3. Log in as one of the targeted (non-excluded) recipients - confirm a
   bell badge appears, the Inbox tab shows the announcement, and clicking
   it jumps to the Messages tab with that thread open and marked read.
   Confirm the excluded person sees nothing.
4. As that recipient, send a reply. Log back in as another recipient (or
   the Admin who sent it) and confirm the reply is visible in the same
   thread.
5. As a non-Admin/Superadmin staff member, navigate directly to
   `/staff/notifications/new` - confirm it redirects away.

---

## Round 2: Gmail-style messaging redesign

Follow-up request after round 1 shipped: a compose modal (Mail vs.
Announcement type picker) launched from a new navbar mail icon, anyone-to-
anyone Mail threads, Announcement senders widened to Supervisor/Admin/
Superadmin, per-item read/unread/star/delete actions, search/filter/sort,
and a Gmail-style folder rail (Inbox/Starred/Sent/Drafts/System) replacing
the Inbox-tab/Messages-tab split from round 1.

### Important decisions

- **Presentation-layer merge, not table unification**: the `notifications`
  table (8 system event types, ~15 existing `createNotification` call
  sites elsewhere in the app) is untouched. `message_threads`/`messages`
  stay the only reply-capable, subject-based conversations. The client
  normalizes both into one `InboxItem` shape for display - two backends,
  one screen. `'message_received'` notification rows are excluded from
  every normalized view (Inbox/Starred/System) since the thread itself is
  the richer, canonical representation of that same event - showing both
  would double-list one conceptual item.
- **Folders**: Inbox (received, `is_own = false`), Sent (`is_own = true`,
  threads only), Drafts (new `message_drafts` table), Starred
  (`is_starred = true` across both kinds), System (notifications only).
  Every folder has its own search/filter/sort controls.
- **`ANNOUNCEMENT_SENDER_ROLES = ['Supervisor','Admin','Superadmin']`** -
  new constant in `staff.types.ts`, deliberately separate from
  `ADMIN_ROLES` (which also gates unrelated staff-CRUD routes).
- **New directory endpoint** `GET /messages/directory?q=` (any
  authenticated user, staff or customer) - minimal fields only (id, display
  name, staff role), powers the Mail recipient picker. New PII-adjacent
  surface: any customer can now discover any other customer's full name
  and any staff member's display name/role by search - a direct, necessary
  consequence of "anyone can Mail anyone."
- **Delete is one-way/soft, no restore UI** (no Trash folder was
  requested); **star is a toggle**; **read gets a `read?: boolean` param**
  on both `markThreadRead`/`markNotificationRead` (default true) rather
  than separate mark-unread endpoints.
- **Drafts don't support resuming into the composer with fields
  pre-filled** in this pass - a draft row lists as its own row with Send/
  Delete actions only; Send reconstructs and dispatches the real thread
  entirely server-side (`sendDraft`), no need to reopen the modal.
- `AnnouncementComposerPage`/`/staff/notifications/new` is retired -
  compose now only happens via the navbar's `ComposeEntryPoint` ->
  `ComposeModal`. The old route redirects to `/staff/notifications` rather
  than 404ing for anyone with it bookmarked.
- **Live-verified**: every new server endpoint (directory search, Mail
  create, star/delete/unread on both threads and notifications, and the
  full draft lifecycle - create, update, send, list) was smoke-tested
  against the real dev Supabase project with seeded Admin/Supervisor/
  Receptionist logins before the client was built on top of it, including
  confirming Supervisor can send an announcement and a Receptionist gets 403.

### 4. Database schema (round 2)

**What changed:** `message_threads` gains `created_by_customer_id`
(customers can now create Mail threads) and `thread_type`
(`'mail' | 'announcement'`, defaulting existing rows to `'announcement'`);
`message_thread_participants` and `notifications` both gain
`is_starred`/`is_deleted`; a new `message_drafts` table backs the Drafts
folder (author-scoped, `recipients` stored as jsonb since Mail and
Announcement have different targeting shapes).

**Files:**
`supabase/migrations/20260814126_custom_message_threads_add_created_by_customer_id.sql`,
`supabase/migrations/20260814127_custom_message_threads_add_thread_type.sql`,
`supabase/migrations/20260814128_custom_message_thread_participants_add_starred_deleted.sql`,
`supabase/migrations/20260814129_custom_notifications_add_starred_deleted.sql`,
`supabase/migrations/20260814130_custom_create_message_drafts_schema.sql`.

### 5. Server (round 2)

**What changed:** `messaging.service.ts`'s `createAnnouncement` insert
logic was factored into a shared `createThread` helper, reused by new
`createMailThread` (anyone to anyone, explicit recipients). New
`directory.service.ts` (`searchMessagingDirectory`) and `drafts.service.ts`
(full CRUD + `sendDraft`). `setThreadReadState`/`setThreadStarred`/
`setThreadDeleted` added to `messaging.service.ts`; `setNotificationStarred`/
`setNotificationDeleted` added to `notification.service.ts`; `markRead`
extended with a `read` param. `POST /messages/announcements`'s
`requireRole` swapped from `ADMIN_ROLES` to `ANNOUNCEMENT_SENDER_ROLES`.

**New/changed routes:** `POST /messages/mail`, `GET /messages/directory`,
`PATCH /messages/threads/:id/star`, `POST /messages/threads/:id/delete`,
`GET|POST /messages/drafts`, `GET|PATCH|DELETE /messages/drafts/:id`,
`POST /messages/drafts/:id/send`, `PATCH /notifications/:id/star`,
`POST /notifications/:id/delete`.

**Files:**
`server/src/features/messaging/services/{messaging,directory,drafts}.service.ts`,
`server/src/features/messaging/{messaging.controller,messaging.routes,messaging.types}.ts`,
`server/src/features/notifications/{notification.service,notifications.controller,notifications.routes,notifications.types}.ts`,
`server/src/features/staff/staff.types.ts` (+ `ANNOUNCEMENT_SENDER_ROLES`).

**Verify manually:**

1. As Supervisor, `POST /messages/announcements` - confirm 201 (widened
   role). As a Receptionist, same request - confirm 403.
2. As any staff member or customer, `GET /messages/directory?q=<2+ chars>`
   - confirm results include both staff and customers, excluding the
     caller themselves, and that a 1-character query returns `[]`.
3. `POST /messages/mail` from a staff member to a customer (or vice
   versa) - confirm 201 and the recipient sees it via `GET
/messages/threads`.
4. `PATCH /messages/threads/:id/star` and `POST /messages/threads/:id/delete`
   - confirm the thread disappears from `GET /messages/threads` after
     delete but is still reachable via `GET /messages/threads/:id` directly.
5. `POST /messages/drafts` -> `PATCH /messages/drafts/:id` -> `POST
/messages/drafts/:id/send` - confirm the draft is gone from `GET
/messages/drafts` afterward and a real thread now exists.

### 6. Client (round 2)

**What changed:** new `client/src/features/messaging/components/`
(`RecipientPicker`, `MailComposer`, `ComposeModal`, `ComposeEntryPoint`);
`AnnouncementComposer` gained an optional `onSaveDraft` prop/button.
`NotificationsPage` was rebuilt: folder rail (Inbox/Starred/Sent/Drafts/
System) with unread counts, a single normalized list with per-row Star/
Mark read-unread/Delete actions, and a search+filter+sort control bar
shown on every folder. `Navbar`/`AppShell` gained a `composeButton` prop
(rendered next to `notificationBell`), wired to `ComposeEntryPoint` in both
`StaffAuthGuard` (passes the already-resolved staff `role`) and
`CustomerAuthGuard` (passes `null`). The old `ThreadList` component and
`AnnouncementComposerPage` page are deleted (fully superseded).

**Files:**
`client/src/features/messaging/components/{RecipientPicker,MailComposer,ComposeModal,ComposeEntryPoint}/*` (new),
`client/src/features/messaging/components/AnnouncementComposer/AnnouncementComposer.tsx` (+ `onSaveDraft`),
`client/src/features/messaging/{messaging.types,api/messaging.api}.ts`,
`client/src/features/notifications/{notifications.types,api/notifications.api}.ts`,
`client/src/pages/NotificationsPage/*` (rebuilt),
`client/src/shared/components/{Navbar,AppShell}/*` (+ `composeButton`),
`client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx`,
`client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx`,
`client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.spec.ts`
(+ `notifications.api` mock, matching `StaffAuthGuard.spec.ts`'s own -
needed once the customer navbar started rendering a `NotificationBell`
too),
`client/src/features/auth/staff/staffAuth.routes.ts` (`/staff/notifications/new`
now redirects instead of rendering the deleted page).

**Verify manually:**

1. Click the navbar mail icon (both staff and customer) - confirm the
   "New message" modal opens directly (no page navigation). As a
   Receptionist/Cashier/etc. or a customer, confirm only the Mail tab
   shows (no Announcement tab). As Supervisor/Admin/Superadmin, confirm
   both tabs show.
2. Compose a Mail to a specific person (search by name in the recipient
   picker) and Send - confirm it lands in your Sent folder and their
   Inbox, with a correct "From" label.
3. Compose an Announcement, click **Save draft** instead of Send - confirm
   it appears in the Drafts folder with Send/Delete actions, and that
   clicking Send there actually delivers it (check the recipient's Inbox).
4. On any Inbox/Starred/Sent/System row, use the row's Star, Mark
   read/unread, and Delete actions - confirm the folder counts in the rail
   update immediately and a deleted row disappears from the list.
5. Type into the search box and change the filter/sort dropdowns on a
   folder with several items - confirm the list narrows/reorders
   correctly, and that switching folders resets these controls.
6. Confirm the System folder shows only booking/payment/etc. notifications
   (no Mail/Announcement threads), and that Inbox does **not** show a
   duplicate row for a thread you already see there (i.e. no
   `message_received` row leaking through as a second entry).

---

## Round 3: proxy fix, exclude-list UX, recipient filtering, attachments

Four follow-ups after using round 2 in the browser.

### Important decisions

- **Root cause found for the original "Request failed" report and the new
  "Mail search shows no results" report - the same bug**: `client/vite.config.ts`
  has an explicit allowlist of path prefixes proxied to the Express API in
  dev; `/messages` was never added to it when `messaging.routes.ts` was
  created. Every `/messages/*` call from the browser (thread list,
  directory search, star/delete, drafts, mail/announcement send) was
  silently falling through to Vite's own dev server instead of reaching
  Express - exactly the failure mode this same file's comments already
  document for `/branches`/`/catalog`/`/reports` (a non-JSON response, not
  a 404/403). My earlier live-testing never caught this because curl talks
  to Express on port 3000 directly, bypassing the Vite proxy entirely -
  this class of bug is invisible to server-side smoke testing by
  construction. Fixed by adding a `/messages` entry; **restart the client
  dev server** (Vite auto-restarts on `vite.config.ts` changes, but
  confirm) for it to take effect.
- **Exclude lists are collapsed by default** with their own search/role-
  filter/sort controls (new shared `ExcludeListPanel` component) rather
  than an always-open scroll - these can run into dozens of names once
  several roles or "Customers" is checked.
- **Mail's recipient search gains client-side filter (staff vs. customer,
  staff role) and sort** on top of the existing server-side name search -
  the two are independent: the server still does the substring match, the
  new controls only narrow/reorder the current result page.
- **Attachments**: any Mail/Announcement send or thread reply can attach
  files (images, PDF, plain text, Word/Excel), capped at 15 MB each. A new
  `message-attachments` storage bucket is provisioned **via migration SQL**
  (`insert into storage.buckets`), not a manual dashboard step - unlike the
  pre-existing `avatars` bucket, which predates this convention. Upload
  happens immediately on file-select (`POST /messages/attachments`,
  returning a plain descriptor - no DB row yet since no message exists
  yet); the descriptors travel with the actual send/reply request, which
  is what links them to a real `message_attachments` row. **Drafts do not
  carry attachments in this pass** - an attachment uploaded while composing
  a message that's then saved as a draft (instead of sent) becomes an
  orphaned storage object rather than being persisted with the draft;
  low-risk (no automatic cleanup exists for orphaned uploads anywhere else
  in this codebase either, e.g. a changed avatar's old file), but worth
  knowing if storage usage ever needs auditing.
- **Live-verified end-to-end**: applied migration `131` (attachments
  schema + bucket) to the dev project, then via curl: uploaded a file,
  created a Mail thread with that attachment, fetched the thread detail
  and confirmed the attachment round-tripped with a real id, and confirmed
  the returned public URL is actually downloadable (200, correct
  content-type/length). The `/messages/directory` fix itself is a dev-only
  Vite config change with no server-side surface to curl-test - covered by
  a manual verification step below instead.

### Database

**What changed:** `message_attachments` table (participant-scoped SELECT
RLS, same convention as the rest of this schema) and a `message-attachments`
public storage bucket.

**Files:** `supabase/migrations/20260814131_custom_create_message_attachments_schema.sql`.

### Server

**What changed:** new `attachments.service.ts` (`uploadAttachment` -
validates type/size, uploads to storage, returns a descriptor;
`insertAttachmentsForMessage` - links descriptors to a real message row,
called from both `createThread` and `replyToThread` in
`messaging.service.ts`). `getThreadDetail` now fetches and attaches each
message's attachments. `CreateAnnouncementParams`/`CreateMailThreadParams`/
`ReplyToThreadParams` all gained an optional `attachments` field.

**New route:** `POST /messages/attachments` (multipart, any authenticated
user, 15 MB/file limit via multer, mirrors `staff.routes.ts`'s
`avatarUpload`/`handleAvatarUploadError` pattern).

**Files:**
`server/src/features/messaging/services/attachments.service.ts` (new),
`server/src/features/messaging/services/messaging.service.ts`,
`server/src/features/messaging/{messaging.controller,messaging.routes,messaging.types}.ts`.

**Verify manually:**

1. `POST /messages/attachments` with a small text/image file - confirm
   201 with a `fileUrl` that's publicly downloadable.
2. `POST /messages/mail` (or `/messages/announcements`) including that
   descriptor in `attachments` - confirm `GET /messages/threads/:id`
   shows it under the first message, with a real `id`.
3. `POST /messages/threads/:id/messages` (reply) with an attachment -
   confirm it shows up on the reply message, not the first one.
4. Upload a file over 15 MB, or an unsupported type (e.g. `.exe`) -
   confirm 400 in both cases.

### Client

**What changed:** new `ExcludeListPanel` (collapsible, search/role-filter/
sort) used by both "Exclude staff" and "Exclude customers" in
`AnnouncementComposer`. `RecipientPicker` gained a filter row (staff vs.
customer, staff role) and a sort dropdown (best match/name A-Z/name Z-A)
over its live search results. New `AttachmentPicker` (file input + upload-
on-select + removable chips) used in `MailComposer`, `AnnouncementComposer`,
and `ThreadDetail`'s reply box; `ThreadDetail` now also renders each
message's attachments as download links.

**Files:**
`client/src/features/messaging/components/ExcludeListPanel/*` (new, lives
under `AnnouncementComposer/`),
`client/src/features/messaging/components/AttachmentPicker/*` (new),
`client/src/features/messaging/components/{AnnouncementComposer,MailComposer,RecipientPicker,ThreadDetail}/*`,
`client/src/features/messaging/{messaging.types,api/messaging.api}.ts`,
`client/src/pages/NotificationsPage/NotificationsPage.tsx`,
`client/vite.config.ts` (the proxy fix).

**Verify manually:**

1. Hard-refresh the browser after restarting the client dev server, open
   Compose -> Mail, type a 2+ character name into "To" - confirm results
   now actually appear (this was the reported bug).
2. In that same "To" field, use the new filter dropdowns to narrow to
   "Staff only" + a specific role, and try both sort options - confirm the
   result list updates accordingly.
3. Open Compose -> Announcement, check a couple of staff roles - confirm
   "Exclude staff" starts collapsed; expand it, use its search box and
   role filter/sort - confirm it narrows correctly and the excluded-count
   badge on the collapsed header updates as you check names.
4. In either Mail or Announcement, click "Attach files", pick 1-2 small
   files - confirm each appears as a chip with its size, is removable
   before sending, and after Send, opening that thread shows the
   attachment(s) as clickable download links under the first message.
5. Open an existing thread and reply with an attached file - confirm it
   appears on the reply bubble specifically, not retroactively on the
   first message.

---

## Migrations

Nine migrations total, applied in order: round 1's `20260814123` through
`20260814125` (see above), round 2's `20260814126` through `20260814130`
(message_threads creator/type columns, star/deleted columns on
participants and notifications, the message_drafts table), and round 3's
`20260814131` (message_attachments table + the message-attachments storage
bucket). `124` must run in its own transaction (Postgres forbids using an
`ADD VALUE` enum value in the same transaction that added it) - the
CLI/dashboard both apply migrations one at a time already, so this only
matters if you're ever tempted to hand-paste multiple migrations' bodies
into one query. Bundled for reference in
`notifications-page-and-announcements.sql` in this folder; source of truth
is still `supabase/migrations/`. **All nine were applied and live-verified
against the real dev Supabase project as part of building this feature**
(see each round's "Live-verified" note above) - this is not a "run it
yourself and hope" migration set.

- **With Supabase CLI access:** `supabase db push` from the repo root (or
  `supabase migration up` for a local dev DB).
- **Without CLI/push access:** Supabase Dashboard -> **SQL Editor** ->
  **New query** -> paste `notifications-page-and-announcements.sql` from
  this folder -> **Run**. Afterwards, confirm with:

  ```sql
  select exists (
    select 1 from pg_tables where tablename = 'message_threads'
  ) as has_message_threads;

  select exists (
    select 1 from pg_enum
    where enumlabel = 'message_received'
      and enumtypid = 'public.notification_event_type'::regtype
  ) as has_message_received_value;

  select column_name from information_schema.columns
  where table_name = 'notifications' and column_name = 'related_thread_id';

  select column_name from information_schema.columns
  where table_name = 'message_threads'
    and column_name in ('created_by_customer_id', 'thread_type');

  select column_name from information_schema.columns
  where table_name = 'message_thread_participants'
    and column_name in ('is_starred', 'is_deleted');

  select exists (
    select 1 from pg_tables where tablename = 'message_drafts'
  ) as has_message_drafts;

  select exists (
    select 1 from pg_tables where tablename = 'message_attachments'
  ) as has_message_attachments;

  select exists (
    select 1 from storage.buckets where id = 'message-attachments'
  ) as has_attachments_bucket;
  ```

  All queries should confirm the new objects exist.

## Postman

`notifications-page-and-announcements.postman_collection.json` in this
folder covers the round 1 `/messages/*` surface: create an announcement
(`POST /messages/announcements`), the 403 a non-admin gets on the same
route, list/read a thread (`GET /messages/threads`,
`GET /messages/threads/:id`), reply (`POST /messages/threads/:id/messages`),
and mark-read (`PATCH /messages/threads/:id/read`). Fill in
`admin_identifier`/`admin_password`, `staff_identifier`/`staff_password`
(any non-admin staff member, used both as a targeted recipient and to
prove the 403), and `branch_id` in the collection variables before running
requests 1 through 8 in order - each has a **Tests** tab that should go
green. Rounds 2 and 3's additional routes (`/messages/mail`,
`/messages/directory`, `/messages/attachments`, star/delete on threads and
notifications, the drafts CRUD + send) were smoke-tested live via curl
during development (see each round's "Live-verified" note above) rather
than added to this collection - the manual steps in each round's section
above cover the same ground request-by-request if you want to replay them
in Postman yourself.

## Test suites

- `server`: `npx tsc --noEmit` clean; full suite (`npm test`) - **817
  tests pass** (unchanged count across all three rounds - no new specs
  added, see below).
- `client`: `npx tsc --noEmit` clean; full suite (`npm test`) - **591
  tests pass**. `CustomerPortalPage.spec.ts`, `StaffAuthGuard.spec.ts`, and
  `CustomerAuthGuard.spec.ts` (all touched across rounds 1-2) pass with no
  unhandled rejections.
- No dedicated unit specs were added for the new `messaging.service.ts`/
  `directory.service.ts`/`drafts.service.ts`/`attachments.service.ts` or
  any client messaging component across any of the three rounds - every
  round's server surface was instead live-verified end-to-end against the
  real dev database (see each round's "Live-verified" note above), and the
  manual steps in each section cover the client-side behavior.

## Suggested branch name

`feat/notifications-page-and-announcements`

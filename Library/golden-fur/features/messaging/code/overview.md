---
title: Messaging — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, messaging]
project: golden-fur
---

Messaging is the in-app Mail/Announcements feature — Gmail-style threads
between staff and customers, plus role-targeted Announcements from
Supervisor/Admin/Superadmin. It was added after the original 14 modules and
has no M-code of its own; it's a _consumer_ of the Notifications module
(every new thread/reply fires a `message_received` notification through
`createNotification`), not part of that module's own code.

**Part of:** [[M11-notification]] (closest related module — see "How this
connects" below for the exact relationship)

## Client-side (`client/src/features/messaging/`)

### components/

- **`ComposeEntryPoint/ComposeEntryPoint.tsx`** — The navbar's compose
  (pencil) icon. Owns its own open/closed state by default (same shape as
  `NotificationBell` owning its dropdown), but accepts a controlled
  `isOpen`/`onOpenChange` pair so the customer portal's HelpMascot "Contact
  support" link can open the same modal from outside the navbar. Opens
  `ComposeModal` — nothing to render when closed, since this is a write-only
  trigger, not a second inbox.
- **`ComposeModal/ComposeModal.tsx`** — The compose dialog. Toggles between a
  "Mail" tab (`MailComposer`, anyone to anyone) and an "Announcement" tab
  (`AnnouncementComposer`), the latter only rendered at all when
  `viewerRole` is in the local `ANNOUNCEMENT_SENDER_ROLES` literal
  (Supervisor/Admin/Superadmin). Also owns the "Save draft" plumbing —
  collects whichever composer's current field state and calls `createDraft`.
- **`MailComposer/MailComposer.tsx`** — Anyone-to-anyone compose form:
  subject, body, a `RecipientPicker` for arbitrary individual recipients, and
  an `AttachmentPicker`. Submits via `createMailThread`.
- **`AnnouncementComposer/AnnouncementComposer.tsx`** — Admin/Superadmin-only
  compose form: subject, body, a checkbox grid (one per staff role plus a
  "Customers" checkbox) for who the announcement targets, and an
  `ExcludeListPanel` to carve out specific people from an otherwise-broad
  target. Reuses the existing `listStaff`/`listCustomers` endpoints rather
  than a dedicated directory call. Submits via `createAnnouncement`.
- **`AnnouncementComposer/ExcludeListPanel.tsx`** — Collapsed-by-default
  search/filter/sort picker used by the Announcement composer's "Exclude
  staff"/"Exclude customers" sections — these lists can run into the dozens
  of names, so it's not just a long always-open checkbox list.
- **`AttachmentPicker/AttachmentPicker.tsx`** — Shared by every compose
  surface (Mail, Announcement, and thread replies). Each selected file
  uploads immediately via `uploadAttachment` and shows up as a removable
  chip holding a `PendingAttachment` descriptor; the actual send/reply call
  is what links the descriptors to a real message.
- **`RecipientPicker/RecipientPicker.tsx`** — Debounced (250ms) search box
  for Mail's "anyone to anyone" targeting, backed by `GET
/messages/directory`. Client-side filter (staff vs. customer, staff role)
  and sort apply to the current results page; the search itself is
  server-side.
- **`ThreadDetail/ThreadDetail.tsx`** — The detail pane of the Messages
  page's master-detail layout: renders a thread's full message history as
  chat-style bubbles (styled differently for "sent by me" vs. others, judged
  by comparing `viewerId` against each message's sender id) plus a reply box
  any participant can use, not just the thread's creator.
- `*.module.css` files across all the above — plain CSS Modules styling; no
  logic worth documenting per-file.

### api/

- **`api/messaging.api.ts`** — Thin fetch wrappers around every server
  route: thread listing/detail/reply (`listThreads`, `getThreadDetail`,
  `replyToThread`), attachment upload (`uploadAttachment`), thread state
  (`markThreadRead`, `starThread`, `deleteThread`), thread creation
  (`createAnnouncement`, `createMailThread`), directory search
  (`searchDirectory`), and the full drafts CRUD
  (`listDrafts`/`createDraft`/`updateDraft`/`deleteDraft`/`sendDraft`). Same
  `{ data, error }` result shape as `notifications.api.ts`.

### messaging.types.ts

- Client mirror of the server's `messaging.types.ts` — `MessageThread`,
  `MessageThreadParticipant`, `MessageAttachment`, `PendingAttachment` (an
  already-uploaded-but-not-yet-linked file descriptor), `Message`,
  `ThreadSummary` (the inbox list row shape — `lastMessageAt`,
  `lastMessagePreview`, `lastSenderLabel`, `unread`, `isStarred`, `isOwn`),
  `ThreadDetail`, `CreateAnnouncementParams`, `CreateMailThreadParams`,
  `DirectoryEntry`, and the drafts shapes (`DraftRecipients`,
  `MessageDraft`, `SaveDraftParams`).

## Server-side (`server/src/features/messaging/`)

### Controller & routes

- **`messaging.controller.ts`** — One controller per route: thread
  list/detail/reply, attachment upload (plus
  `handleAttachmentUploadError`, a multer error handler mirroring
  `staff.controller.ts`'s avatar-upload one), thread
  read/star/delete state, `createAnnouncementController` (reads
  `req.user.role`/`branch_id`, already populated by `requireRole`/
  `requireBranch` in the routes file), `createMailThreadController` (no role
  gate — "anyone to anyone"), directory search, and the full drafts CRUD
  including `sendDraftController` (which resolves the sender's branch itself
  since this shared route only runs `jwtMiddleware`, not `requireBranch`).
- **`messaging.routes.ts`** — Mounts everything under `/messages`.
  `/messages/announcements` alone is gated
  `requireRole(ANNOUNCEMENT_SENDER_ROLES)` + `requireBranch`; every other
  route (mail, threads, directory, attachments, drafts) is a shared
  customer-or-staff route behind `jwtMiddleware` only, same pattern as
  `notifications.routes.ts` — membership/ownership is resolved inside each
  controller instead. Attachment upload runs through `multer` (15MB limit,
  in-memory storage) before `uploadMessageAttachmentController`.

### Service

- **`services/messaging.service.ts`** — The core of this feature. The
  private `createThread()` helper is the one path both `createAnnouncement`
  (resolves the role-checkbox + exclude-list targeting into concrete
  recipients, branch-scoped for a non-Superadmin sender) and
  `createMailThread` (explicit recipients, self-references dropped) funnel
  through: it inserts the thread row, a participant row per recipient (plus
  the creator), the opening message, any attachments, and then — the
  connection point to Notifications — calls `createNotification()` once per
  recipient with `eventType: 'message_received'` and `relatedThreadId` set,
  catching and logging any single recipient's notify failure without
  stopping the rest. `replyToThread()` follows the same pattern for a reply:
  inserts the message, bumps the replier's own `last_read_at`, and
  best-effort notifies every _other_ participant. Also exports the inbox
  reader `getThreadsForRecipient()` (batch-resolves sender display names
  rather than querying per row), `getThreadDetail()` (404s rather than 403s
  on a thread the requester isn't a participant of, matching Notifications'
  own "don't leak existence" convention), and `setThreadReadState()` (which
  deliberately also syncs the matching `message_received` notification row's
  `is_read`, so the bell badge and the thread's own unread state can't drift
  depending which UI the user reads from).
- **`services/directory.service.ts`** — `searchMessagingDirectory()` backs
  the Mail recipient picker. Reachable by any authenticated user (unlike the
  staff-only `GET /staff` or `GET /customers`), and deliberately returns only
  id/display name/role — never email, phone, or branch — since this is now
  readable by any customer as a direct consequence of "anyone can Mail
  anyone." Requires a 2+ character query so it can't be used to dump the
  whole directory.
- **`services/drafts.service.ts`** — Draft CRUD scoped to the author's own
  id. `sendDraft()` loads the draft (author-scoped 404), reconstructs the
  right `createMailThread`/`createAnnouncement` call from the draft's
  `recipients` jsonb blob (re-checking the announcement role gate at send
  time, not just at save time), sends it, then deletes the draft row — a
  draft is a staging area, not something that lingers next to its own sent
  thread.
- **`services/attachments.service.ts`** — `uploadAttachment()` validates
  MIME type (an allow-list covering images, PDF, plain text, and
  Word/Excel) and a 15MB size cap, then uploads to the `message-attachments`
  Supabase storage bucket and returns a plain descriptor — no
  `message_attachments` row is written yet, since no message exists at
  upload time. `insertAttachmentsForMessage()` is the second half: called
  once an actual message row exists (from `createThread`/`replyToThread`),
  it writes one `message_attachments` row per descriptor.

### Types & validators

- **`messaging.types.ts`** — Server-side source of truth for the shapes
  mirrored on the client (see above), plus the server-only
  `CreateAnnouncementParams`/`CreateMailThreadParams`/`ReplyToThreadParams`
  input shapes each service function takes.

## How it connects

Messaging has no M-code of its own — `docs/architecture.md`'s module map
explicitly calls it out as one of a few features "added later" that "aren't
part of this module numbering." It's documented here as a satellite of
[[M11-notification]] because every thread creation and reply routes through
that module's shared `createNotification()` write path
(`server/src/features/notifications/services/notification.service.ts`) with
`eventType: 'message_received'` — see
[[M11-01-event-triggered-notification-dispatch]] for how that dispatch is
gated by the recipient's own preferences. Messaging is a _source_ of that
event, not part of the Notifications module's own code: the `notifications`
row a new thread/reply produces is what lights up the bell badge
(`NotificationBell` — see [[features/notifications/code/overview|the
Notifications Code Guide]]) and its `related_thread_id` is what lets clicking
that notification open the right thread.

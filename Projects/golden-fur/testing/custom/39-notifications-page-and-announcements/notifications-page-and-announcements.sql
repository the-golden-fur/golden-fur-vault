-- Bundled for reference only - source of truth is still supabase/migrations/.
-- Apply in order (124 must run in its own transaction - Postgres forbids
-- using a value added by ADD VALUE in the same transaction it was added in):
--   20260814123_custom_create_messaging_schema.sql
--   20260814124_custom_notification_event_type_add_message_received.sql
--   20260814125_custom_notifications_related_thread_id.sql
-- Round 2 (Gmail-style redesign - Mail/Announcement compose modal, star/
-- delete, drafts, Supervisor+ announcement senders):
--   20260814126_custom_message_threads_add_created_by_customer_id.sql
--   20260814127_custom_message_threads_add_thread_type.sql
--   20260814128_custom_message_thread_participants_add_starred_deleted.sql
--   20260814129_custom_notifications_add_starred_deleted.sql
--   20260814130_custom_create_message_drafts_schema.sql
-- Round 3 (proxy fix, exclude-list UX, recipient filtering, attachments):
--   20260814131_custom_create_message_attachments_schema.sql

-- ============================================================
-- 20260814123_custom_create_messaging_schema.sql
-- ============================================================

-- Custom change (notifications page + admin announcements): message_threads/
-- message_thread_participants/messages - the schema behind the
-- Admin/Superadmin "announcement" composer. Threads are only ever created by
-- messaging.service.ts's createAnnouncement (Admin/Superadmin, targeted by
-- role checkboxes + an excluded-user list) - there is no general "start a
-- DM with anyone" composer. Once a thread exists, every participant (staff
-- or customer) can reply within it.

-- ---------------------------------------------------------------------------
-- message_threads
-- ---------------------------------------------------------------------------

create table public.message_threads (
  id uuid primary key default gen_random_uuid(),
  subject text not null,
  created_by_staff_id uuid not null references public.staff_profiles(id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- message_thread_participants
-- ---------------------------------------------------------------------------
-- participant_staff_id/participant_customer_id mirrors notifications'
-- recipient_staff_id/recipient_customer_id exactly-one-of pattern.
-- Participants are fixed at thread-creation time (the announcement's
-- resolved recipients minus exclusions, plus the composer) - there is no
-- "add participant later" operation. last_read_at is null until the
-- participant opens the thread; null means every message is unread to them.

create table public.message_thread_participants (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  participant_staff_id uuid references public.staff_profiles(id),
  participant_customer_id uuid references public.customer_profiles(id),
  last_read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint message_thread_participants_exactly_one_participant check (
    num_nonnulls(participant_staff_id, participant_customer_id) = 1
  )
);

create unique index message_thread_participants_unique_staff_idx
  on public.message_thread_participants(thread_id, participant_staff_id)
  where participant_staff_id is not null;
create unique index message_thread_participants_unique_customer_idx
  on public.message_thread_participants(thread_id, participant_customer_id)
  where participant_customer_id is not null;
create index message_thread_participants_thread_id_idx
  on public.message_thread_participants(thread_id);
create index message_thread_participants_staff_id_idx
  on public.message_thread_participants(participant_staff_id)
  where participant_staff_id is not null;
create index message_thread_participants_customer_id_idx
  on public.message_thread_participants(participant_customer_id)
  where participant_customer_id is not null;

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
-- The announcement's own body is row #1 (sender = the admin who composed
-- it); every reply from any participant is a subsequent row, same
-- exactly-one-of sender pattern.

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  sender_staff_id uuid references public.staff_profiles(id),
  sender_customer_id uuid references public.customer_profiles(id),
  body text not null,
  created_at timestamptz not null default now(),
  constraint messages_exactly_one_sender check (
    num_nonnulls(sender_staff_id, sender_customer_id) = 1
  )
);

create index messages_thread_id_created_at_idx
  on public.messages(thread_id, created_at);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- Every write in this codebase runs through the server's service-role
-- Supabase client (server/src/config/supabase/supabase.config.ts) - there is
-- no code path that inserts as the authenticated end user. So, exactly like
-- notifications' own RLS (whose UPDATE-by-owner policy is never actually
-- exercised either, since markRead/markAllRead also run service-role with
-- ownership checked manually), these policies are SELECT-only and serve as
-- defense-in-depth/documentation rather than live enforcement. A reply's
-- authorization (must be an existing participant) is checked in
-- messaging.controller.ts before the service-role insert runs, mirroring how
-- notifications.controller.ts resolves ownership before calling markRead.

alter table public.message_threads enable row level security;
alter table public.message_thread_participants enable row level security;
alter table public.messages enable row level security;

create policy "Participants can read their threads"
  on public.message_threads
  for select
  to authenticated
  using (
    exists (
      select 1 from public.message_thread_participants p
      where p.thread_id = message_threads.id
        and (p.participant_staff_id = auth.uid() or p.participant_customer_id = auth.uid())
    )
  );

create policy "Participants can read their own membership rows"
  on public.message_thread_participants
  for select
  to authenticated
  using (participant_staff_id = auth.uid() or participant_customer_id = auth.uid());

create policy "Participants can read messages in their threads"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1 from public.message_thread_participants p
      where p.thread_id = messages.thread_id
        and (p.participant_staff_id = auth.uid() or p.participant_customer_id = auth.uid())
    )
  );

-- ============================================================
-- 20260814124_custom_notification_event_type_add_message_received.sql
-- ============================================================

-- Custom change (notifications page + admin announcements): adds the 9th
-- notification_event_type value covering both an announcement's initial
-- delivery and every reply in its thread - notifications.related_thread_id
-- (next migration) is what distinguishes "go read this thread," not the
-- event type, so one value covers both rather than doubling the enum
-- surface for no behavioral gain.
--
-- Must be its own migration: Postgres forbids using a value added by ADD
-- VALUE in the same transaction it was added in - same isolation already
-- used by 20260803079_m13_add_misc_service_category.sql.

alter type public.notification_event_type add value 'message_received';

-- ============================================================
-- 20260814125_custom_notifications_related_thread_id.sql
-- ============================================================

-- Custom change (notifications page + admin announcements): links a
-- 'message_received' notification row back to the message_threads row it
-- was raised for, so selecting it in the bell/notifications page can open
-- the right thread. Nullable, mirroring related_booking_id's own
-- nullability - every other event type never sets this.

alter table public.notifications
  add column related_thread_id uuid references public.message_threads(id);

-- ============================================================
-- 20260814126_custom_message_threads_add_created_by_customer_id.sql
-- ============================================================

-- Custom change (Gmail-style messaging redesign): Mail threads can now be
-- created by a customer, not just staff (Announcement senders) - widens
-- message_threads' creator to the same exactly-one-of pattern already used
-- for participants/senders elsewhere in this schema. Existing rows all
-- already have created_by_staff_id set and created_by_customer_id defaults
-- null, so num_nonnulls = 1 holds with no backfill.

alter table public.message_threads
  alter column created_by_staff_id drop not null;

alter table public.message_threads
  add column created_by_customer_id uuid references public.customer_profiles(id);

alter table public.message_threads
  add constraint message_threads_exactly_one_creator check (
    num_nonnulls(created_by_staff_id, created_by_customer_id) = 1
  );

-- ============================================================
-- 20260814127_custom_message_threads_add_thread_type.sql
-- ============================================================

-- Custom change (Gmail-style messaging redesign): distinguishes an
-- Announcement thread (Supervisor/Admin/Superadmin, role-targeted) from a
-- Mail thread (anyone to anyone, explicit recipients) so the client can
-- badge/filter by type. Every existing row predates Mail, so it defaults to
-- 'announcement' - the only type that existed before this migration.

create type public.message_thread_type as enum ('mail', 'announcement');

alter table public.message_threads
  add column thread_type public.message_thread_type not null default 'announcement';

-- ============================================================
-- 20260814128_custom_message_thread_participants_add_starred_deleted.sql
-- ============================================================

-- Custom change (Gmail-style messaging redesign): per-participant star/
-- delete state for the Starred folder and the delete action - deliberately
-- per participant (not per thread) so one person starring or deleting a
-- shared thread never affects any other participant's view of it. Delete
-- is one-way/soft (no Trash folder was requested) - a deleted row simply
-- stops being returned by getThreadsForRecipient going forward.

alter table public.message_thread_participants
  add column is_starred boolean not null default false,
  add column is_deleted boolean not null default false;

-- ============================================================
-- 20260814129_custom_notifications_add_starred_deleted.sql
-- ============================================================

-- Custom change (Gmail-style messaging redesign): mirrors the star/delete
-- columns just added to message_thread_participants, so the merged Inbox's
-- per-row actions (star/delete) work uniformly across both plain system
-- notifications and message threads even though they stay two separate
-- tables (presentation-layer merge, not a data-model unification - see
-- messaging.service.ts/notification.service.ts for the read-side merge).

alter table public.notifications
  add column is_starred boolean not null default false,
  add column is_deleted boolean not null default false;

-- ============================================================
-- 20260814130_custom_create_message_drafts_schema.sql
-- ============================================================

-- Custom change (Gmail-style messaging redesign): the Drafts folder - an
-- in-progress Mail or Announcement composition that hasn't been sent yet,
-- so it has no thread/participants of its own. recipients is a jsonb blob
-- because Mail and Announcement have entirely different recipient shapes
-- (an explicit staff/customer id list vs. role checkboxes + exclusions) -
-- sendDraft (drafts.service.ts) reconstructs the right params from it and
-- deletes the draft row once the real thread is created.

create table public.message_drafts (
  id uuid primary key default gen_random_uuid(),
  author_staff_id uuid references public.staff_profiles(id),
  author_customer_id uuid references public.customer_profiles(id),
  message_type public.message_thread_type not null,
  subject text,
  body text,
  recipients jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint message_drafts_exactly_one_author check (
    num_nonnulls(author_staff_id, author_customer_id) = 1
  )
);

create index message_drafts_staff_author_idx
  on public.message_drafts(author_staff_id)
  where author_staff_id is not null;
create index message_drafts_customer_author_idx
  on public.message_drafts(author_customer_id)
  where author_customer_id is not null;

-- RLS: same SELECT-only/documentation convention as the rest of this
-- schema (every write goes through the server's service-role client,
-- ownership checked in drafts.service.ts) - a draft has no participant
-- concept, it's private to its author only.

alter table public.message_drafts enable row level security;

create policy "Authors can read their own drafts"
  on public.message_drafts
  for select
  to authenticated
  using (author_staff_id = auth.uid() or author_customer_id = auth.uid());

-- ============================================================
-- 20260814131_custom_create_message_attachments_schema.sql
-- ============================================================

-- Custom change (Gmail-style messaging redesign): file attachments on Mail/
-- Announcement messages and replies. Uploads always go through the
-- server's service-role client (attachments.service.ts), same convention
-- as avatarUpload.service.ts/petPhotoUpload.service.ts - the bucket is
-- created here via SQL (unlike 'avatars', which predates this convention
-- and was created manually) so provisioning is version-controlled rather
-- than a manual dashboard step.

insert into storage.buckets (id, name, public)
values ('message-attachments', 'message-attachments', true)
on conflict (id) do nothing;

create table public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  file_name text not null,
  file_url text not null,
  file_size bigint not null,
  mime_type text not null,
  created_at timestamptz not null default now()
);

create index message_attachments_message_id_idx
  on public.message_attachments(message_id);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
-- Same SELECT-only/documentation convention as the rest of this schema -
-- every write goes through the service-role client. A participant of the
-- owning thread may read the attachment row (mirrors messages' own
-- participant-membership SELECT policy).

alter table public.message_attachments enable row level security;

create policy "Participants can read attachments in their threads"
  on public.message_attachments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages m
      join public.message_thread_participants p on p.thread_id = m.thread_id
      where m.id = message_attachments.message_id
        and (p.participant_staff_id = auth.uid() or p.participant_customer_id = auth.uid())
    )
  );

-- Storage bucket is public (mirrors 'avatars') so an uploaded file's public
-- URL works directly in an <a>/<img> tag without a signed-URL round trip -
-- attachment *visibility* is still gated by the message_attachments row
-- policy above (an unlisted, unguessable object path is not itself an
-- access control, but nothing in the UI ever surfaces a URL to a non-
-- participant since the row that carries it is already scoped).

create policy "Public can read message attachments"
  on storage.objects
  for select
  to public
  using (bucket_id = 'message-attachments');

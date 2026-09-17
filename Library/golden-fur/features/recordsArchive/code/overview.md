---
title: Records Archive — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, recordsArchive]
project: golden-fur
---

Records Archive is a universal safety net for accidental (or malicious)
deletes: whenever a row is physically deleted from _any_ table in the
database, a Postgres trigger copies its full contents into one shared
`deleted_records_archive` table before it's gone. This feature is the
admin-facing API over that table — list/search what's been deleted,
restore a row back into its original table, or permanently purge an
archive entry. It's server-only, and it doesn't map cleanly onto a single
architecture.md module (M01–M14): it's cross-cutting admin/staff tooling
that watches every table at once, rather than belonging to one business
area, so no `[[M0X]]` link is included below. (It's a different mechanism
from the per-entity "deactivate → archive → hard-delete" soft-archive
lifecycle used by Customers/Pets, Products, and Staff — that one is
enforced by `server/src/shared/archive/archiveGuard.ts`, covered here for
context but documented in full as part of
[[M02-03-customer-pet-deactivation-archive-lifecycle]].)

## Server-side (`server/src/features/recordsArchive/`)

### Controller & routes

- **`recordsArchive.controller.ts`** — four handlers:
  `listDeletedRecordsController`, `listDeletedRecordTablesController`,
  `restoreDeletedRecordController`, `purgeDeletedRecordController`. The
  list endpoint validates its query string with a Zod schema
  (`table`, `search`, `from`/`to` ISO datetimes, `sort`, and paginated
  `page`/`page_size`, capped at 100 per page) defined right in this file.
  Restore requires an authenticated requester (`req.user?.sub`, 401 if
  missing) so the archive row can record who restored it. All four route
  through a shared `sendServiceError` helper for consistent error
  responses.
- **`recordsArchive.routes.ts`** — mounts
  `GET /staff/deleted-records`, `GET /staff/deleted-records/tables`,
  `POST /staff/deleted-records/:id/restore`, and
  `DELETE /staff/deleted-records/:id`, all behind `jwtMiddleware`,
  `sessionTimeoutMiddleware`, and `requireRole(ADMIN_ROLES)`. A comment
  notes these are deliberately mounted under `/staff` rather than getting
  their own `API_ROUTE_PREFIXES` entry, since this is staff/admin tooling
  alongside the rest of the Archive page's routes.

### Service

- **`services/recordsArchive.service.ts`** — the core logic, four
  functions:
  - `listDeletedRecords` — filters `deleted_records_archive` by
    `source_table`, a `search` term matched against a generated
    `search_text` column (plain `ilike`, no full-text search setup — a
    file comment explains that's enough at this project's scale), and a
    `deleted_at` date range; sorts and paginates; returns `{ rows, total }`.
  - `listDeletedRecordTables` — the distinct `source_table` values
    currently present in the archive, for the filter dropdown — a table
    only appears once something has actually been deleted from it.
  - `restoreDeletedRecord` — fetches the archive entry, rejects if
    already restored (409), then re-inserts its `row_data` (a full
    `to_jsonb(OLD)` snapshot) straight back into `source_table` and stamps
    `restored_at`/`restored_by`. Because it doesn't know the target
    table's columns ahead of time, any Postgres constraint violation (a
    new row already occupying that id, a referenced row itself gone,
    etc.) just surfaces as a plain 400 with Postgres's own message. It
    also does **not** reconstruct a deleted row's dependent children
    automatically — cascade-deleted rows are archived as their own
    separate entries, so restoring a parent means separately finding and
    restoring each child entry too.
  - `purgeDeletedRecord` — permanently deletes one archive entry (not the
    long-gone original row). The capture trigger excludes this table from
    itself, so purging never re-archives the purge.

### Types

- **`recordsArchive.types.ts`** — `DeletedRecordArchiveEntry` (id,
  source_table, record_id, row_data, deleted_by, deleted_at, restored_at,
  restored_by) and the `DeletedRecordsSort` union. A comment notes
  `deleted_by` will be null for the overwhelming majority of deletes,
  since the server's service-role Supabase client has no `auth.uid()`
  inside the database trigger that captures rows — the same limitation
  `activity_log.actor_staff_id` has.

There's no validator subfolder or barrel `index.ts` here to skip — the one
query validator lives inline in the controller.

## The underlying capture mechanism

The actual "copy the row before it's deleted" behavior isn't application
code at all — it's a database trigger created in migration
`20260913202_custom_universal_deleted_records_archive.sql`, referenced
directly in `recordsArchive.types.ts`'s doc comment. This feature only
reads and manages what that trigger has already written; nothing in
`server/src/features/recordsArchive/` performs the capture itself.

### Related shared module: the soft-archive gate

`server/src/shared/archive/archiveGuard.ts` is a separate, smaller shared
helper — not part of this feature's own code, but worth knowing about
since both concern "archiving." It exports two guard functions used by
Products, Staff, and Customers/Pets before their own archive/hard-delete
actions:

- **`assertInactiveBeforeArchive(isActive, entityLabel)`** — throws a 403
  unless the entity is already deactivated (`is_active === false`), so
  nothing still in active use can be archived by accident.
- **`assertArchivedBeforeHardDelete(archivedAt, entityLabel)`** — throws a
  403 unless the entity already has an `archived_at` timestamp, so nothing
  can be permanently deleted without first passing through the archived
  state.

These guard a row's own `is_active`/`archived_at` flags on its _original_
table — a completely different mechanism from `deleted_records_archive`,
which only fires once a row is physically `DELETE`d.

## How it connects

The client UI lives under `client/src/features/staff/` rather than a
`recordsArchive` feature folder — `pages/AdminArchivePage/AdminArchivePage.tsx`
is the routed page (`/staff/admin/archive`),
`components/DeletedRecordsArchiveList/DeletedRecordsArchiveList.tsx` renders
the list/search/restore/purge UI, and `api/recordsArchive.api.ts` wraps the
four endpoints above. Access is Admin/Superadmin only
(`ADMIN_ROLES`), the same tier that manages the rest of Settings > Config.
Because the capturing trigger watches every table, this feature acts as a
last-resort recovery path across the whole app — a deleted customer, pet,
booking, product, or any other row can be found and restored here even
though its own feature has no "undo" of its own.

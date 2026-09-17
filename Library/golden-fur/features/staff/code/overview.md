---
title: Staff — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, staff]
project: golden-fur
---

Everything about running a staff member's account: who can log in and as
what role, each role's own dashboard, requesting/approving time off, the
branch-wide Monthly Schedule calendar, front-desk customer lookup and
walk-in registration, and the two-step archive workflow (soft-archive, then
restore or permanently delete) used across the app.

**Part of:** [[M01-staff-authentication-access-control|M01 · Staff Authentication & Access Control]]

## Client-side (`client/src/features/staff/`)

### pages/
- **`StaffDashboardPage.tsx`** — The one landing page every role shares after
  login (`/staff/dashboard/:roleSlug`). It looks up the signed-in staff
  member's profile, maps their role to a dashboard "slug"
  (`ROLE_TO_DASHBOARD_SLUG`), and redirects to their own canonical slug if
  the URL doesn't match — so nobody can browse to another role's dashboard
  by editing the address bar. Superadmin additionally sees an extra row of
  at-a-glance widgets (cage availability, recent transactions, branch
  revenue, all four service queues); Veterinarian and Receptionist each get
  their own smaller widget row.
- **`StaffManagementPage.tsx`** — Admin/Superadmin-only. Lists every staff
  member (filterable by role, and by branch for Superadmin), with an inline
  "Create staff account" panel at the top and, per staff card, expandable
  "Set day(s) off" and "Manage account" panels. Figures out the viewer's own
  role by finding their own row in the staff list (the Supabase session
  itself carries no app-level role claim).
- **`CustomerManagementPage.tsx`** — Front-desk customer/pet lookup for
  Receptionist, Admin, Supervisor, Superadmin. Lets staff register a new
  walk-in customer, and per customer row opens a "…" action menu (Check
  Profile / View Pets / Add Pet / Deactivate / Archive).
- **`DaysOffPage.tsx`** — Self-service page every role can reach from their
  own dashboard: shows the caller's current availability badge and the form
  to request time off (a quick "rest of today" action, or a custom range/
  full day with a reason and leave type).
- **`MySchedulePage.tsx`** — Read-only monthly calendar of the signed-in
  staff member's own rest days and approved leave (what a manager plotted
  for them on the Monthly Schedule). Every role can see this; it only ever
  shows the viewer's own entries.
- **`MonthlySchedulePage.tsx`** — Admin/Supervisor/Superadmin-only,
  branch-wide calendar for plotting every staff member's Rest Day/Vacation/
  Sick Leave. Two views (Calendar and a spreadsheet-style Staff Grid), a
  branch switcher for Superadmin, and an "Add schedule entry" modal with its
  own staff search/filter — additions here are always full-day and always
  auto-approved (a manager acting on someone else's behalf never has to wait
  for review).
- **`UnavailabilityApprovalQueuePage.tsx`** — Admin/Supervisor/Superadmin-
  only queue of pending self-requested day-off blocks, with search/sort
  (soonest, requested-earliest, staff name) and a branch filter for
  Superadmin. Approve/deny is optimistic (removed from the list immediately,
  rolled back with a fresh reload if the request fails).
- **`AdminArchivePage.tsx`** — Admin/Superadmin-only. One tabbed page
  (Products / Staff / Customers & Pets / Discounts / Promos / Packages /
  Deleted Records) for the final decision on anything already soft-archived
  elsewhere: Restore it, or permanently delete it. The "Deleted Records" tab
  is a different, broader thing — see `DeletedRecordsArchiveList.tsx` below.
- **`StaffPetProfilePage.tsx`** — Staff-side counterpart to the customer
  portal's own pet profile page, reached by clicking "View Pets" from
  Customer Management. Reuses the same `PetDetailPanel` component the
  customer-facing portal uses.

### components/dashboard/
Per-role dashboard widgets, all small "fetch on mount, render a summary"
components used by `StaffDashboardPage.tsx`.
- **`DashboardTile.tsx`** — A generic clickable tile (link, or a button when
  `onSelect` is given) used to build the Settings > Config sub-navigation;
  renders "Coming soon" when a tile has no destination yet.
- **`QueueWidgetCard.tsx`** — Shared shell for a "count + latest item, click
  through to the full queue" card. Reused by five of the widgets below so
  each only has to supply its own fetch and labels.
- **`GroomingQueueWidget.tsx`**, **`HotelQueueWidget.tsx`**,
  **`DaycareQueueWidget.tsx`**, **`VeterinaryConsultationQueueWidget.tsx`** —
  Superadmin dashboard widgets, each reusing the same queue endpoint its own
  full staff page calls, showing a count and the next/latest item.
- **`VeterinaryMyPatientsWidget.tsx`**, **`VeterinaryCatalogWidget.tsx`** —
  Veterinarian-only widgets: the vet's own patient roster and their saved
  medication/procedure catalog.
- **`DaysOffWidget.tsx`** — The caller's own availability badge with a
  click-through to Days Off; not a `QueueWidgetCard` since a status isn't a
  count.
- **`ReceptionistBookingsQueueWidget.tsx`** — The Receptionist dashboard's
  larger widget: today's whole booking queue broken into "awaiting online
  payment," "ready to check in," and "in service" counts, with an alert
  banner when unconfirmed online bookings need attention.
- **`AssessmentQueueWidget.tsx`** — Receptionist widget summarizing pending
  Initial Assessment/Reassessment bookings for the branch.
- **`CreditReviewQueueWidget.tsx`** — Receptionist/Cashier widget summarizing
  pending downpayment-to-credit reviews for manually-reviewed cancellations.
- **`CageOccupancyWidget.tsx`** — Receptionist widget: per-size-category cage
  availability badges (Available/Occupied/Reserved/Under Maintenance) for the
  viewer's own branch.

### components/ (other)
- **`cards/StaffCard/StaffCard.tsx`** — One staff member's summary card
  (avatar/initials, name, role, branch, availability badge, and a resend-
  account-email button) — the building block of `StaffManagementPage`'s grid.
- **`badges/UnavailabilityBlockBadge/UnavailabilityBlockBadge.tsx`** — Reads
  Supabase directly (not the REST API) to check whether a staff member has an
  active block covering *right now*, and renders "Available" / "Off until
  HH:MM" / "Full day off."
- **`buttons/ResendEmailButton/ResendEmailButton.tsx`** — Re-sends the
  original account-created credential email without generating a new
  password; used on both the creation-confirmation screen and an existing
  staff member's card.
- **`review/UnavailabilityReviewCard/UnavailabilityReviewCard.tsx`** — One
  pending day-off request in the approval queue: staff identity, the
  requested window, an optional "Requested for" reviewer, Approve/Deny
  buttons (Deny expands an optional reason field). Shows a "not reviewable"
  note instead of action buttons when the row is the viewer's own request.
- **`ArchiveList/ArchiveList.tsx`** — Generic, reusable list for any
  already-soft-archived entity (products, staff, customers, pets, discounts,
  promos, packages): Restore is one click, permanent delete goes through a
  confirmation dialog. `AdminArchivePage` plugs in different fetch/restore/
  delete functions per tab rather than duplicating this component per entity.
- **`DeletedRecordsArchiveList/DeletedRecordsArchiveList.tsx`** — A separate,
  broader archive: every row ever hard-deleted from *any* table app-wide,
  captured automatically by a database trigger. Supports filtering by table,
  search, sort, pagination, viewing the captured JSON snapshot, restoring it
  back into its original table, or purging the archive entry itself.
- **`forms/CreateStaffAccountForm/CreateStaffAccountForm.tsx`** — Admin/
  Superadmin form to create a new staff login (username, email, display
  name, role, and — since both roles now have full branch-assignment parity
  — a branch picker). Shows the temporary password as a fallback after
  creation alongside a resend-email button.
- **`forms/ManageStaffAccountForm/ManageStaffAccountForm.tsx`** — Promote/
  demote role or transfer branch (Superadmin-only fields), deactivate/
  reactivate (Admin or Superadmin), and archive (once deactivated).
- **`forms/UnavailabilityBlockForm/UnavailabilityBlockForm.tsx`** — The Days
  Off request form: a one-click "take the rest of today off" quick action,
  or a custom form (entire day vs. a specific time range, leave type,
  optional reason, and — for self-service only — an optional "send to"
  reviewer picker). Validates client-side with the same Zod schema the
  server uses before submitting.
- **`forms/NewWalkInCustomerForm/NewWalkInCustomerForm.tsx`** — Two-step
  walk-in registration: check whether an account already exists for the
  entered email, then either update that existing profile or create a new
  one (a random unusable password is generated since walk-ins don't set
  their own at intake).
- **`forms/AvatarUploader/AvatarUploader.tsx`** — Drag-and-drop or click-to-
  browse profile photo uploader with client-side type/size validation before
  the file is sent to the server.

### api/
- **`staff.api.ts`** — Every `fetch` call to the `/staff/*` REST endpoints:
  profile read/update, username change, avatar upload, unavailability block
  CRUD and review, branch schedule, staff list, account create/manage/
  archive/restore/hard-delete, and resend-account-email.
- **`recordsArchive.api.ts`** — Calls the `/staff/deleted-records/*`
  endpoints (list with filters, list distinct tables, restore, purge) behind
  the universal Deleted Records archive.

### config/ and modules/validators/
- **`config/staffDashboard.config.ts`** — The single source of truth for
  every role's dashboard: which tiles appear, in what order, under what
  section headings, with what icon. `toSidebarSections()` flattens this same
  config for the navigation sidebar, so the dashboard tiles and sidebar links
  can never drift apart.
- **`modules/validators/staff.validator.ts`** — Zod schemas mirroring the
  server's own validators (profile update, avatar file type/size, create-
  unavailability-block, review decision) so bad input is caught before the
  round trip to the server.

### Other
- **`staff.routes.ts`** — Registers every `/staff/*` page route under
  `StaffAuthGuard` (the client-side route guard, not to be confused with the
  server's role checks).
- **`staff.types.ts`** — Shared TypeScript types: `StaffRole`,
  `StaffProfile`, the unavailability-block shapes, and the create/manage
  payload types. Mirrored closely by the server's own `staff.types.ts`.

`*.module.css` files (one per component/page) are omitted from this guide —
pure styling, no logic.

## Server-side (`server/src/features/staff/`)

### Controller & routes
- **`staff.controller.ts`** — Every `/staff/*` request handler: profile
  read/update, self-service username change, avatar upload (with its own
  Multer error handler), staff account create/manage/archive/restore/hard-
  delete, resend-account-email, and the full unavailability-block
  lifecycle (create, cancel, list, review, list-pending, list-branch-
  schedule). Each handler checks `req.user` (set by the JWT middleware),
  authorizes the specific action (self vs. admin, same-branch vs.
  Superadmin-wide), validates the body with a Zod schema, then delegates to
  a service function and translates its thrown error into an HTTP status.
- **`staff.routes.ts`** — Wires each endpoint to `jwtMiddleware` →
  `sessionTimeoutMiddleware` → `requireRole(...)` → `requireBranch` → the
  controller. `requireRole` is called with different role sets per route:
  `ALL_STAFF_ROLES` for anything self-service, `ADMIN_ROLES` for staff-CRUD
  and archive actions, and `UNAVAILABILITY_MANAGER_ROLES` (Admin/Supervisor/
  Superadmin) for reviewing requests and viewing branch/pending schedules.

### Services
- **`staffManagement.service.ts`** — Creating a staff account is the most
  involved flow here: checks username/email aren't already taken, creates
  the Supabase Auth user with a randomly-generated temporary password,
  inserts the `staff_profiles` row (rolling back the orphaned Auth user if
  that insert fails), then three best-effort side steps that never fail
  account creation itself if they error — encrypting the temp password at
  rest (so a later resend can re-deliver it), emailing the credentials via
  Brevo, and writing an in-app "account created" notification. Also handles
  promote/demote/branch-transfer (Superadmin-only), deactivate, the
  archive → restore → hard-delete chain (which also deletes the underlying
  Supabase Auth user), and the self-service username change.
- **`unavailabilityBlock.service.ts`** — The core of the Days Off feature.
  `createUnavailabilityBlock()` resolves the actual start/end window three
  different ways depending on the request (quick action = now until end of
  branch shift; full day = that date's branch operating hours; custom range
  = the given times), checks it doesn't overlap an existing block for that
  staff member, and inserts it — self-requests land as `pending`, anything
  created on someone else's behalf is auto-approved. `reviewUnavailabilityBlock()`
  is Admin/Supervisor/Superadmin-only and explicitly blocks reviewing your
  own request even though the service bypasses RLS. `listBranchSchedule()`
  backs the Monthly Schedule calendar, and `listPendingUnavailabilityBlocks()`
  backs the approval queue, flagging the viewer's own pending row as
  non-reviewable rather than hiding it.
- **`staffAvailability.service.ts`** — A read-side reference implementation
  that computes a staff member's open time windows for a date range by
  intersecting branch operating hours with their approved unavailability
  blocks. Explicitly documented as not the real availability check used by
  booking — that's the `get_staff_availability()` Postgres function (see the
  M01 module note) — this service exists for inspection/testing of the same
  3-condition logic in application code.
- **`avatarUpload.service.ts`** — Validates the file (type, size), uploads it
  to the `avatars` Supabase Storage bucket under a per-staff folder, deletes
  any previous avatar file for that staff member, and updates
  `staff_profiles.profile_photo_url` to the new public URL.
- **`resendAccountEmail.service.ts`** — Decrypts the temp password stored at
  account-creation time and re-sends the same Brevo email as-is (does not
  generate a new password). Returns a 409 once the staff member has logged
  in for the first time, since the stored credential is cleared at that
  point and would otherwise be stale.

### Types & validators
- **`staff.types.ts`** — `ALL_STAFF_ROLES` (the 8 roles) and the three role-
  group constants routes/services check against: `ADMIN_ROLES`,
  `ANNOUNCEMENT_SENDER_ROLES`, and `UNAVAILABILITY_MANAGER_ROLES` (each
  deliberately a different set, so widening one never accidentally widens
  another). Also `StaffProfile`, the unavailability-block shapes, and
  `UNAVAILABILITY_LEAVE_TYPES` (`Rest Day` is manager-only, never self-
  service).
- **`modules/validators/staff.validator.ts`** — Zod schemas for profile
  update (`.strict()`, deliberately excludes role/branch/username), the
  Admin-manage payload (role/branch/is_active, at least one required),
  account creation, and the self-service username change.

## How it connects

A staff member's own dashboard (`StaffDashboardPage.tsx`) and its widgets
call `/staff/*` and other features' own queue endpoints, all scoped
server-side to the caller's branch (except Superadmin). Time-off requests
flow through `unavailabilityBlock.service.ts` into the same
`staff_unavailability_blocks` table that the booking flow's Slot/Staff
Picker reads via `get_staff_availability()` — see
[[M01-staff-authentication-access-control|M01]]'s own "Staff availability"
section for that Postgres-side check. Creating a staff account touches
Supabase Auth (login), `staff_profiles` (the app-level profile), and the
Brevo-backed account-created email; archiving/hard-deleting a staff account
also removes the underlying Auth user so there's no dangling login. The
Archive page's "Deleted Records" tab is unrelated to any single feature — it
reads from a database trigger that fires on every table's deletes, wired up
by a Supabase migration rather than any feature's own service code.

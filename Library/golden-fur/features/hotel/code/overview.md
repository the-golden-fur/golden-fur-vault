---
title: Hotel — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, hotel]
project: golden-fur
---

Lets front-desk staff check a pet into an overnight cage, record its feeding/walking/playtime/medication instructions, track those tasks on a shared daily checklist, and check the pet back out with any extension fee calculated. It also covers the admin screen for managing the physical cage inventory.

**Part of:** [[M05-pet-hotel-boarding-management]]

## Client-side (`client/src/features/hotel/`)

### api/

- **`hotel.api.ts`** — every fetch call this feature makes to the server: check-in/checkout, cage suggestion, the cage grid and cage CRUD, care-log-entry actions (complete/start/reopen), listing stays and the activity log, and two read-only helpers (`listFoodCatalog`/`listMedicationCatalog`) that now read from the shared product catalog rather than a hotel-only table.

### components/

- **`CageStatusGrid/CageStatusGrid.tsx`** — the cage picker grid, grouped by size (S/M/L/XL) with a colored status badge per cage. Admin/Superadmin get a "Mark Under Maintenance"/"Mark Available" menu on each card; clicking an Available cage (when a `onSelectCage` callback is passed) selects it for check-in. Refetches whenever `refreshSignal` changes.
- **`HotelBookingPicker/HotelBookingPicker.tsx`** — the searchable/filterable list of Hotel bookings shown on the Check In tab. Cross-references `GET /hotel/stays` so a booking that's already been checked in shows "Already checked in" with a "Go to checkout" link instead of a Check In button.
- **`HotelStayPicker/HotelStayPicker.tsx`** — the same pattern for the Check Out tab: a searchable/filterable list of active (or, when widened, completed) stays, defaulting to "all dates" so an overdue stay still shows up.
- **`BoardingChecklistKanban/BoardingChecklistKanban.tsx`** — the Kanban board of the day's care tasks (feeding/walking/playing/medication), shared with Daycare via a Hotel/Daycare tab switch. Cards live in columns grouped by Status, Time of day, or Category (switchable); clicking a card's checkbox advances it Pending → In Progress → Completed, and clicking a completed checkbox reopens it to Pending. Backlog (not due yet) and Missed (date has passed) are read-only.
- **`TimeInput/TimeInput.tsx`** — a native `<input type="time">` paired with a "quick pick" dropdown of common times, used anywhere staff enter a walking/playtime/medication time. `formatTimeValue.ts` turns a 24-hour `"HH:MM"` value into a human string like `"7:00 AM"` for that dropdown's labels.

### pages/

- **`HotelQueuePage/HotelQueuePage.tsx`** — the main Hotel Queue screen, with Check In and Check Out tabs. The Check In tab's "Check in" button on a row checks the pet in immediately using whatever the customer entered at booking time (see `buildQuickCheckInPayload.ts`); success/failure shows as a modal. The old separate Check-in/Checkout pages/routes now redirect here — `HotelLegacyRedirects.tsx` keeps `/staff/hotel/check-in` and `/staff/hotel/checkout(/:stayId)` working by forwarding to this page with the right tab/stay preselected via query params.
- **`HotelQueuePage/buildQuickCheckInPayload.ts`** — builds the one-click check-in payload straight from a booking's saved `hotel_preferences`, letting the server auto-resolve the cage and (when no medication was named) auto-fill from the pet's current prescription.
- **`HotelQueuePage/HotelCheckInPanel.tsx`** — the detailed check-in form reached from a queue row's "..." menu → "View booking details". Shows the auto-suggested cage and the booking's feeding/walking/playing/medication instructions read-only, with a single "Edit" toggle to unlock and correct them before submitting. This is also where a pet's current prescription (from Veterinary) gets folded into the medication list.
- **`HotelQueuePage/HotelCheckoutPanel.tsx`** — the checkout confirmation/result panel: shows the downpayment already collected, any extension fee, and the remaining balance once checkout succeeds.
- **`HotelQueuePage/hotelQueueRoles.ts`** — the one-line role list (`HOTEL_QUEUE_VIEWER_ROLES`: Admin/Supervisor/Superadmin/Groomer/Pet Assistant, deliberately excluding Receptionist) shared by the queue page and the routed check-in form.
- **`HotelCheckInFormPage/HotelCheckInFormPage.tsx`** — the routed wrapper around `HotelCheckInPanel`, reached at `/staff/hotel/queue/check-in/:bookingId`. Loads the booking and re-runs the queue's own role gate since it's its own route now.
- **`BoardingChecklistPage/BoardingChecklistPage.tsx`** — hosts the Kanban board (`BoardingChecklistKanban`) at `/staff/hotel/care-log`. When reached with `?petId=...` from the Daycare Queue, it scopes the board to that one pet and adds a "Check out" section (reusing Daycare's own checkout panel) since Daycare's queue no longer has its own per-row checkout button.
- **`ActivityLogPage/ActivityLogPage.tsx`** — a read-only, filterable logbook of everything that happened (check-ins, check-outs, task started/completed/reopened/missed), newest first. Each row already carries a server-generated human-readable description.
- **`AdminCagesPage/AdminCagesPage.tsx`** — Admin/Superadmin-only screen to add, rename/resize, or delete cages at their branch, plus the same Under Maintenance toggle `CageStatusGrid` offers. A cage that's Occupied or Reserved can't be deleted.

### Other files

- **`hotel.types.ts`** — the client-side TypeScript shapes for cages, stays, care instructions, and the checklist/activity-log entries — mirrors the server's own `hotel.types.ts`.
- **`hotel.routes.tsx`** — wires the pages above into `/staff/hotel/*` routes, all behind `StaffAuthGuard`.
- **`utils/careScheduleBounds.ts`** — figures out whether a meal time (Morning/Noon/Afternoon/Evening) actually applies on check-in day or checkout day, based on whether that meal's clock-time window has already passed by check-in time or hasn't started yet by checkout time.

The `.module.css` files paired with each component/page are pure styling with no logic and are skipped here as boilerplate.

## Server-side (`server/src/features/hotel/`)

### Controller & routes

- **`hotel.controller.ts`** — one exported function per endpoint (check-in, cage suggestion, current-prescription lookup, care-log-entry complete/start/reopen, care-log listing, activity log, cage grid/available-counts, cage status/CRUD, stay listing, checkout). Each pulls the caller's branch/role off the authenticated request, validates the body/query with a Zod schema, calls into a service, and turns a thrown `statusCode`-carrying error into the right HTTP response.
- **`hotel.routes.ts`** — maps each controller to a path under `/hotel/*`, gated by `jwtMiddleware` + `sessionTimeoutMiddleware` + `requireRole([...])` + `requireBranch`. Most read/write routes allow `HOTEL_ADVANCE_ROLES` (front desk + Groomer + Pet Assistant); cage maintenance and cage CRUD are `HOTEL_ADMIN_ROLES`-only (Admin/Superadmin).

### Services

- **`cageAssignment.service.ts`** — `suggestCage` reads a pet's weight class and pet type and returns the matching-size, matching-pet-type Available cages at the branch. `assignCage` claims a specific cage by flipping it to Occupied only if it's still Available (an optimistic, conditional-update "claim" — no real DB transaction is available here), rejecting with a 409 if someone else grabbed it first. `releaseCage` puts a cage back to Available if a later check-in step fails after the cage was already claimed.
- **`cageStatus.service.ts`** — the cage-grid read (`getCageGrid`, grouped S/M/L/XL), the available-cage-count read used by the booking Slot Picker, the Admin-only maintenance toggle (`setCageMaintenanceStatus`, also a conditional update guarded on the cage's current status), and full CRUD (`createCage`/`updateCage`/`deleteCage`) for the Cages admin page — including keeping each cage's `cage_pet_types` junction rows in sync, and refusing to delete a cage that's Occupied or Reserved.
- **`careInstructions.service.ts`** — this is the file most worth reading carefully; it's the heart of check-in. `checkInHotelStay` validates the booking (must be a Pending or already-In-Progress Hotel booking, not already checked in, belongs to the caller's branch), resolves and claims a cage via `resolveAndClaimCage` (an explicit override or the auto-suggested one), inserts a `stays` row, advances the booking to In Progress, writes the feeding/walking/playing/medication instruction rows, and then calls `generateCareLogEntries` to expand those instructions into one `care_log_entries` row per scheduled action per day of the stay (via `enumerateDates`) — this is what populates the Boarding Checklist. If anything fails after the cage was claimed, the cage is released back to Available so a failed check-in never strands an Occupied cage with nothing behind it. Medications are auto-filled from the pet's current prescription (via M07) only when the request omits the `medications` field entirely.
- **`careLogCompletion.service.ts`** — reads and mutates individual checklist tasks. `getCareLogEntries` lists tasks for a branch/date-range and applies two read-time-only relabelings: `applyMissedTransition` flips any Pending/In Progress task whose date has passed to `Missed` (a real DB write, since it's a terminal state), while `applyBacklogLabel` relabels a still-Pending task scheduled for a future date as `Backlog` for display only (never written to the database — it "resolves" itself once the date arrives). `startCareLogEntry`/`completeCareLogEntry`/`reopenCareLogEntry` drive the Kanban board's Pending → In Progress → Completed → (back to Pending) transitions, each firing an activity-log entry. `assertChecklistComplete` is the checkout gate: it blocks checkout while any task is still Pending or In Progress (Missed and Backlog tasks don't block).
- **`careLogNotifications.service.ts`** — fires an in-app notification (and, only if the branch has per-task email enabled via policy configuration, an email) to the pet's owner whenever a checklist task is completed. Off by default for email since a stay generates many tasks per day and would otherwise blow through the Brevo daily send quota.
- **`checkout.service.ts`** — `checkOutHotelStay` re-validates the stay belongs to the branch and its booking is still In Progress, blocks checkout via `assertChecklistComplete` if the checklist isn't done, computes any late-checkout extension fee (`extensionDays` rounds any partial late day up to a full day, at a flat `EXTENSION_FEE_PER_DAY` placeholder rate), advances the booking to Completed, and — guarded by a conditional update on `actual_check_out_at IS NULL` so two simultaneous checkout requests can't both "win" — marks the stay Completed and releases the cage back to Available.
- **`hotelStay.service.ts`** — `listHotelStays` backs both the check-in picker's "already has a stay" cross-reference and the checkout picker's searchable list, reading a stay's real progress off its joined booking's `status` rather than a separate stay-status column.
- **`activityLog.service.ts`** — `recordActivity`/`recordBulkActivity` write best-effort, non-blocking rows to the `activity_log` table (a failure here must never fail the real action it's logging) for check-in, checkout, and every task status change. `listActivityLog` reads them back newest-first for the Activity Log page, optionally scoped to one stay or a date range.

### Types & validators

- **`hotel.types.ts`** — the server-side shapes for cages, stays, the four care-instruction tables, and checklist entries, plus the feature's role lists (`HOTEL_FRONT_DESK_ROLES`, `HOTEL_ADMIN_ROLES`, `HOTEL_ADVANCE_ROLES`).
- **`modules/validators/hotel.validator.ts`** — Zod schemas for every request body/query this feature accepts. Rejects, for example, a feeding row with no quantity, a cage-status update to anything other than `Available`/`Under Maintenance`, or a new cage with an empty `pet_types` list (a cage must support at least one pet type). The feeding/walking/playing/medication instruction schemas are also reused as-is by the Daycare feature, since both write to the same shared tables.

## How it connects

A check-in click on `HotelQueuePage` calls `checkInHotelStay` via `POST /hotel/check-in`, which claims a cage (`cages`/`cage_pet_types`), writes a `stays` row and the four `care_*_instructions` tables, expands them into `care_log_entries` for the [[M05-02-boarding-checklist-task-lifecycle|Boarding Checklist]], and advances the booking's status (shared with [[M03-appointment-booking]]). The Boarding Checklist Kanban then drives those `care_log_entries` through [[M05-02-boarding-checklist-task-lifecycle|its own lifecycle]], firing customer notifications ([[M11-notification]]) on completion. Checkout (`POST /hotel/stays/:id/checkout`, see [[M05-03-hotel-checkout|Hotel Checkout]]) gates on the checklist being clear, completes the booking, reconciles the stay's total price against its downpayment plus any extension fee (feeding into [[M08-sales-billing]]), and releases the cage. Every one of these actions also writes a row to `activity_log`, read back on the Activity Log page.

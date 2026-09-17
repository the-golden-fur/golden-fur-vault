---
title: Grooming — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, grooming]
project: golden-fur
---

Grooming is the smallest of the four service queues: a Groomer (or a
manager role) opens their queue of today's grooming appointments and
advances each one from Pending to In Progress ("Start") and then to
Completed ("Complete"). There's no cage/room logic here — the interesting
part is how little state Grooming keeps of its own, since the underlying
booking's status is the single source of truth.

**Part of:** [[M04-grooming-management]]

## Client-side (`client/src/features/grooming/`)

### pages/

- **`GroomerDashboardPage/GroomerDashboardPage.tsx`** — the whole feature's
  UI. Gates access to `Groomer`/`Admin`/`Supervisor`/`Superadmin`
  (`ALLOWED_VIEWER_ROLES`), then loads today's queue via `listGroomingQueue`
  and re-polls it every 15 seconds (`REFRESH_INTERVAL_MS`) since the app has
  no WebSocket/realtime layer yet — this is a deliberately simple polling
  loop rather than new infrastructure. It also loads service/package names
  (`listServices`/`listPackages`) to label each appointment's line items,
  and each session's pet/owner via `getPet`/`getCustomerProfile`. Supports
  date-range and status filtering, search by pet/owner name, and sorting by
  queue position or pet name. `handleAdvance` calls
  `transitionGroomingStatus` and replaces the updated session in local state
  with the response (which already comes back with its booking re-joined).

### components/

- **`AppointmentCard/AppointmentCard.tsx`** — one card per queue entry.
  Shows the pet/owner, weight class, coat type, service labels, and special
  instructions. Its one Start/Complete button is driven by a small lookup
  table (`ADVANCE_ACTION`) keyed off the booking's status: `Pending` shows
  "Start" (targets `In Progress`), `In Progress` shows "Complete" (targets
  `Completed`), and any other status shows no button at all — there's no
  "reopen" path once a session is Completed.

### api/

- **`grooming.api.ts`** — `listGroomingQueue` (optional `dateFrom`/`dateTo`)
  and `transitionGroomingStatus` (PATCH the session's status to `'In
Progress'` or `'Completed'`), both thin `fetch` wrappers returning a
  `{ data, error }` shape.

### Types & routing

- **`grooming.types.ts`** — `GroomingSession`: just `id`, `booking_id`,
  `assigned_groomer_id`, `queue_position`, timestamps, and an optional
  joined `booking`. Notably has **no status field of its own** — the
  session's real execution state lives entirely on the joined booking
  (`session.booking.status`).
- **`grooming.routes.tsx`** — one staff-guarded route,
  `/staff/grooming/queue` → `GroomerDashboardPage`; the role check itself
  happens inside the page, not the route.

## Server-side (`server/src/features/grooming/`)

### Controller & routes

- **`grooming.controller.ts`** — `listGroomingQueueController` reads the
  requester's id/role/branch off the authenticated request plus optional
  `date_from`/`date_to` query params and calls the service.
  `transitionGroomingStatusController` validates the body against
  `transitionGroomingStatusValidator` and calls
  `transitionGroomingSessionStatus`. Both map thrown errors (with a
  `statusCode`) to the matching HTTP response.
- **`grooming.routes.ts`** — `GET /grooming/queue` and
  `PATCH /grooming/sessions/:id/status`, both behind `jwtMiddleware`,
  `sessionTimeoutMiddleware`, `requireRole(GROOMING_QUEUE_ROLES)`, and
  `requireBranch`.

### Service

- **`services/grooming.service.ts`** — the core logic, in two functions.
  `listGroomingQueue` queries `bookings` for `service_category: 'Grooming'`,
  `status: 'In Progress'` only, within the resolved date range (defaults to
  today in UTC), excluding any booking that still needs an unpaid
  downpayment. It then scopes by role — a `Groomer` sees only their own
  assigned bookings, `Admin`/`Supervisor` are branch-scoped, `Superadmin`
  sees everything — and **lazily creates** (`insert`) a `grooming_sessions`
  row for any matching booking that doesn't have one yet, denormalizing
  `assigned_groomer_id` from the booking at that moment. There's no
  database trigger for this; the queue endpoint itself is what vivifies
  rows. Results are sorted by `queue_position` when both compared rows have
  one set, otherwise falling back to the booking's `scheduled_start`.
  `transitionGroomingSessionStatus` checks that the requester is either the
  assigned groomer or a manager role (`MANAGER_ROLES`), then just calls the
  shared `startBooking`/`completeBooking` functions from the booking
  feature — Grooming keeps no state machine of its own; any invalid-
  transition error simply propagates up from those shared functions.

### Types & validators

- **`grooming.types.ts`** — `GROOMING_QUEUE_ROLES` (Groomer, Admin,
  Supervisor, Superadmin) and the server copy of the `GroomingSession`
  interface (same shape as the client's).
- **`modules/validators/grooming.validator.ts`** —
  `transitionGroomingStatusValidator`: a single Zod schema requiring
  `status` to be exactly `'In Progress'` or `'Completed'`.

## How it connects

Grooming appointments and their `assigned_staff_id`/downpayment state come
from [[M03-appointment-booking]]; Start/Complete just call that feature's
own `startBooking`/`completeBooking`, which is why Grooming has no status
column of its own. Pricing (packages, size/coat rules) is configured in
[[M13-maintenance-packages-services-promos]], and completing a session
feeds billing in [[M08-sales-billing]]. See
[[M04-01-grooming-queue-population]] for the full queue-visibility flow and
diagram, and [[M04-02-grooming-session-execution]] for the Start/Complete →
billing handoff.

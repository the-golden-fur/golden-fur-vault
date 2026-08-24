# Issue #68 Verification: Groomer Dashboard UI — queue view + status buttons

**Issue:** #68 — feat(grooming): Groomer Dashboard UI — queue view + status buttons
**Owner:** James
**Branch:** `feat/groomer-dashboard-ui`
**Base:** `dev`
**Depends on:** #64 merged
**Sprint:** Sprint 3 Epic A — M04 Grooming Management

## Overview

`GroomerDashboardPage` at `/staff/grooming/queue` — today's grooming appointments assigned to the logged-in groomer (Admin/Supervisor/Superadmin see every session at their branch), sorted by queue order, one `AppointmentCard` per session with pet/owner/breed/size/coat/service/add-ons/special-instructions, and a single status-advance button (Waiting → In Progress → Completed).

## What Changed

- **Added** `client/src/features/grooming/grooming.types.ts`, `client/src/features/grooming/api/grooming.api.ts` (+spec) — client mirror of #64's `GroomingSession`/`GroomingStatus`, `listGroomingQueue()`/`transitionGroomingStatus()`.
- **Added** `client/src/features/grooming/components/GroomingStatusBadge/GroomingStatusBadge.tsx` (+spec) — Waiting/In Progress/Completed pill using the 3 new `--color-grooming-status-*` tokens (`client/src/styles/tokens.css`).
- **Added** `client/src/features/grooming/components/AppointmentCard/AppointmentCard.tsx` (+spec) — one card per session; the single status-advance button hides once `Completed` (#64's backend has no "reopen" path).
- **Added** `client/src/features/grooming/pages/GroomerDashboardPage/GroomerDashboardPage.tsx` (+spec) — role gate (`Groomer`/`Admin`/`Supervisor`/`Superadmin`, same `ALLOWED_VIEWER_ROLES` pattern as `UnavailabilityApprovalQueuePage`), queue fetch + 15s poll, client-side pet/owner/service-name resolution.
- **Added** `client/src/features/grooming/grooming.routes.tsx`; **modified** `client/src/routes.tsx` (registers it) and `client/src/features/staff/dashboards/staffDashboard.config.ts` (Groomer dashboard's "Grooming Queue" tile now links to `/staff/grooming/queue`, per the config's own "only the tile gains a `to`" convention).

### Decision flagged for the reviewer: pet/owner/service names are resolved client-side

`GET /grooming/queue` (#64) only joins `booking:bookings(*, booking_addons(*))` — no pet/customer/service names. Rather than modifying #64's already-merged backend (out of this issue's Affected Files, which name only client paths), the dashboard resolves names itself: unique `pet_id`s via `getPet()`, `customer_id`s via `getCustomerProfile()` (both already exist, M02), and `service_id`/`package_id`/add-on `service_id`s via `listServices()`/`listPackages()` (M13) — the same "join client-side" precedent `ReceptionistBookingsQueuePage` (#60) already established for branch names. **Raise with Alarie if #64's queue endpoint should instead be extended to embed these directly** (would reduce round-trips at scale, but is backend work outside #68's stated scope).

### Decision flagged for the reviewer: "refreshes without a manual reload" (AC-5) is polling, not push

No WebSocket/Supabase-Realtime subscription exists anywhere else in this client codebase to model this on. The dashboard instead re-fetches the queue every 15 seconds. This satisfies AC-5's observable behavior (a change made elsewhere appears without the user reloading) at the cost of up to a 15s delay. **Raise with Alarie if a tighter latency requirement (i.e. real push) was actually intended** — that would be a larger, cross-cutting addition (a realtime subscription layer), not a one-page change.

## Acceptance Criteria Map

| AC                                                                                                                   | Automated                                                        | Manual UI                       |
| -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------- |
| AC-1 dashboard shows today's grooming appointments assigned to the logged-in groomer, in queue order                 | `GroomerDashboardPage.spec.ts`                                   | step D3                         |
| AC-2 each card displays pet name, owner name, breed, size, coat type, service/package, add-ons, special instructions | `AppointmentCard.spec.ts`                                        | step D3                         |
| AC-3 status buttons advance Waiting → In Progress → Completed and disable/hide once Completed                        | `AppointmentCard.spec.ts`, `GroomerDashboardPage.spec.ts`        | step D4                         |
| AC-4 completing an appointment makes the booking queryable for the future Cashier view                               | covered by #64's own `grooming.service.spec.ts` (unchanged here) | step D4 (Supabase Studio check) |
| AC-5 a change made elsewhere is reflected without a manual reload                                                    | design note above (15s poll)                                     | step D5                         |

## Automated Verification

```powershell
npm --prefix client test -- --run src/features/grooming
npm --prefix client run lint
npm --prefix client run build
```

Expected: 4 test files / 12 tests pass; lint 0 errors/warnings; `tsc -b && vite build` succeeds with no type errors.

## Manual UI Verification

### Prerequisites

- Server running (`npm --prefix server run dev`) with migrations through `040` pushed.
- Client running (`npm --prefix client run dev`).
- One **Groomer** account at a branch (Sprint 1 seed data, e.g. `makati.groomer1@goldenfur.com` / `password123`).
- A **Confirmed Grooming booking** scheduled for **today**, assigned to that groomer — create one via the customer/receptionist booking flow (`/staff/bookings/new`), or reuse #51's booking collection with today's date.

### D. Steps

1. Log in to the staff portal (`/staff/login`) as the Groomer.
2. From the staff dashboard, click **Grooming Queue** (or navigate directly to `/staff/grooming/queue`).
3. Confirm the appointment card shows: pet name, owner name, breed, weight class and coat type badges, the service/package name, any add-ons, and special instructions (if the test booking had any) — and that the status badge reads **Waiting**.
4. Click **Mark In Progress** → badge updates to **In Progress**, button now reads **Mark Completed**. Click it → badge updates to **Completed**, and the button disappears entirely (AC-3). In Supabase Studio → Table Editor → `bookings`, confirm the row's `status` is now `Completed` (AC-4).
5. In a second browser tab/window logged in as an Admin/Supervisor at the same branch, use Supabase Studio (or a re-run of #64's Postman collection) to reassign or re-trigger the session; within ~15 seconds the first tab's dashboard should reflect the change without a manual refresh (AC-5).

### E. Cleanup

Supabase Studio → Table Editor → `grooming_sessions` → filter by the `booking_id` used above → delete the row. The underlying `bookings` row can stay `Completed` or be deleted alongside.

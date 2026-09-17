---
title: Branches — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, branches]
project: golden-fur
---

Branches is the system-configuration record for Golden Fur's two physical
locations (Makati and Southwoods): name, address, contact number, whether
it's the vet-capable branch, timezone, and a per-weekday open/close
schedule. It's server-only — there's no dedicated `branches` folder on the
client. Every other feature that needs a branch (the booking flow's Date &
Time step, staff-name dropdowns, the Services/Packages/Promos multi-selects)
either reads the `branches` table directly through Supabase Row-Level
Security or goes through this feature's full CRUD API only when it needs to
create or edit a branch.

**Part of:** [[M01-staff-authentication-access-control]]

## Server-side (`server/src/features/branches/`)

### Controller & routes

- **`branches.controller.ts`** — four handlers: `listBranchesController`,
  `getBranchController`, `createBranchController`,
  `updateBranchController`. Create/update parse the request body with the
  Zod validators below and return a 400 with issue details on failure;
  every handler funnels thrown service errors through a shared
  `sendServiceError` helper that reads a `statusCode` off the error (or
  falls back to a generic 500).
- **`branches.routes.ts`** — mounts `GET /branches`, `POST /branches`,
  `GET /branches/:id`, and `PATCH /branches/:id`, all behind
  `jwtMiddleware`, `sessionTimeoutMiddleware`, and `requireRole` restricted
  to `BRANCH_CONFIG_ROLES` (Superadmin only). A comment in the file is
  explicit about why: this is the full read/write "Superadmin System
  Configuration" API, deliberately separate from the lightweight
  `branches` SELECT every authenticated staff member already gets for
  free via RLS (used elsewhere for plain name dropdowns) — operating
  hours, address, and contact number are treated as config details that
  only Superadmin should see, not just edit.

### Service

- **`services/branches.service.ts`** — plain Supabase CRUD, no business
  logic beyond error mapping: `listBranchesFull` (all branches,
  alphabetical), `getBranch` (404 if missing), `createBranch` (409 if the
  name is already taken — detected via Postgres's `23505` unique-violation
  code), and `updateBranch` (same 409 handling, 404 if the id doesn't
  exist). Every function throws a plain `Error` tagged with a
  `statusCode` property via a local `throwWithStatus` helper, which is
  what the controller's `sendServiceError` reads back out.

### Types & validators

- **`branches.types.ts`** — the `Branch` interface (id, name, address,
  contact_number, is_vet_branch, operating_hours, timezone, created_at),
  `BRANCH_CONFIG_ROLES` (`['Superadmin']`), the `WEEKDAYS` tuple, and the
  `OperatingHours` type — a `Partial<Record<Weekday, {open, close}>>`
  where a day simply absent from the map means the branch is closed that
  day (matching the convention `availability.service.ts` uses elsewhere).
- **`modules/validators/branches.validator.ts`** — Zod schemas
  `createBranchValidator` and `updateBranchValidator`. Both validate
  `operating_hours` per-day with a `HH:MM` (24h) regex and a refinement
  that `open` must be before `close`; `createBranchValidator` requires
  name/address/timezone and defaults `operating_hours` to `{}` (closed
  every day until configured) and `is_vet_branch` to `false`;
  `updateBranchValidator` makes every field optional for partial patches.
  Both are `.strict()`, so an unrecognized field is rejected rather than
  silently dropped.

`branches.routes.ts` is the only barrel-like entry point here — there's no
separate `index.ts` to skip.

## How it connects

Superadmin manages branches from the System Configuration page inside
Settings > Config (see [[M01-staff-authentication-access-control]]'s
"System Configuration — branch creation" section) — the client calls this
API through `client/src/features/maintenance/api/branches.api.ts`
(`listBranchesFull`, `createBranch`, `updateBranch`), even though the page
itself lives under the Staff/Admin area rather than a `branches` client
feature folder. Once configured, branch `operating_hours` and `timezone`
drive [[M03-appointment-booking]]'s Date & Time slot generation and
[[M01-staff-authentication-access-control]]'s `get_staff_availability()`
function (shift-end/closed-day resolution). Every other feature that just
needs a branch name for a dropdown (Services/Packages/Promos branch
multi-selects in [[M13-maintenance-packages-services-promos]], staff
assignment, etc.) reads the `branches` table directly via Supabase RLS
instead of calling this API, since that plain SELECT is open to any
authenticated staff member and doesn't need the config-level detail this
feature guards behind Superadmin.

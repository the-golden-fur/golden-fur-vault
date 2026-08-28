---
title: Golden Fur — System Architecture
date: 2026-08-26
tags: [architecture, golden-fur, reference]
project: golden-fur
---

# Golden Fur — System Architecture

Golden Fur is a capstone management information system (MIS) for a
two-branch pet care business (**Makati** and **Southwoods**) offering
grooming, pet hotel, daycare, and veterinary services. Veterinary is
Makati-only; every other service category is offered at both branches.

It ships as two applications sharing one Supabase backend:

- A **customer-facing booking portal** — registration, pet profiles,
  booking, self-service payment, credits, transaction history.
- A **role-scoped staff console** for Superadmin, Admin, Supervisor,
  Receptionist, Groomer, Veterinarian, Cashier, and Pet Assistant —
  running bookings, service execution queues, billing, promos/discounts,
  and customer/pet records.

## System topology

Three top-level workspaces in one repo:

```
golden-fur/
├── client/     React + Vite frontend (customer portal + staff console)
├── server/     Express + TypeScript API
└── supabase/   Database schema, migrations, seeds, edge functions
```

`client` and `server` are independent npm workspaces, run together in
development via the root `npm run dev` (`concurrently`). Both talk to the
same Supabase project.

```
Browser (React SPA)
    │  Supabase JS client — auth session, direct reads guarded by RLS
    ▼
Supabase (Postgres 17 + Auth + Storage)
    ▲
    │  service-role client — privileged operations, cross-table business rules
Express API (server/)
```

The client goes straight to Supabase for session management and
RLS-guarded reads, and to the Express API for anything needing
server-side validation, cross-table business rules, or the service-role
key (which never reaches the browser).

## Tech stack

| Layer         | Technology                                                  |
| ------------- | ----------------------------------------------------------- |
| Frontend      | React 19, TypeScript, Vite, React Router, Zod               |
| Backend       | Node.js, Express, TypeScript, Zod                           |
| Database/Auth | Supabase (PostgreSQL 17, Auth, Storage, Row-Level Security) |
| Testing       | Vitest, Testing Library, Supertest                          |
| Tooling       | ESLint, Prettier, GitHub Actions CI                         |

## Repository layout

**Client (`client/src/`)**

- `pages/` — top-level routed pages not tied to one feature (landing,
  home, profile, settings, app shell).
- `features/<name>/` — one folder per business domain, each with
  `api/` (Supabase/API calls), `components/`, `pages/`,
  `<name>.routes.tsx`, `<name>.types.ts`.
- `shared/` — cross-feature code: API client, auth context, reusable
  components, hooks, providers.
- `routes.tsx` — top-level route table.

**Server (`server/src/`)** mirrors the client's feature layout:

- `features/<name>/` — `*.controller.ts`, `*.routes.ts`, `*.types.ts`,
  plus `modules/`/`services/` for domain logic and `tests/` per feature.
- `shared/` — Express app wiring, auth middleware, shared services,
  centralized error handling, config.
- `app.ts` — Express entry point.

**Database (`supabase/`)**

- `migrations/` — timestamped, numbered SQL migrations, one change per
  file. Every table's RLS policy is defined alongside its creation
  migration.
- `schemas/` — declarative schema definitions for local diffing.
- `seeds/` — TypeScript seed scripts populating realistic sample data.
- `functions/` — Edge Functions (reserved for future use).

## Feature folders → business domain

The actual `features/` folders (same names on client and server, except
`branches` which is server-only) are more granular than the 14-module
spec — several folders implement one module, and a few modules share
infrastructure with another:

| Folder              | Primary module(s)                                                                                                                                                           |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auth`              | [[M01-staff-authentication-access-control\|M01]]                                                                                                                            |
| `staff`             | [[M01-staff-authentication-access-control\|M01]]                                                                                                                            |
| `branches` (server) | [[M01-staff-authentication-access-control\|M01]] system configuration                                                                                                       |
| `customers`         | [[M02-customer-portal-pet-management\|M02]]                                                                                                                                 |
| `booking`           | [[M03-appointment-booking\|M03]], [[M09-policy-enforcement\|M09]] (policy config + cancellation/reschedule logs live here)                                                  |
| `grooming`          | [[M04-grooming-management\|M04]]                                                                                                                                            |
| `hotel`             | [[M05-pet-hotel-boarding-management\|M05]]                                                                                                                                  |
| `daycare`           | [[M06-daycare-management\|M06]]                                                                                                                                             |
| `veterinary`        | [[M07-health-veterinary-management\|M07]]                                                                                                                                   |
| `billing`           | [[M08-sales-billing\|M08]]                                                                                                                                                  |
| `credits`           | [[M10-credit-balance-management\|M10]]                                                                                                                                      |
| `notifications`     | [[M11-notification\|M11]]                                                                                                                                                   |
| `messaging`         | [[M11-notification\|M11]] (provider dispatch)                                                                                                                               |
| `discounts`         | [[M12-discount-management\|M12]]                                                                                                                                            |
| `maintenance`       | [[M13-maintenance-packages-services-promos\|M13]]                                                                                                                           |
| `catalog`           | Customer-owned food/medication catalog, feeding [[M05-pet-hotel-boarding-management\|M05]]/[[M06-daycare-management\|M06]] — not the services/packages catalog (that's M13) |
| `reports`           | [[M14-report-management\|M14]]                                                                                                                                              |
| `public`            | Cross-cutting: unauthenticated marketing routes (no `jwtMiddleware`), not a business module                                                                                 |

## Domain model at a glance

- Two physical **branches**: Makati and Southwoods.
- **Staff roles**: Superadmin, Admin, Supervisor, Receptionist, Groomer,
  Veterinarian, Cashier, Pet Assistant — each with a role-scoped
  dashboard and permission tier enforced in both the UI and RLS/API.
- **Customers** manage **pets**, which flow through **bookings** for one
  of five `service_category` values: Grooming, Hotel, Daycare,
  Veterinary, and Misc (pet weight/coat assessment — not a
  customer-selectable booking category).

## Module map

The product is specified as 14 modules (M01–M14). As of this writing
(reconciled against dev HEAD as of 2026-08-09, cross-checked against
`features/` folders present in the repo on 2026-08-26) **all 14 are
implemented** — the module status table in the repo's own
`docs/architecture.md` is stale and still marks eight of them "Planned."

| #                                                 | Module                                    | Layer       | Note                                                     |
| ------------------------------------------------- | ----------------------------------------- | ----------- | -------------------------------------------------------- |
| [[M01-staff-authentication-access-control\|M01]]  | Staff Authentication & Access Control     | Foundation  | Entry point: login, TOTP, roles, staff availability      |
| [[M02-customer-portal-pet-management\|M02]]       | Customer Portal & Pet Management          | Foundation  | Data backbone for booking/billing/vet                    |
| [[M03-appointment-booking\|M03]]                  | Appointment & Booking                     | Foundation  | Booking wizard, Slot/Staff/Cage Picker, status lifecycle |
| [[M04-grooming-management\|M04]]                  | Grooming Management                       | Operations  | Groomer execution queue                                  |
| [[M05-pet-hotel-boarding-management\|M05]]        | Pet Hotel (Boarding) Management           | Operations  | Cage assignment, Boarding Checklist                      |
| [[M06-daycare-management\|M06]]                   | Daycare Management                        | Operations  | Shares Hotel's stays table                               |
| [[M07-health-veterinary-management\|M07]]         | Health & Veterinary Management            | Operations  | Makati-only clinical console                             |
| [[M08-sales-billing\|M08]]                        | Sales & Billing                           | Back-office | Checkout, PayMongo, Payments Queue                       |
| [[M09-policy-enforcement\|M09]]                   | Policy Enforcement                        | Back-office | Rules engine for cancel/reschedule                       |
| [[M10-credit-balance-management\|M10]]            | Credit Balance Management                 | Back-office | Branch-locked customer credit                            |
| [[M11-notification\|M11]]                         | Notification                              | Back-office | Email + in-app, per-event preferences                    |
| [[M12-discount-management\|M12]]                  | Discount Management                       | Back-office | Standing per-branch discounts                            |
| [[M13-maintenance-packages-services-promos\|M13]] | Maintenance (Packages, Services & Promos) | Back-office | Catalog, pricing, promos, Service Types                  |
| [[M14-report-management\|M14]]                    | Report Management                         | Back-office | DSR, cage occupancy, analytics                           |

## Cross-cutting mechanics worth knowing

- **Booking status is a 5-value enum** — `Pending → In Progress →
Completed`, plus `Cancelled` and a lazy, read-time `No-show`.
  `payment_stage` (`Unpaid → Paid in Advance → Paid`) is a fully
  independent field, not a status value — a booking can sit at
  `Completed` + `Unpaid` simultaneously.
- **Bookings Queue / Payments Queue split** — the Receptionist Bookings
  Queue is read-only (view/reschedule/cancel/create only). Every
  status- and payment-advancing action lives on category-specific
  execution queues ([[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]]) or the
  dedicated Payments Queue ([[M08-sales-billing|M08]]).
- **Downpayment is a per-transaction policy field**, not a catalog
  attribute — configured system-wide or per branch in
  [[M09-policy-enforcement|M09]], resolved against the whole booking's
  total at creation time in [[M03-appointment-booking|M03]].
- **`get_staff_availability()`** (a Postgres function) is the single
  source of truth for staff availability, consumed by the Slot/Staff
  Picker in [[M03-appointment-booking|M03]].
- **Row-Level Security everywhere** — every table's RLS policy ships in
  the same migration that creates the table.
- **Notification preferences are per-event-type**, stored as `jsonb` on
  `staff_profiles`/`customer_profiles`, checked before every dispatch —
  see [[M11-notification|M11]].

## Known gaps (as of 2026-08-09)

- **Credit redemption at checkout is a stub** — issuance, balances, and
  expiry are real ([[M10-credit-balance-management|M10]]), but a cashier cannot yet apply a
  customer's credit to a transaction total ([[M08-sales-billing|M08]]).
- **Reschedule fees are calculated and logged but never posted** as a
  billable line item at checkout ([[M09-policy-enforcement|M09]], [[M08-sales-billing|M08]]).
- A **Service Type beyond the seeded four** (Grooming/Hotel/Daycare/
  Veterinary) can be created in the admin UI but has no real
  availability/capacity/pricing logic behind it ([[M13-maintenance-packages-services-promos|M13]]).
- `cage_picker_enabled` on Service Types is hardcoded Hotel-only
  regardless of its stored value for other categories.
- Precedence between Policy Configuration's per-branch Staff/Cage
  Picker toggle and Service Types' global per-type toggle is
  unconfirmed.

Full list: see the Roadmap section carried into each affected module
note, or the source doc referenced below.

## Since this was reconciled (2026-08-09 → 2026-08-26)

Veterinary ([[M07-health-veterinary-management|M07]]) picked up several PRs not yet reflected in the
source doc: a vet catalog, a "My Patients" view, a Completed column on
the queue, a schedule-follow-up flow, and RBAC gating so only the
Veterinarian role can write to the console (PRs #112–#115).

## Sources

- `golden-fur/AGENTS.md` and `golden-fur/docs/architecture.md` (system
  layout, tech stack — architecture-level parts still accurate).
- `Projects/golden-fur/docs/context/architecture/Modules-Features.docx`
  ("Latest" edition, compiled 2026-08-11, reconciled against dev HEAD
  commit `ffd9ac2` as of 2026-08-09) — primary source for module detail;
  described by the doc itself as grounded directly in the codebase
  rather than the `Architectural-Change-Suggestions` tracker.
- `golden-fur/client/src/features/` and `golden-fur/server/src/features/`
  directory listings, and `git log`, checked live on 2026-08-26 to
  confirm module status and catch drift since the doc's cutoff.

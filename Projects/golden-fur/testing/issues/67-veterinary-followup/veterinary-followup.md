# Issue #67 Verification: follow-up scheduling backend — creates Pending M03 booking

**Issue:** #67 — feat(veterinary): follow-up scheduling backend — creates Pending M03 booking
**Owner:** Matthew
**Branch:** `feat/veterinary-followup`
**Base:** `dev`
**Depends on:** #66 merged
**Sprint:** Sprint 3 Epic A — M07 Health & Veterinary Management

## Overview

`POST /veterinary/consultations/:id/follow-up` — creates a new `bookings` row with `status = 'Pending'` from a completed or in-progress consultation, and sets `consultations.follow_up_booking_id` on the originating consultation so the console can show "follow-up already scheduled" without a second query.

## What Changed

- **Added** `server/src/features/veterinary/services/followUp.service.ts` (+spec, 3 tests) — `scheduleFollowUp()`.
- **Added** `scheduleFollowUpValidator` to `server/src/features/veterinary/modules/validators/veterinary.validator.ts` (added alongside #66's validators in the same file, rather than a second validator module for one schema).
- **Added** `POST /veterinary/consultations/:id/follow-up` to `server/src/features/veterinary/veterinary.routes.ts` (created together with #66's routes — see #66's own verification doc for that decision note).

### Decision flagged for the reviewer: the follow-up booking's placeholder slot

Per the dev notes, the created booking "does not set a specific time slot" — the receptionist's confirmation step is what actually runs it through the Slot Picker. Since `bookings.scheduled_start`/`scheduled_end` are both `NOT NULL` with a `scheduled_end > scheduled_start` check, `scheduleFollowUp()` anchors the placeholder at 9:00 AM UTC on the chosen `follow_up_date`, with a duration copied from the originating booking. This value is never shown to a customer and is expected to be overwritten by the eventual confirmation step. **Raise with Alarie if a different placeholder convention (e.g. branch opening time in branch-local time) was intended.**

### Decision flagged for the reviewer: "the normal M03 confirmation flow" (AC-4) doesn't fully exist yet

AC-4 says receptionist confirmation of the pending follow-up booking "proceeds through the normal, unmodified M03 confirmation flow." What exists today: the booking is created `Pending` and is immediately visible in the Receptionist Bookings Queue (#60, no change needed — it already reads off `bookings.status`) and is reschedulable (`reschedule.service.ts` already permits `Pending` bookings, from #54). What does **not** exist anywhere in this codebase yet is a "confirm this Pending booking → Confirmed" action — `booking.service.ts` already carries its own `TODO(Sprint 5, M08)` marking that promotion as cashier-confirmation scope (Sprint 5). This issue creates the Pending booking correctly; the "confirmation flow" itself is out of scope until M08 ships. **Raise with Alarie/the Sprint 5 reviewer if AC-4 was meant to imply a promotion path should exist sooner.**

## Acceptance Criteria Map

| AC                                                                                                                                            | Automated                                                                   | Postman                  |
| --------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------ |
| AC-1 setting a follow-up date on a Completed/Ongoing consultation creates a Pending booking with correct pet/customer/branch/service_category | `followUp.service.spec.ts`                                                  | request 6                |
| AC-2 the originating consultation's `follow_up_booking_id` is set to the new booking's id                                                     | `followUp.service.spec.ts`                                                  | request 6                |
| AC-3 the new Pending booking is visible in the Receptionist Bookings Queue without any additional query changes                               | not unit-tested (integration behavior of an already-merged feature, #60)    | request 7                |
| AC-4 receptionist confirmation proceeds through the normal M03 flow                                                                           | see decision note above — the promotion path itself is Sprint 5 (M08) scope | not exercised — see note |

Also covered: rejecting a follow-up on a still-`Pending` (not-yet-started) consultation, and rejecting a second follow-up once one is already scheduled (both `followUp.service.spec.ts` and Postman requests 4/8).

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all 54 test files / 499 tests pass (3 new in `followUp.service.spec.ts`, alongside #66's 11 landing in the same pass); typecheck silent; lint 0 errors (3 pre-existing `no-console` warnings, unrelated).

## Postman Verification

### Prerequisites

- Migrations through `040` pushed (`supabase db push`) — no new migration in this issue.
- One **Veterinarian** account and one **Receptionist** account, both at Makati (Sprint 1 seed data, password `password123`).
- A **Confirmed Veterinary booking** at Makati for **today**, assigned to that Veterinarian.

### A. Collect the IDs (Supabase Studio)

1. `bookings` — the `id` of today's Confirmed Veterinary booking at Makati (`vet_booking_id`).

### B. Import and configure

1. Postman → **Import** → `testing/docs/issues/67-veterinary-followup/veterinary-followup.postman_collection.json`.
2. Open the collection → **Variables** tab → fill `base_url`, `vet_email`/`vet_password`, `receptionist_email`/`receptionist_password`, `vet_booking_id`. Leave tokens/`consultation_id`/`follow_up_booking_id` blank.
3. Save (Ctrl+S).

### C. Start the server

```powershell
npm --prefix server run dev
```

### D. Run requests 1→8 in order (top to bottom)

Each request carries its own tests — the **Test Results** tab must be green:

1. **Login Veterinarian** → 200, token captured.
2. **Login Receptionist** → 200, token captured.
3. **GET consultation queue (Vet)** → 200; consultation for `vet_booking_id` captured (still `Pending` at this point).
4. **POST follow-up on a Pending consultation** → **409** (cannot schedule a follow-up before the consultation has started).
5. **PATCH → Ongoing** (Vet) → 200.
6. **AC-1/AC-2 POST follow-up** (Vet) → **201**; new booking `status = "Pending"`, `service_category = "Veterinary"`; consultation's `follow_up_booking_id` matches the new booking's `id`, `follow_up_date = "2026-08-15"`.
7. **AC-3 Receptionist GET /bookings?status=Pending** → 200; the new follow-up booking appears in the list.
8. **POST a second follow-up on the same consultation** → **409** (already scheduled).

### E. Cleanup

Supabase Studio → Table Editor → `bookings` → delete the follow-up booking row (`follow_up_booking_id` value from step 6). Then `consultations` → delete or clear the original consultation row used in this run.

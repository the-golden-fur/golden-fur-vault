# Issue #73 Verification: care_instructions tables (feeding / walking / medication)

**Issue:** #73 — chore(db): care_instructions tables (feeding / walking / medication)
**Owner:** Matthew
**Branch:** `chore/hotel-care-instructions-schema`
**Base:** `dev`
**Depends on:** #72 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

Creates the three structured care-instruction tables so #75 has real tables to write into at check-in and Care Log generation has a real source to read from: `care_feeding_instructions`, `care_walking_instructions`, `care_medication_instructions` — three tables, not one wide table, since each is a fixed-shape structured form (feeding is per-meal-time, walking is per-time-block, medication is per-drug).

## What Changed

- **Added** `supabase/migrations/20260727052_m05_create_care_instructions_schema.sql`:
  - `care_feeding_instructions`: `hotel_stay_id` (FK), `meal_time` (`Morning`/`Afternoon`/`Evening`, checked), `food_type`, `quantity`, `special_instructions` (nullable).
  - `care_walking_instructions`: `hotel_stay_id`, `time_block`, `duration_minutes` (checked `> 0`), `notes` (nullable).
  - `care_medication_instructions`: `hotel_stay_id`, `medication_name`, `dose`, `scheduled_times` (`jsonb`, array of time strings), `administration_notes` (nullable), `source_prescription_note` (nullable text — a one-time copy reference, **not** a live FK back to `consultations`, so a receptionist's free edits here never write back to the M07 clinical record).
  - Indexes on `hotel_stay_id` for all three.
  - **RLS** (identical pattern across all three): Receptionist/Admin/Supervisor full read/write at their own branch (resolved via `hotel_stays → cages.branch_id`); **Pet Assistant read-only** — explicitly no INSERT/UPDATE/DELETE grant, enforcing "pet assistants may only mark Care Log entries complete, never edit the underlying instructions" at the database layer.

## Acceptance Criteria Map

| AC                                                                          | Where verified                           |
| --------------------------------------------------------------------------- | ---------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with #72 applied)               | `supabase db push` below                 |
| AC-2 all three tables have the DB-Design columns/constraints/defaults       | SQL script section 1                     |
| AC-3 Pet Assistant can SELECT but not INSERT/UPDATE/DELETE any of the three | SQL script section 2 + manual test below |
| AC-4 Receptionist/Admin/Supervisor have full read/write at their branch     | manual test below                        |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Database Verification (Supabase)

1. **Apply migrations:**

   ```powershell
   supabase db push
   ```

2. **Studio → SQL Editor**, paste `hotel-care-instructions-schema.sql` (this folder) and **Run** — every row `pass = true`.

3. **AC-3/AC-4 manual RLS test** — uncomment the `RLS IMPERSONATION TEST` block, fill in one Pet Assistant UUID and one Receptionist UUID at the branch of an existing `hotel_stays` row (create one via #75's Postman collection first). Run the whole block:
   - Pet Assistant: SELECT returns rows; a raw `UPDATE`/`INSERT` attempt affects 0 rows / errors.
   - Receptionist: SELECT/INSERT/UPDATE all succeed.

## Notes

- `care_medication_instructions.source_prescription_note` is a plain text note (e.g. "Pre-filled from consultation \<id\> completed \<timestamp\>"), populated only by #75's auto-fill path when a current M07 prescription exists — never set for a receptionist-entered row, per the DB Design sheet's explicit "not a live FK" note.
- The `NOT NULL` constraints on `scheduled_times` (default `'[]'::jsonb`) mean an inserted medication row always has an array present, even before the receptionist fills in real times — #75's Care Log generation treats an empty array as "as scheduled" rather than skipping the entry.

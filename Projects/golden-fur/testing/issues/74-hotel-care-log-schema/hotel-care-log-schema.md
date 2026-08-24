# Issue #74 Verification: care_log_entries table

**Issue:** #74 — chore(db): care_log_entries table
**Owner:** Matthew
**Branch:** `chore/hotel-care-log-schema`
**Base:** `dev`
**Depends on:** #73 merged
**Sprint:** Sprint 4 Epic A — M05 Pet Hotel (Boarding) Management

## Overview

Creates the Care Log schema so #75/#76/#77 have a real table and RLS to build against: `care_log_entries` — one row per scheduled care action per day of the stay, generated automatically at check-in.

## What Changed

- **Added** `supabase/migrations/20260727053_m05_create_care_log_entries_schema.sql`:
  - `care_log_entries`: `hotel_stay_id` (FK), `care_type` (`Feeding`/`Walking`/`Medication`, plain text — not a polymorphic FK across the three instruction tables, since the only consumer is display grouping), `scheduled_date`, `description` (human-readable checklist label generated at creation), `completed_at` (nullable, **server-set only**, never app-supplied), `completed_by` (nullable FK to `staff_profiles`), `created_at`.
  - Indexes on `hotel_stay_id`, `scheduled_date`, and a partial index on `scheduled_date` where `completed_at is null` (backs #77's end-of-day flagging query).
  - **RLS:** Pet Assistant may **SELECT only** rows for stays at their own branch — no INSERT/UPDATE/DELETE grant exists for this role at all; completion goes through #76's service-role completion path, never a raw RLS-governed UPDATE. Receptionist/Admin/Supervisor may SELECT all rows at their branch. No staff INSERT policy for any role — rows are created only by #75's check-in service.

## Acceptance Criteria Map

| AC                                                                                                                      | Where verified                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with #73 applied)                                                           | `supabase db push` below                                                                                                         |
| AC-2 `care_log_entries` has the DB-Design columns/constraints/defaults                                                  | SQL script section 1                                                                                                             |
| AC-3 Pet Assistant can update only completed_at/completed_by via the completion function, cannot insert/delete directly | manual test below + #76's Postman                                                                                                |
| AC-4 `completed_at` cannot be set to a past timestamp through the completion path                                       | #76's `careLogCompletion.service.spec.ts` (`completed_at` is always `new Date().toISOString()`, never accepted from the request) |

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

2. **Studio → SQL Editor**, paste `hotel-care-log-schema.sql` (this folder) and **Run** — every row `pass = true`.

3. **AC-3 manual RLS test** — uncomment the `RLS IMPERSONATION TEST` block, fill in a Pet Assistant UUID at the branch of an existing `care_log_entries` row (generated automatically once you run #75's check-in Postman request). A raw `UPDATE ... SET completed_at = now()` attempted as the Pet Assistant must affect 0 rows (RLS grants no UPDATE at all for this role) — completion only ever succeeds through #76's `PATCH /hotel/care-log-entry/:id/complete` endpoint, which uses the server's service-role client.

## Notes

- Unlike `staff_unavailability_blocks`' self-approval design (which uses row-level `USING`/`WITH CHECK` predicates to restrict _which_ rows a role can touch), `care_log_entries` restricts Pet Assistant at the _policy-existence_ level — no UPDATE policy names this role at all, so there is no column to even attempt bypassing at the SQL layer. The actual "only completed_at/completed_by, forced server-side" guarantee lives entirely in #76's `careLogCompletion.service.ts`, which runs under the service-role client (RLS bypassed) and only ever sets those two columns.

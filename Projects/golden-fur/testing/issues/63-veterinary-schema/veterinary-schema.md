# Issue #63 Verification: consultations + consultation_line_items + procedure_type enum

**Issue:** #63 — chore(db): consultations + consultation_line_items + procedure_type enum
**Owner:** Matthew
**Branch:** `chore/veterinary-schema`
**Base:** `dev`
**Depends on:** Issue #62 merged (sequential numbering); `branches.is_vet_branch` (M01, merged Sprint 0/1)
**Sprint:** Sprint 3 Epic A — M07 Health & Veterinary Management

## Overview

Creates the M07 veterinary clinical-record schema so #66 (consultation backend — **not** part of this batch) has real tables and RLS to build against: the `procedure_type` enum and `consultations` + `consultation_line_items`. `medications` is `jsonb` on `consultations` itself, not a separate table — Modules-Features is explicit that current-prescription derivation reads directly from a consultation's own `medications` and needs no separate prescription table or archiving step.

**Numbering note:** same renumbering as #61/#62 — this migration is `20260719040` (Guide assumed `...028`).

## What Changed

- **Added** `supabase/migrations/20260719040_m07_create_veterinary_schema.sql`:
  - `procedure_type` enum: `Lab test / Dental / Vaccination / Surgery / Emergency / Wellness Exam` (all 6 values, per DB Design).
  - `consultations` with the exact DB Design column set: `booking_id` (`UNIQUE`, FK), `pet_id` (denormalized, FK), `veterinarian_id` (FK — any Veterinarian may be assigned, no per-pet restriction), `status` (plain text, `'Pending'` default, `CHECK IN ('Pending','Ongoing','Completed')`), vitals (`temperature` / `weight` / `heart_rate` / `respiratory_rate`, all nullable `numeric`), `diagnosis`, `medications` (`jsonb`), `reason_for_visit` (`NOT NULL`), `follow_up_date`, `follow_up_booking_id` (nullable FK, set later by #67 — not this epic's scope), `completed_at`.
  - `consultation_line_items`: `consultation_id` (FK, `ON DELETE CASCADE`), `item_type` (`professional_fee` / `medication` / `procedure`), `procedure_type` (nullable, set only when `item_type = 'procedure'` — enforced by a `CHECK`), `description`, `amount` (`NOT NULL numeric(10,2)` — stored now even though M08/M14 don't consume it until Sprint 5/6, per Modules-Features Second Cut Slides 7–8 calling out vet revenue).
  - **RLS:** any authenticated Veterinarian may SELECT/INSERT/UPDATE any `consultations` row (no per-pet assigned-vet restriction, matching the explicit Modules-Features carve-out); Admin/Supervisor/Superadmin may SELECT all; Receptionist may SELECT (pet-history / follow-up visibility in the Receptionist Bookings Queue) but has **no** INSERT/UPDATE policy on clinical fields. `consultation_line_items` mirrors the same read tiers; it has no staff INSERT/UPDATE policy at all — those rows are written only by the server's service-role client (#66's `consultation.service.ts`, not this epic's scope) on status → Completed.

### Note on write-time Makati enforcement

The DB Design deliberately does **not** put the Makati-only restriction in a `CHECK` constraint here — a `CHECK` can't reach through `bookings → branches` to read `is_vet_branch`. That guard is application-layer, in #66's consultation-creation service (not built in this batch), mirroring Sprint 2 Epic B's `assertVeterinaryBranchEligibility` pattern. This migration only creates the tables/RLS; AC-3 (below) is therefore verified with a query showing the enforcement point exists at the schema level (no columns/constraints block it — the guard is correctly left to the service layer) rather than a schema-level rejection.

## Acceptance Criteria Map

| AC                                                                                        | Where verified                                                             |
| ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| AC-1 migration runs cleanly (fresh + on dev with #62 applied)                             | `supabase db push` below                                                   |
| AC-2 tables/columns/constraints/defaults per DB Design; `procedure_type` has all 6 values | SQL script section 1                                                       |
| AC-3 a consultation cannot be created against a Southwoods-branch booking                 | SQL script section 2 (schema-level note) — real enforcement lands with #66 |
| AC-4 RLS: any Veterinarian read/write; Receptionist read-only                             | SQL script section 3 + manual cross-role test below                        |

## Automated Verification

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

## Database Verification (Supabase)

1. **Apply migrations**:

   ```powershell
   supabase db push
   ```

   Expected: `20260719040` (and `038`/`039` if verifying the whole epic) apply cleanly. `supabase db reset` locally replays everything from scratch with zero errors. **Do not run `db reset` against the hosted project.**

2. **Open Supabase Studio → SQL Editor → New query**, paste all of `veterinary-schema.sql` (this folder) and **Run**. Expected: every row `pass = true`.

3. **AC-4 cross-role RLS test** (needs one Veterinarian account, one Receptionist account, and a seeded Makati Veterinary booking):
   1. In Studio → **Authentication → Users**, note the two staff UUIDs.
   2. Run the `-- RLS IMPERSONATION TEST` block at the bottom of the SQL file (uncomment it first). It seeds a `consultations` row (as service role) tied to a Makati Veterinary booking, then impersonates the Veterinarian (must SELECT/INSERT/UPDATE successfully) and the Receptionist (must SELECT successfully but fail an UPDATE attempt).

## Notes

- `consultations.follow_up_booking_id` and the `procedure_type` enum exist now purely as forward-compatible schema for #66/#67 — no code in this batch reads or writes them.
- `item_type` is plain `text`, deliberately not `procedure_type` — `professional_fee` and `medication` line items aren't procedures, and reusing the enum there would force meaningless values into it.

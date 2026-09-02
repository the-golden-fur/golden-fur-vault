---
title: "M14 · Cage Occupancy Report Generation"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M14
---

# M14 · Cage Occupancy Report Generation

**Actors:** Receptionist, Admin, Supervisor, Superadmin
**Code:** `server/src/features/reports/reports.controller.ts`,
`server/src/features/reports/reports.routes.ts`,
`server/src/features/reports/services/cageOccupancy.service.ts`,
`supabase/migrations/20260805101_m14_create_reporting_functions.sql`
**Part of:** [[M14-report-management|M14 · Report Management]]

A Receptionist, Admin, Supervisor, or Superadmin opens the Cage Occupancy
report to get a live count of every cage's status, grouped by size tier;
the result is computed directly off the current `cages` table, not a
snapshot or cached rollup.

```mermaid
flowchart TD
    A(["START: Receptionist / Admin / Supervisor /\nSuperadmin opens Cage Occupancy report"]) --> B{"Authenticated, session valid,\nrole in Superadmin/Admin/Supervisor/Receptionist,\nbranch resolved? (route middleware)"}
    B -- "No" --> C(["END: Blocked — unauthorized / forbidden\n(401 / 403)"])
    B -- "Yes" --> D{"Is requester a Superadmin?"}
    D -- "No" --> E["effective branch = requester's own branch_id\n(any branch_id passed is ignored)"]
    D -- "Yes" --> F["effective branch = branch_id passed,\nor null for combined-branches view"]
    E --> G["Call get_cage_occupancy_report(effective_branch)"]
    F --> G
    G --> H{"RPC returned an error?"}
    H -- "Yes" --> I(["END: Blocked — report generation failed (400)"])
    H -- "No" --> J["DB function groups current cages rows\nby size (S/M/L/XL) x status\n(Available/Occupied/Reserved/Under Maintenance)\nand counts each combination"]
    J --> K(["END: Cage occupancy rows returned\n(possibly empty array)"])
```

## Notes

- No date or date-range input exists for this report — it always reflects
  the current state of the `cages` table at the moment of the call.
- Same branch-scoping convention as the Daily Sales Report: Admin/
  Supervisor/Receptionist are pinned to their own branch regardless of
  any `branch_id` they pass; only a Superadmin can request a specific
  other branch or omit `branch_id` for a combined view across branches.
- Receptionist access here is a **later addition** (`CAGE_OCCUPANCY_READ_ROLES`)
  distinct from `REPORTS_READ_ROLES` (Superadmin/Admin/Supervisor), which
  still gates the DSR and Analytics endpoints — Receptionists cannot see
  those two.
- `get_cage_occupancy_report()` returns a plain row set (`size`, `status`,
  `cage_count`), not a wrapping jsonb object like the DSR function — the
  service returns `[]` if the RPC yields no rows rather than null.

## Relationship to other modules

Reads the `cages` table owned by
[[M05-pet-hotel-boarding-management|M05 · Pet Hotel/Boarding Management]].

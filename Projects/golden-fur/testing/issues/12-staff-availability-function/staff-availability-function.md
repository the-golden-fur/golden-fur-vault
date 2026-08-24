# Issue #12 Verification: Refactor DB - Rewrite get_staff_availability() to 3-Condition Check

**Issue:** #12 — refactor(db): rewrite `get_staff_availability()` to 3-condition check
**Branch:** `refactor/staff-availability-function`
**Sprint:** Sprint 1 — Epic A-1

## Overview

This issue replaces the stale four-condition availability logic with a single three-condition check that evaluates:

1. Whether the requested window falls within the branch operating hours for the staff member's branch.
2. Whether a confirmed booking overlap would exist (deferred to Sprint 2; the function now skips this check defensively when the `bookings` table is not present).
3. Whether the requested window overlaps any `staff_unavailability_blocks` row for that staff member.

---

## Verification Steps

### Step 1: Pull Latest Changes

```bash
git checkout dev && git pull origin dev
git checkout -b refactor/staff-availability-function
```

Confirm you are on the branch created for this issue.

### Step 2: Apply the Migration

Push the new migration to the linked Supabase project:

```bash
supabase db push
```

If the project is not linked yet, run the Supabase login/link tasks first.

### Step 3: Run the Verification SQL Script

Open the Supabase SQL Editor and run the file at:

```text
testing/docs/sprints/sprint1/epicA1/issue-12/supabase/issue12.sql
```

This script:

- creates or reuses a staff profile tied to an existing branch,
- inserts a sample unavailability block,
- verifies that an in-hours request is accepted when there is no overlap,
- verifies that an out-of-hours request is rejected,
- verifies that a request overlapping an unavailability block is rejected.

### Step 4: Confirm the Expected Results

Expected results from the script:

- `in_hours_available` returns `true`
- `outside_hours_unavailable` returns `false`
- `unavailability_overlap_unavailable` returns `false`

### Step 5: Spot-Check the Function Definition

Run this in the SQL Editor:

```sql
select proname, pg_get_functiondef(oid)
from pg_proc
where proname = 'get_staff_availability';
```

Pass criteria:

- The function exists in the `public` schema.
- It references `branches.operating_hours`.
- It references `staff_unavailability_blocks`.
- It no longer references `branches.break_window` or `staff_profiles.is_busy` / `busy_until`.

---

## Acceptance Criteria Checklist

- [x] **AC-1:** Checks branch operating hours for the requested window.
- [x] **AC-2:** Includes a placeholder booking-overlap check with a Sprint 2 TODO, and skips it safely when the bookings table is absent.
- [x] **AC-3:** Checks `staff_unavailability_blocks` for range overlap.
- [x] **AC-4:** No longer references `branches.break_window` or `staff_profiles.is_busy` / `busy_until`.
- [x] **AC-5:** Keeps the same function signature for existing callers.

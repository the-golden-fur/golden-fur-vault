# Issue #11 Verification: Refactor DB - Replace Busy Toggle with staff_unavailability_blocks

**Issue:** #11 — refactor(db): replace Busy toggle with `staff_unavailability_blocks`; remove `break_window`
**Branch:** `refactor/staff-unavailability-blocks`
**Sprint:** Sprint 1 — Epic A-1

## Overview

This issue replaces the boolean `is_busy` toggle with a time-bound `staff_unavailability_blocks` table, removes the unused `break_window` column from branches, and removes `busy_until` from staff_profiles.

---

## Migrations Created

| Migration   | File                                                     | Purpose                                                 |
| ----------- | -------------------------------------------------------- | ------------------------------------------------------- |
| 20260701010 | `20260701010_m01_drop_branches_break_window.sql`         | Drop `branches.break_window` column                     |
| 20260701011 | `20260701011_m01_drop_staff_profiles_busy_columns.sql`   | Drop `is_busy` and `busy_until` from staff_profiles     |
| 20260701012 | `20260701012_m01_create_staff_unavailability_blocks.sql` | Create `staff_unavailability_blocks` table with indices |
| 20260701013 | `20260701013_m01_staff_unavailability_blocks_rls.sql`    | Enable RLS and set policies                             |

> **Note:** Filenames were changed from `20260701_010_...` (underscore between date and sequence) to `20260701010_...` (no underscore) — see "Migration Filename Fix" below. This applied repo-wide to all 13 existing migrations (`20260625_001` → `20260625001`, etc.), not just this issue's files.

---

## Verification Steps

### Step 1: Pull Latest Changes

```bash
git checkout dev && git pull origin dev
```

Verify that Epic A (Issues #4–#10) is merged into dev.

### Step 2: Verify Branch Creation

```bash
git checkout refactor/staff-unavailability-blocks
```

Confirm you're on the branch created for this issue.

### Step 3: Run Migrations

Push the new migrations to the linked remote project:

```bash
supabase db push
```

You'll be prompted to confirm the list of pending migrations — type `y` and press Enter. Or run the **📤 Supabase: Push Migrations** VS Code task instead (see "VS Code Tasks for Supabase Management" below).

If you haven't linked this machine to the project yet, run **🔐 Supabase: Login** then **🔗 Supabase: Link Project** first (or `supabase login` / `supabase link` from the terminal).

### Step 4: Verify Column Drops (AC-1, AC-2)

Execute the following SQL in your Supabase database:

```sql
-- Check branches table no longer has break_window
select column_name from information_schema.columns
where table_name = 'branches' and column_name = 'break_window';
-- Expected: 0 rows

-- Check staff_profiles table no longer has is_busy or busy_until
select column_name from information_schema.columns
where table_name = 'staff_profiles' and column_name in ('is_busy', 'busy_until');
-- Expected: 0 rows
```

**Pass Criteria:**

- `break_window` column is gone from `branches` table
- `is_busy` and `busy_until` columns are gone from `staff_profiles` table

### Step 5: Verify Table Creation (AC-3, AC-4)

Execute the following SQL:

```sql
-- Check table exists and has required columns
select column_name, data_type, is_nullable
from information_schema.columns
where table_name = 'staff_unavailability_blocks'
order by ordinal_position;
```

**Pass Criteria:**

- Table `staff_unavailability_blocks` exists
- Has columns: `id` (uuid), `staff_id` (uuid), `start_time` (timestamptz), `end_time` (timestamptz), `reason` (text), `created_by` (uuid), `created_at` (timestamptz)
- `staff_id` has foreign key constraint to `staff_profiles(id) ON DELETE CASCADE`

### Step 6: Verify Foreign Keys (AC-4)

Execute:

```sql
-- Check foreign key constraints
select constraint_name, table_name, column_name, referenced_table_name, referenced_column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu using (constraint_name)
where table_name = 'staff_unavailability_blocks';
```

**Pass Criteria:**

- `staff_id` column has foreign key referencing `staff_profiles(id) ON DELETE CASCADE`
- `created_by` column has foreign key referencing `auth.users(id) ON DELETE CASCADE`

### Step 7: Verify Indices (Performance)

Execute:

```sql
-- Check indices
select indexname
from pg_indexes
where tablename = 'staff_unavailability_blocks'
order by indexname;
```

**Pass Criteria:**

- Index on `staff_id`
- Index on `created_by`
- Index on `(start_time, end_time)` for range queries

### Step 8: Verify RLS Policies (AC-5)

Execute:

```sql
-- Check RLS is enabled
select tablename, rowsecurity
from pg_tables
where tablename = 'staff_unavailability_blocks';
-- Expected: rowsecurity = true

-- List all policies
select policyname, permissive, roles, qual, with_check
from pg_policies
where tablename = 'staff_unavailability_blocks'
order by policyname;
```

**Pass Criteria:**

- RLS is enabled on the table
- Policies exist for staff (self-access: select, insert, update, delete)
- Policies exist for Admin/Superadmin (manage-all: select, insert, update, delete)

### Step 9: Smoke-Test the Table (AC-5)

Run `testing/docs/sprints/sprint1/epics/epicA1/supabase/issue11.sql` in the Supabase SQL Editor (Dashboard → SQL Editor → paste the whole file → Run). It inserts a test row using a real `staff_profiles` row, queries it back, checks the row count, then deletes the test row so the script is safe to re-run.

> **Why not `auth.uid()`?** The SQL Editor runs as the `postgres` role with no JWT session, so `auth.uid()` is always `NULL` there and RLS is bypassed entirely (the original version of this script tried `auth.uid()` and failed with `23502: null value in column "staff_id" violates not-null constraint`). The script now uses an existing `staff_profiles` row instead, so it only smoke-tests the table/FK constraints — it does **not** exercise the RLS policies themselves.

**Pass Criteria (smoke test):**

- Insert succeeds against the FK constraints (staff_id → staff_profiles, created_by → auth.users)
- The row is queryable back by its `reason`
- The row count reflects the insert
- The cleanup `delete` leaves 0 matching rows behind

**To actually verify RLS (AC-5), separately:**

- Dashboard → Authentication → Policies → use the policy tester against a real user, or
- Sign in via the client SDK as a staff member and confirm you can only select/insert/update/delete your own blocks, then sign in as an Admin/Superadmin and confirm you can do so for any staff member's blocks

---

## Migration Filename Fix (root cause of the `db push` failure)

Running `supabase db push` on this issue originally failed with:

```
ERROR: policy "Authenticated users can view branches" for table "branches" already exists (SQLSTATE 42710)
```

**Root cause:** Supabase derives each migration's tracking "version" from the leading run of digits in its filename (it stops at the first non-digit character). This repo's old naming convention, `YYYYMMDD_NNN_description.sql`, put an underscore right after the 8-digit date — so **every migration created on the same calendar day computed to the identical version number** (e.g. `20260625_001` through `20260625_009` all resolved to version `20260625`). The remote tracking table can hold only one row per version, so only the first migration of each day (`001`) ever got recorded as applied. Every other same-day migration was invisible to the tracker even though its SQL had already run successfully — so `supabase db push` kept re-attempting `002`'s non-idempotent `create policy` statement from scratch and hit "already exists" every time. The same collision would have hit `010`–`013` (all dated `20260701`) immediately after.

This was confirmed directly against the linked remote using `supabase db query --linked` (read-only): `branches`, `staff_profiles`, `customer_profiles`, their enums, and all pre-existing RLS policies already existed, but `supabase_migrations.schema_migrations` had only one row for the whole date `20260625`.

**Fix applied (repo-wide, not just this issue's files):** every existing migration filename had its underscore between the date and sequence number removed, so each file's leading digit-run is unique:

| Old filename                                      | New filename                                     |
| ------------------------------------------------- | ------------------------------------------------ |
| `20260625_001_m01_create_branches.sql`            | `20260625001_m01_create_branches.sql`            |
| `20260625_002` … `20260625_009` (same pattern)    | `20260625002` … `20260625009`                    |
| `20260701_010_m01_drop_branches_break_window.sql` | `20260701010_m01_drop_branches_break_window.sql` |
| `20260701_011` … `20260701_013` (same pattern)    | `20260701011` … `20260701013`                    |

After renaming, the remote's stale single tracking row (version `20260625`) was deleted and `supabase migration repair --status applied` was run for the 9 real, already-applied migrations under their new unique versions (`20260625001`–`20260625009`). `supabase migration list` then showed a clean 1:1 match between local and remote for those 9, with `010`–`013` correctly pending — at which point `supabase db push` applied them without error.

**Going forward:** any new migration file must keep this no-underscore-after-date convention (e.g. `supabase migration new <name>` output naturally satisfies this since it generates a full unambiguous timestamp — this repo's shorter `YYYYMMDDNNN` scheme just needs the sequence number glued directly to the date, no underscore in between).

### Bonus fix: truncated policy identifiers

While applying `20260701013`, Postgres emitted `NOTICE (42622): identifier "..." will be truncated` for the three Admin/Superadmin `insert`/`update`/`delete` policies — their names exceeded Postgres's 63-character identifier limit. Since this migration had only just been applied for the first time and hadn't merged to `dev` yet, the policy names were shortened (`"...for any staff"` → `"...all unavailability blocks"`, matching the existing `select` policy's naming) in both the migration file and directly on the remote (drop + recreate under the corrected name), so the file and the live database stay in sync.

### VS Code Tasks for Supabase Management

Use these tasks to manage Supabase from VS Code (`Terminal` → `Run Task`):

- **🔐 Supabase: Login** — Authenticate with Supabase CLI
- **🔗 Supabase: Link Project** — Link to your remote project
- **📊 Supabase: Check Migration Status** — View migration sync status (`supabase migration list`)
- **📥 Supabase: Pull Remote State** — Sync local migrations with remote
- **📤 Supabase: Push Migrations** — Apply local migrations to remote
- **🔧 Supabase: Reset Local DB** — Reset local database to clean state
- **🩹 Supabase: Repair Migration History** — Prompts for a status (`applied`/`reverted`) and a migration version, then runs `supabase migration repair` against the linked remote. Use this when `migration list` shows a local migration with no matching remote entry despite its SQL already having run (exactly the scenario above).

---

## Acceptance Criteria Checklist

- [x] **AC-1:** `branches.break_window` column is dropped via migration ✓ (Step 4) — confirmed on remote, 0 rows
- [x] **AC-2:** `staff_profiles.is_busy` and `staff_profiles.busy_until` columns are dropped via migration ✓ (Step 4) — confirmed on remote, 0 rows
- [x] **AC-3:** `staff_unavailability_blocks` table is created with required columns ✓ (Step 5) — confirmed on remote, 7 columns
- [x] **AC-4:** `staff_id` references `staff_profiles(id) ON DELETE CASCADE` ✓ (Step 6)
- [x] **AC-5:** RLS is enabled and policies allow staff self-access and Admin/Superadmin manage-all ✓ (Step 8–9) — confirmed on remote, `rowsecurity = true`, all 8 policies present with corrected (untruncated) names
- [x] **AC-6:** No `staff_availability_templates` or `staff_availability_overrides` tables introduced ✓ (by design) — confirmed on remote, 0 rows

---

## Notes

- Validation of `end_time > start_time` is enforced at the application layer (service/validator), not as a DB constraint.
- The `staff_unavailability_blocks` table plus the upcoming `get_staff_availability()` function (Issue #12) remain the single source of truth for staff availability.
- The RLS pattern mirrors that of `staff_profiles`: self-access policies + Admin/Superadmin manage-all policies.

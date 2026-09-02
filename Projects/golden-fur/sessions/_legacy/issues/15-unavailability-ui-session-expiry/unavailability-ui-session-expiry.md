# Issue #15 Verification: Unavailability Block UI and Session Expiry Handling

**Issue:** #15 - refactor(client): Unavailability Block UI; session expiry handling  
**Branch:** `refactor/unavailability-ui-session-expiry`  
**Sprint:** Sprint 1 - Epic A-1

## Overview

This issue adds staff-only client UI for two Epic A-1 behaviors:

- A read-only staff unavailability badge that checks whether the signed-in staff member has an active `staff_unavailability_blocks` row.
- A staff-only inactivity warning modal that appears before the role-tiered timeout from issue #13 and signs the staff member out at expiry.
- A forward DB policy fix so staff-facing unavailability reads do not hit recursive RLS policy failures.

Customer-facing routes are intentionally unchanged and should never show the inactivity warning.

## Verification Steps

### Step 1: Run the focused client tests

From the repository root:

```bash
cd client
npm test -- --run src/shared/hooks/useInactivityTimeout/useInactivityTimeout.spec.ts src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.spec.ts
```

Expected result:

- The inactivity hook spec passes.
- The staff auth guard spec passes.
- The guard test confirms the warning appears before the Admin 30-minute timeout.
- The guard test confirms staff sign-out is called once when the threshold elapses.

### Step 2: Run the full client test suite

From the repository root:

```bash
cd client
npm test
```

Expected result:

- All client Vitest suites pass.

### Step 3: Start the app locally

From the repository root:

```bash
npm run client
```

Open the local Vite URL shown in the terminal, usually:

```text
http://localhost:5173
```

### Step 4: Apply the Supabase RLS fix

This issue includes a forward migration:

```text
supabase/migrations/20260701015_m01_fix_staff_rls_role_recursion.sql
```

Apply pending migrations to the linked Supabase project:

```bash
npm run supabase:push
```

Expected result:

- The migration creates `public.current_staff_role()` as a `security definer` helper.
- Admin/Superadmin policies on `staff_profiles` and `staff_unavailability_blocks` use `public.current_staff_role()`.
- The browser console no longer shows a Supabase REST `500` when the badge queries `staff_unavailability_blocks`.

### Step 5: Verify the RLS policy helper

In Supabase Dashboard:

1. Open the project.
2. Go to **SQL Editor**.
3. Open a new query.
4. Paste the contents of:

```text
testing/docs/sprints/sprint1/epicA1/issue-15/supabase/issue15.sql
```

5. Click **Run**.

Expected result:

- `current_staff_role` exists.
- `is_security_definer` is `true`.
- Admin/Superadmin policies reference `current_staff_role`.

### Step 6: Verify the unavailability badge

1. Sign in as a staff user.
2. Go to a staff-scoped route such as `/staff`.
3. Confirm a small status badge appears near the top of the staff area.
4. In Supabase Table Editor, open `staff_unavailability_blocks`.
5. Insert or find a row where:
   - `staff_id` is the signed-in staff user's id.
   - `start_time` is before the current time.
   - `end_time` is after the current time.
6. Refresh the staff page.

Expected result:

- With an active row, the badge reads `Currently unavailable`.
- Without an active row, the badge reads `Available for bookings`.
- The badge is read-only; there is no create/edit calendar UI in this issue.
- If the badge reads `Unable to check availability`, inspect the browser Network tab for the Supabase REST response body before continuing.

### Step 7: Verify the session-expiry warning

Use the automated test as the primary verification because the real thresholds are intentionally long:

- Admin/Superadmin: 30 minutes
- Supervisor: 60 minutes
- Receptionist/Cashier: 4 hours
- Groomer/Veterinarian/Pet Assistant: 8 hours

Manual smoke test:

1. Sign in as a staff user.
2. Stay on a staff-scoped route.
3. Leave the browser inactive until the final warning window before that role's timeout.

Expected result:

- A modal appears with a `Stay signed in` button.
- Clicking `Stay signed in` dismisses the modal and restarts the inactivity timer.

### Step 8: Verify automatic sign-out

Use the automated guard spec as the primary verification.

Manual smoke test, if you are willing to wait for the real threshold:

1. Sign in as a staff user.
2. Stay inactive past that staff role's timeout.

Expected result:

- The app signs the staff member out.
- The browser redirects to `/staff/login`.

### Step 9: Verify customer pages do not show the warning

1. Sign in as a customer, or open a customer-facing route.
2. Navigate customer pages normally.
3. Leave the page idle.

Expected result:

- No session-expiry modal appears on customer-facing pages.
- Customer auth guard behavior remains unchanged.

## Acceptance Criteria Checklist

- [x] **AC-1:** Staff area displays a lightweight read-only unavailability status indicator when the signed-in staff member has an active `staff_unavailability_blocks` row.
- [x] **AC-2:** A session-expiry warning appears before the role-tiered inactivity timeout elapses, with an option to stay signed in.
- [x] **AC-3:** If the staff member takes no action, they are signed out automatically once the role-tiered threshold is reached and redirected to `/staff/login`.
- [x] **AC-4:** Customer-facing pages never show a session-expiry warning.

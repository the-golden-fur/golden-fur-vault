# Sprint 1 Gap Audit & Fix — M01 (Staff Auth & Access Control) + M02 (Customer Portal & Pet Management)

Type: Custom audit + fix (not tracked against a specific epic/issue backlog item)
Sources reviewed: `temp/context/source.txt` (M01/M02 flowchart specs + revision log),
`temp/context/Modules-Features.docx`, `temp/context/Agile-SprintMap.xlsx` (Sprint 1 tasks
1-A through 1-G), `temp/context/Sprint1-EpicStructure.xlsx` (Issues #1–#38),
`temp/context/Modules-Overview.xlsx`.

## Summary

Sprint 1 was audited against the spec and found incomplete in the exact area
you suspected — admin's ability to promote/demote a staff member's role,
deactivate an account, or transfer branch did not exist anywhere in the
codebase — plus a few more gaps and one live bug found during the audit. **All
of them have now been implemented/fixed in this pass.** See "Fixes
implemented" below for what changed, and "Verification" for how to confirm it
yourself.

## Fixes implemented

### 1. Admin role change / deactivate / branch transfer (the item you asked about)

**Was:** No route, service, or UI existed for this at all (M01 Process 5 /
Sprint 1 task 1-C's "Admins can create, change role, change branch, and
deactivate accounts" AC). `AdminStaffListPage`'s only per-card action was "Set
unavailability."

**Now:**

- New endpoint `PATCH /staff/:id/manage` ([staff.routes.ts:78-85](server/src/features/staff/staff.routes.ts#L78-L85)),
  gated to Admin/Superadmin at the route level.
- New service [staffManagement.service.ts](server/src/features/staff/services/staffManagement.service.ts):
  `manageStaffAccount()` enforces that **role and branch_id changes require
  Superadmin** (matching M01 Process 5's explicit "Actor is Superadmin?" gate),
  while **deactivate (`is_active`) is available to Admin or Superadmin**, each
  branch-scoped for Admin (an Admin can only manage staff at their own
  branch; Superadmin can manage any branch).
- New UI: `ManageStaffAccountForm` ([client component](client/src/features/staff/components/forms/ManageStaffAccountForm/ManageStaffAccountForm.tsx)),
  wired into `AdminStaffListPage` behind a new "Manage account" button per
  staff card. Role/branch dropdowns only render for a Superadmin viewer;
  deactivate/reactivate is available to both Admin and Superadmin.
- **Deliberately not added:** a database-level trigger restricting role/branch
  changes to Superadmin. This codebase's server always talks to Postgres via
  the service-role Supabase client, which bypasses RLS entirely and still
  fires triggers — a trigger keyed on `auth.uid()`/`current_staff_role()`
  would see no real user context on the server's own legitimate writes and
  would incorrectly block them. The existing self-review RLS policy
  (`...021`) has the same "inert against the server, meaningful only against
  a hypothetical direct-API-call with a real user JWT" nature; the app-layer
  check in `staffManagement.service.ts` is the actual enforcement, consistent
  with how every other authorization check in this codebase already works.

### 2. Admin creates a staff account

**Was:** No `POST /staff` route existed; the only way to create a
`staff_profiles` row was the seed script.

**Now:**

- New endpoint `POST /staff` ([staff.routes.ts:40-46](server/src/features/staff/staff.routes.ts#L40-L46)),
  gated to Admin/Superadmin, branch-scoped for Admin.
- `createStaffAccount()` in the same service checks username/email uniqueness
  with friendly 409s (matching M01 Process 1's "Is the username already
  taken?" branch), creates the Supabase Auth user with a generated temporary
  password, inserts the `staff_profiles` row, and compensates (deletes the
  orphaned auth user) if the profile insert fails.
- **Known, flagged limitation:** M11 (Notification module, email delivery) is
  Sprint 6 and doesn't exist yet, so there's no `account_created` email. The
  temporary password is returned directly in the API response and shown in
  the new "Create staff account" form (`CreateStaffAccountForm`) for the
  admin to relay to the new hire manually.

### 3. Bug fix — the "now until end of shift" quick action was created `pending`, not `approved`

**Was:** `createUnavailabilityBlock()` never set `is_quick_action` on the
insert, so the DB trigger fell through to its "pending" branch for a
self-requested quick action, silently defeating the emergency-safety-net
purpose of that button.

**Now:** [unavailabilityBlock.service.ts:230](server/src/features/staff/services/unavailabilityBlock.service.ts#L230)
sets `is_quick_action: Boolean(quickAction)` on the insert. Covered by a new
regression test asserting the insert payload (`unavailabilityBlock.service.spec.ts`,
"bug fix regression" test).

### 4. `get_staff_availability()` now filters to approved-only

**Was:** The Postgres function counted pending/denied unavailability blocks
as blocking, contradicting the Jul 11, 2026 spec revision.

**Now:** New migration
[20260714031_m01_get_staff_availability_approved_only.sql](supabase/migrations/20260714031_m01_get_staff_availability_approved_only.sql)
recreates the function with `and sub.status = 'approved'` added to the
overlap check. Everything else in the function is unchanged.

### 5. Mandatory TOTP now includes Supervisor

**Was:** Only Admin/Superadmin were forced through TOTP, both server
(`requireMfa.middleware.ts`) and client (`StaffAuthGuard.tsx`) — contradicting
the spec's "required for Admin and Supervisor."

**Now:** Both `MANDATORY_MFA_ROLES` (server) and `requiresMfa()` (client) include
Supervisor. Existing tests that asserted the old (wrong) behavior were flipped
to assert the corrected one.

### 6. Server-side session-inactivity middleware is no longer dead code

**Was:** `sessionTimeoutMiddleware` existed with the correct role-tiered
timeout table but was never imported into any route.

**Now:** Wired into every route in `staff.routes.ts`, right after
`jwtMiddleware`. **Known, flagged limitation carried over from before:** this
middleware measures elapsed time since the JWT's `auth_time` (issued-at),
i.e. absolute session age, not true idle-time — it doesn't reset on activity
the way the client-side `useInactivityTimeout` hook does. Re-architecting it
into true server-tracked inactivity (e.g. a last-activity store updated per
request) is a larger change than "wire up the existing middleware" and was
left out of this pass; the client-side enforcement remains the primary,
correctly-behaving inactivity timeout, and this middleware is now at least a
real (if coarser) backstop instead of inert code.

### 7. Password reset completion page

**Was:** Requesting a reset email worked, but there was no page for the
emailed link to land on to actually set a new password.

**Now:**

- `forgotPasswordController` now passes `redirectTo` pointing at
  `<client origin>/staff/reset-password` (client origin read from the first
  entry of `CORS_ALLOWED_ORIGINS`).
- New route `/staff/reset-password` → `StaffResetPasswordPage` →
  `StaffResetPasswordForm`: establishes the recovery session from the
  emailed link's hash fragment (same pattern as the existing customer OAuth
  callback), then lets the user set and confirm a new password
  (8+ characters, must match), calling `supabase.auth.updateUser()`.

## Automated verification

From the repository root in PowerShell:

```powershell
npm --prefix server run test
npx --prefix server tsc --noEmit
npx --prefix server eslint .

npm --prefix client run test
npx --prefix client tsc -b
npx --prefix client eslint .
```

Expected: 275 server tests pass, 174 client tests pass, both typechecks
clean, both lints clean (pre-existing `no-console` warnings in
`customerAuth.controller.ts`/`staffAuth.controller.ts` are unrelated to this
change).

## Manual verification

You'll need a running `server/` and `client/` dev instance, access to your
Supabase project's Studio, and Postman for the collection in this folder.

1. **Start both dev servers.** `npm --prefix server run dev`, then in a second
   terminal `npm --prefix client run dev`.

2. **Admin role/branch/deactivate management (fix #1).** Sign in as a seeded
   **Superadmin**, open **Staff Directory**, click **Manage account** on any
   staff card. Confirm you see **Change role to** and **Change branch to**
   dropdowns plus a **Deactivate account** button. Change the role, click
   **Save role/branch**, and confirm the card's role badge updates. Sign out,
   sign back in as an **Admin** (not Superadmin), open **Manage account** on a
   staff card at your own branch — confirm the role/branch dropdowns are
   **not** shown, but **Deactivate account** still is. Click it and confirm
   the account deactivates successfully.

3. **Admin creates a staff account (fix #2).** On the same Staff Directory
   page, fill in the **Create staff account** form (username, registered
   email, display name, role; branch only shown for Superadmin) and submit.
   Confirm a new `StaffCard` appears in the grid and a banner shows the
   generated **temporary password** — copy it, you'll need it to sign in as
   that new account for a smoke test if you want.

4. **Quick-action bug fix (fix #3).** Sign in as any lower-level staff
   account (e.g. a Groomer), go to **My Profile → Availability**, click
   **Unavailable until end of shift**. In Supabase Studio's Table Editor,
   open `staff_unavailability_blocks` and find the new row — confirm
   `status = 'approved'` (not `pending`) and `is_quick_action = true`.

5. **`get_staff_availability()` fix (fix #4) and the request/approval
   workflow end to end.** Run `sprint1-gap-audit.sql`'s Section 2 in
   Supabase Studio's SQL Editor — confirm the printed function body now
   includes `sub.status = 'approved'` in its WHERE clause.

6. **Supervisor MFA (fix #5).** Sign in as a seeded **Supervisor** account
   that has never enrolled TOTP. Confirm the mandatory "Set up multi-factor
   authentication" popup now appears (previously it did not).

7. **Session timeout middleware (fix #6).** No manual repro needed — this is
   an inert-until-triggered backstop; the automated test suite's coverage
   (`sessionTimeout.middleware.spec.ts`, still 10 passing tests) plus
   confirming `staff.routes.ts` now imports and uses it is sufficient.

8. **Password reset completion page (fix #7).** From `/staff/login`, enter a
   real staff account's email under **Forgot password** and submit. Check
   that account's inbox (or your Supabase project's Auth logs if using a
   test SMTP catch-all) for the reset email, click the link. Confirm you land
   on `/staff/reset-password`, not a broken/blank page, can enter and confirm
   a new password, and are redirected to `/staff/login` after a couple of
   seconds. Sign in with the new password to confirm it actually took effect.

9. **Run the updated Postman collection** (`sprint1-gap-audit.postman_collection.json`
   in this folder) — see that file's own request names; every request that
   used to assert a "GAP CONFIRMED" 400/404 now asserts the fixed 200/201
   behavior, and the quick-action bug request now asserts `status: 'approved'`.

# Issue #26 Verification: Admin Staff Management UI

**Issue:** #26 — feat(staff): admin staff management UI
**Owner:** James
**Branch:** `feat/admin-staff-management-ui`
**Base:** `dev`
**Depends on:** #25 (StaffCard + profile UI) merged
**Sprint:** Sprint 1 — Epic B, M01 Staff Auth & Access Control

## Overview

Adds `AdminStaffListPage`, a branch/role-filterable staff directory reachable only by Admin/Superadmin. Reuses `StaffCard` and `UnavailabilityBlockForm` from #25 unmodified — the page only supplies layout (grid), filtering, and the "on behalf of" wiring for `UnavailabilityBlockForm` (passing a target staff member's id instead of the logged-in user's).

## What Changed

- **Added** `client/src/features/staff/pages/AdminStaffListPage/AdminStaffListPage.tsx` (+ module CSS, + spec) — fetches `listStaff()`, applies a role filter (all viewers) and a branch filter (Superadmin only), renders one `StaffCard` per result, and lets an Admin/Superadmin expand an inline `UnavailabilityBlockForm` per card to create a block on behalf of that staff member. Non-Admin/Superadmin roles are redirected to `/staff/profile` once the viewer's own role is known (see bug fix below for how that role is resolved).
- **Modified** `client/src/features/staff/staff.routes.ts` — registered `/staff/admin/staff` behind the existing `StaffAuthGuard`, alongside `/staff/profile`. `client/src/routes.tsx` already imports `staffRoutes` (wired in #25), so no change was needed there.
- **Modified** `client/src/features/auth/staff/staffAuth.routes.ts` — added a "Staff Directory" link (and restructured the two existing links into a list) on the placeholder staff dashboard, for discoverability during manual verification. Not in the issue's own Affected Files table, same rationale as #25's addition of the "My Profile" link there.
- **Modified** `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` (+ spec) — bundled fix for the client-side role-resolution bug this issue surfaced; see "Bug fixes" below. Not in the issue's own Affected Files table, but `StaffAuthGuard` wraps every staff route including this issue's new one, and its role resolution shared the exact same defect `AdminStaffListPage`'s guard hit — leaving it broken would mean #26 ships next to a guard with a live MFA-enforcement/session-timeout gap on every staff page.

### Scope notes / deviations from the issue spec

- **AC-5 skipped.** The issue's AC-5 (link/badge to a pending-requests approval queue) depends on Issue #30's `UnavailabilityApprovalQueuePage` and a pending-request count API/table from the request/approval redesign. Neither exists yet anywhere in this codebase (no route, no API, no migration for a request/approval concept) — confirmed by grepping for `ApprovalQueue`/`UnavailabilityRequest`/`pendingCount` and checking `supabase/migrations/`. Implementing it here would mean building #30's backing infra inside #26. Flagged as blocked on #30 rather than stubbed.
- **Branch filter labels.** No branches-lookup API exists client- or server-side (`GET /staff` returns `branch_id` but not a name; `StaffCard`'s optional `branchName` prop has never been populated by any caller, per #25's own scope notes). The Superadmin branch filter is built from the distinct `branch_id`s already present in the fetched staff list and labeled `Branch <first 8 chars of id>` rather than a real name. Filtering itself is fully functional; only the option label is a placeholder pending a real branches API.
- **No server changes.** `GET /staff` (added in #22, already branch-scoped for non-Superadmin roles server-side) was reused as-is. The issue's dev notes suggest adding `limit`/`offset` to `listStaff()` now to avoid a future breaking change, but pagination itself is explicitly flagged as an Epic-level open item, so this was left alone rather than guessed at.

## Bug fixes: client-side staff role resolution was broken everywhere

Checked against `temp/context/Sprint1-EpicB-Guide.md.docx` (the Epic B implementation guide) before bundling this in: nothing in Issues #27–#30 touches `StaffAuthGuard` or client-side role resolution, and the guide's Handoff State section only confirms the _server-side_ `sessionTimeout.middleware.ts` correctly reads role from `staff_profiles.role` via a DB lookup — a separate, unaffected code path from the client bug below. This wasn't going to be fixed by a later issue, so per the guide's own precedent (Issue #28 exists specifically because a gap discovered mid-epic gets fixed as a new issue, not silently patched into whatever branch found it) it would normally warrant its own issue — bundled into this branch instead, since #26 itself was blocked by it and splitting the fix out would leave #26 shipping next to a guard with a live security gap it had already exposed.

### #1 — "Staff Directory" always redirected Admin/Superadmin back to `/staff/profile`

**Symptom:** manually signed in as a seeded Admin (`makati.admin1@goldenfur.com`), clicking **Staff Directory** (or navigating to `/staff/admin/staff` directly) immediately bounced back to `/staff/profile`, even though `/staff/profile` correctly showed the account's role as "Admin".

**Root cause:** the page's first implementation resolved the viewer's role client-side with the same helper `StaffAuthGuard` used — check `session.user.role`, falling back to `session.user.app_metadata.role`. Neither actually carries the app-level staff role:

- `session.user.role` is Supabase/GoTrue's own Postgres role, which `supabase/seed.sql` sets to the literal string `'authenticated'` for every signed-in user (staff and customer alike) — it has nothing to do with `staff_profiles.role`.
- `app_metadata` is seeded as `{"provider":"email","providers":["email"]}` only; no migration or trigger ever adds a `role` claim to it, and no `custom_access_token` auth hook is configured in `supabase/config.toml` (the hook section is present but commented out).

So the helper always returned `"authenticated"`, which is never in `{Admin, Superadmin}`, and the page redirected away regardless of the signed-in user's real role.

**Fix:** `AdminStaffListPage` no longer reads role off the session at all. `GET /staff` is reachable by every staff role (`staff.routes.ts` gates it with `requireRole([...ALL_STAFF_ROLES])`, not an admin-only list) and always includes the requester's own row — branch-scoped for non-Superadmin, unfiltered for Superadmin. The page now waits for `listStaff()` to resolve, then finds the row where `id === user.id` and uses that row's `role` as the authoritative viewer role, for both the page guard and the Superadmin-only branch filter. This needed the loading/redirect ordering to change too: the role-gate check now runs only after the fetch resolves, so an Admin/Superadmin no longer flashes through a premature redirect while their own role is still unknown.

### #2 — `StaffAuthGuard` had the identical bug, silently disabling mandatory MFA and role-tiered timeouts for every real staff session

**Root cause:** `StaffAuthGuard.tsx`'s own `getStaffRole()` had the same session/app_metadata heuristic as #1, feeding two security-relevant decisions: whether MFA is mandatory for Admin/Superadmin (`requiresMfa(role)`) and which role-tiered inactivity timeout applies (`ROLE_TIMEOUT_MS[role]`). Because `user.role` is always `"authenticated"` on a real session, both silently fell through to the "no role matched" path for every real signed-in user (MFA enforcement never triggered off this check; the timeout fell back to `null`/no timeout). `StaffAuthGuard.spec.ts` never caught it because it mocked `user.role` as a fake app role (`'Admin'`, `'Groomer'`, etc.) directly on the auth context — a shape a real Supabase session never has.

**Fix:** `StaffAuthGuard` now resolves role the same way #29 (Matthew's own Handoff State note confirms the server-side timeout middleware already does this correctly) implies it always should have: a server round trip. It calls `getStaffProfile(user.id, accessToken)` (already existed, used by `StaffProfilePage`) alongside the existing `getMfaStatus` call, and uses the returned `role` for both `requiresMfa()` and the `ROLE_TIMEOUT_MS` lookup. `role` starts `null` (matching the existing `mfaEnrolled` null-until-known pattern) and updates once the fetch resolves — no render-blocking, consistent with how `mfaEnrolled` is already handled.

**Test suite change:** `StaffAuthGuard.spec.ts` now mocks `getStaffProfile` per test to supply the intended role (mirroring the existing per-test `getMfaStatus` overrides), since a real role can no longer come from the auth-context mock. One test, `renders protected staff content for authenticated non-MFA staff`, was previously synchronous and asserted _before_ the async `mfaEnrolled` fetch resolved — it only passed because of that timing race, not because the settled behavior was actually MFA-free. Made it `async`/awaited and set `mfa_enrolled: false` explicitly to match its own name/intent, since the settled behavior for `mfa_enrolled: true` (correctly) redirects to the aal2 challenge regardless of role — that's existing, intended behavior (see the guard's own "Mandatory roles..." comment), not something this fix changed.

**Not fixed (separate, larger, and out of scope even for a bundle):** the _proper_ long-term fix is a Supabase `custom_access_token` auth hook that stamps the real `staff_profiles.role` onto the JWT at login (the hook section already exists, commented out, in `supabase/config.toml`), so every client-side consumer reads a trustworthy claim instead of each guard/page doing its own server round trip to look up its own role. That's a genuine auth-infrastructure change (new Postgres function, hook wiring, and every existing session needs to re-login for a new JWT shape) well beyond either of these two guards, so both fixes here take the smaller, consistent "ask the server for my own profile" path instead.

## Automated Verification

From the repository root in PowerShell:

```powershell
npm --prefix client test -- --run
npm --prefix client run lint
```

Expected result: all 31 client Vitest files / 107 tests pass, and `eslint .` reports 0 problems. (`tsc --noEmit` was also run directly and is clean.)

To run just the files touched by this issue:

```powershell
npm --prefix client test -- --run src/features/staff/pages/AdminStaffListPage
```

Expected: 6 tests pass, one per AC-1 through AC-4 (AC-2's branch/role filter visibility is split across two tests).

```powershell
npm --prefix client test -- --run src/features/auth/staff/guards/StaffAuthGuard
```

Expected: 8 tests pass, covering both the bundled role-resolution fix and the pre-existing MFA/timeout behaviors it now correctly gates.

## Structural Verification

1. Confirm the new page files exist:

   ```powershell
   Get-ChildItem client/src/features/staff/pages/AdminStaffListPage -File
   ```

   Expected: `AdminStaffListPage.tsx`, `AdminStaffListPage.module.css`, `AdminStaffListPage.spec.ts`.

2. Confirm the route is registered:

   ```powershell
   Select-String -Path client/src/features/staff/staff.routes.ts -Pattern "staff/admin/staff"
   ```

   Expected: one match.

3. Confirm `StaffAuthGuard` no longer resolves role from the session:

   ```powershell
   Select-String -Path client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx -Pattern "getStaffRole|getStaffProfile"
   ```

   Expected: no `getStaffRole` match (the broken helper was removed); `getStaffProfile` appears twice (the import and the call).

## Manual Browser Verification

Requires a running server and Supabase project with seeded staff accounts across at least two roles and, ideally, two branches (for the Superadmin branch filter). See issue #22's doc for locating/creating seeded accounts in Supabase Studio's **Table Editor → staff_profiles**.

### Step 1: Start the server and client

```powershell
npm --prefix server run dev
```

In a second terminal:

```powershell
npm --prefix client run dev
```

Open the local Vite URL shown in the terminal, usually `http://localhost:5173`.

### Step 2: Confirm role-gating (AC-1)

1. Sign in at `/staff/login` with a non-Admin account (e.g. a Groomer).
2. Navigate directly to `http://localhost:5173/staff/admin/staff`.

Expected result: immediately redirected to `/staff/profile` — the grid never renders. — **AC-1**

3. Sign out, sign back in with an Admin or Superadmin account.
4. From the staff dashboard placeholder (`/staff`), click **Staff Directory** (or navigate directly to `/staff/admin/staff`).

Expected result: the page loads and stays — **AC-1**

### Step 3: Confirm the grid and filters (AC-2, AC-3)

Expected result on load:

- One `StaffCard` per staff member returned by the account's `listStaff()` scope (branch-scoped for Admin, all branches for Superadmin). — **AC-2**
- A **Role** dropdown is always visible; a **Branch** dropdown is visible only when signed in as Superadmin. — **AC-2**

1. Change the **Role** filter to a role present in the seed data.

Expected result: the grid updates immediately to only that role's cards, with no page reload (check the Network tab — no new navigation/document request). — **AC-3**

2. (Superadmin only) Change the **Branch** filter.

Expected result: the grid updates to only that branch's cards, same as above. — **AC-3**

### Step 4: Create an unavailability block on behalf of another staff member (AC-4)

1. On any card, click **Set unavailability**.
2. Click **Unavailable until end of shift** in the form that expands below the card.

Expected result:

- A "Unavailability block created." banner appears above the grid.
- That card's `UnavailabilityBlockBadge` updates to `Unavailable until HH:MM` without a manual page refresh. — **AC-4**
- In Supabase Studio (**Table Editor → staff_unavailability_blocks**), a new row exists with `staff_id` matching the target card (not the signed-in admin) and `created_by` matching the signed-in admin's id.

### Step 5: Confirm the bundled `StaffAuthGuard` fix (mandatory MFA now actually triggers for Admin/Superadmin)

1. In Supabase Studio, find (or use) a seeded **Admin** or **Superadmin** account that has never enrolled MFA (`auth.mfa_factors` has no row for that user).
2. Sign in with that account at `/staff/login`.

Expected result: the mandatory "Set up multi-factor authentication" popup now appears (before this fix, an Admin/Superadmin would land straight on the staff dashboard with no MFA prompt, because `requiresMfa()` never received a real role).

1. Sign in with a seeded non-Admin role (e.g. Groomer) that also has no MFA factor.

Expected result: no mandatory popup — matches the design ("Mandatory roles always need aal2; everyone else only needs it once they've actually enrolled").

## Acceptance Criteria Checklist

- [x] **AC-1:** `AdminStaffListPage` is reachable only by Admin/Superadmin; other roles are redirected — `AdminStaffListPage.spec.ts` ("redirects a non-Admin/Superadmin role..."); manual Step 2.
- [x] **AC-2:** The staff grid renders one `StaffCard` per staff member, filterable by branch (Superadmin only) and by role — `AdminStaffListPage.spec.ts` (renders-per-viewer and filter-visibility tests); manual Step 3.
- [x] **AC-3:** Filtering updates the visible grid without a full page reload — `AdminStaffListPage.spec.ts` ("filtering by role updates the visible grid without navigating"); manual Step 3.
- [x] **AC-4:** An Admin/Superadmin can create an Unavailability Block on behalf of another staff member directly from the list view, still immediately active — `AdminStaffListPage.spec.ts` ("an Admin can create an unavailability block on behalf of..."); manual Step 4.
- [ ] **AC-5:** Not implemented — blocked on Issue #30 (`UnavailabilityApprovalQueuePage` and its backing pending-count API/table don't exist yet). See "Scope notes / deviations" above.

Not an AC of this issue, but bundled in this branch (see "Bug fixes" above):

- [x] **Bug fix #1:** `AdminStaffListPage`'s own role guard resolves the real `staff_profiles.role` instead of the always-`"authenticated"` session role — `AdminStaffListPage.spec.ts`; manual Step 2.
- [x] **Bug fix #2:** `StaffAuthGuard`'s mandatory-MFA and role-tiered-timeout checks resolve the real role the same way — `StaffAuthGuard.spec.ts` (8 tests); manual Step 5.

# Issue #21 Verification: Server `supabaseAuth.api.ts` — reusable Supabase query service

**Issue:** #21 — feat(server): add server-side `auth.api.ts` — reusable Supabase query service
**Owner:** Matthew
**Branch:** `feat/server-supabase-auth-service`
**Base:** `dev`
**Depends on:** #20 (merged — lands inside `server/src/shared/auth/` created by the restructure)
**Sprint:** Sprint 1 — Epic A-1 Addendum

## Overview

Pure refactor, no behavioral change. All direct `supabase.from()` / `supabase.auth.*` calls that were duplicated inline across staff/customer auth controllers and middleware now live in one place: `server/src/shared/auth/api/supabaseAuth.api.ts`. This mirrors the pattern the client already uses in `client/src/shared/auth/api/auth.api.ts`.

## What Changed

- **Added** `server/src/shared/auth/api/supabaseAuth.api.ts`, exporting:
  - `resolveStaffLoginIdentifier(identifier)` — passes an email-shaped identifier straight through; otherwise looks up `registered_email` by `username` in `staff_profiles` (backs Issue #18's username-or-email login).
  - `signInWithPassword(email, password)` — wraps `supabase.auth.signInWithPassword` on the shared singleton client (staff login only — customer login intentionally keeps its own throwaway service-role client; see "Scope notes" below).
  - `getStaffRole(userId)` — `staff_profiles.role` lookup used by `requireRole`.
  - `getStaffBranch(userId)` — `staff_profiles.role, branch_id` lookup used by `requireBranch`.
  - `createCustomerAuthUser(email, password, metadata)` — wraps `supabase.auth.admin.createUser`.
  - `createCustomerProfile(fields)` — inserts a row into `customer_profiles`.
  - `getCustomerProfileByEmail(email)` — looks up a `customer_profiles` row by `account_email`.
- **Added** `server/src/shared/auth/api/supabaseAuth.api.spec.ts` — unit tests for all 7 functions, mocking `supabase` at the same `config/supabase/supabase.config.ts` boundary the existing controller/middleware tests already use.
- **Modified** `staffAuth.controller.ts` — `staffLoginController` now calls `resolveStaffLoginIdentifier` + `signInWithPassword` instead of building the query/sign-in calls inline.
- **Modified** `customerAuth.controller.ts` — `customerSignupController` now calls `createCustomerAuthUser` + `createCustomerProfile` instead of calling `supabase.auth.admin.createUser` / `supabase.from('customer_profiles').insert(...)` directly.
- **Modified** `requireRole.middleware.ts` — now calls `getStaffRole(userId)` instead of building its own `supabase.from('staff_profiles')` query.
- **Modified** `requireBranch.middleware.ts` — now calls `getStaffBranch(userId)` instead of building its own `supabase.from('staff_profiles')` query.

### Scope notes

- `customerLoginController`'s sign-in call and the post-signup sign-in inside `customerSignupController` **intentionally keep** their existing `createSignInClient()` throwaway client (see the comment already in `customerAuth.controller.ts`). `signInWithPassword()` wraps the shared singleton client instead — reusing it for customer sign-in would reintroduce the exact session-mutation bug that throwaway client exists to avoid. Only staff login (which was already using the singleton) was moved onto `signInWithPassword()`.
- `getCustomerProfileByEmail` is exported per the issue's function list but has no call site inside the 4 affected files in this issue — the equivalent inline query currently lives in `accountMerge.service.ts`, which is out of this issue's `Affected Files` list and was left untouched.
- `requireMfa.middleware.ts`, MFA enroll/verify (`userClient.auth.mfa.*`), `forgotPasswordController`, and `customerOauthCallbackController`'s `supabase.auth.getUser` call were **not** touched — they weren't named in the issue's function list and use a different pattern (a per-request, token-scoped client rather than the shared singleton).
- `requireRole` and `requireBranch` are not currently mounted on any route (confirmed via `grep` across `server/src`), so they can only be regression-checked through their unit tests, not through Postman.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected result:

- All server test files pass, including the new `src/shared/auth/api/supabaseAuth.api.spec.ts` and the **unmodified** `staffAuth.unit.spec.ts`, `staffAuth.middleware.unit.spec.ts`, `customerAuth.unit.spec.ts`, `staffAuth.integration.spec.ts`, `customerAuth.integration.spec.ts`, and `auth.integration.spec.ts` (per AC-3, no assertions in these files were changed).
- `typecheck` and `lint` exit clean (pre-existing `no-console` warnings in the two controllers are unrelated to this change and were already present).

Confirmed for this pass: 18 test files / 94 tests passed; `tsc --noEmit` produced no output; `eslint .` reported 0 errors (3 pre-existing `no-console` warnings).

## Structural Verification

1. Confirm the new service file and its spec exist:

   ```powershell
   Get-ChildItem server/src/shared/auth/api
   ```

   Expected files: `supabaseAuth.api.ts`, `supabaseAuth.api.spec.ts`.

2. Confirm the 4 target files no longer build their own Supabase queries for the moved calls:

   ```powershell
   Select-String -Path server/src/features/auth/staff/staffAuth.controller.ts -Pattern "supabase\.from\('staff_profiles'\)|supabase\.auth\.signInWithPassword"
   Select-String -Path server/src/features/auth/customers/customerAuth.controller.ts -Pattern "supabase\.auth\.admin\.createUser|supabase\.from\('customer_profiles'\)\.insert"
   Select-String -Path server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts -Pattern "supabase\."
   Select-String -Path server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts -Pattern "supabase\."
   ```

   Expected result: no matches in any of the four (the `requireRole`/`requireBranch` middleware files no longer import `supabase` at all).

3. Confirm the 4 files import from the new shared service:
   ```powershell
   Select-String -Path server/src/features/auth/staff/staffAuth.controller.ts,server/src/features/auth/customers/customerAuth.controller.ts,server/src/features/auth/staff/middleware/requireRole/requireRole.middleware.ts,server/src/features/auth/staff/middleware/requireBranch/requireBranch.middleware.ts -Pattern "shared/auth/api/supabaseAuth.api"
   ```
   Expected result: a match in each of the four files.

## Postman Verification

Use the collection at:

`testing/docs/sprints/sprint1/epicA1/issue-21/postman/issue21.postman_collection.json`

1. Open Postman.
2. Select **Import** → **Files**, and browse to the file above (or drag it in).
3. Open the imported collection named **Issue 21 - Server Supabase Auth Service Refactor**.
4. In the collection variables, set:
   - `base_url` to your server URL, usually `http://localhost:3000`.
   - `staff_identifier` to a staff username.
   - `staff_email` to that same staff member's email.
   - `staff_password` to that staff member's password.
   - `staff_totp_code` to a current 6-digit TOTP code if you want to exercise MFA verify (otherwise leave blank — a 401 for an invalid/blank code is still a passing regression result per AC-4).
   - `customer_full_name`, `customer_signup_email`, `customer_password` for a **new** customer signup.
   - `customer_email` for an existing customer account to test login.
5. Start the server if it is not already running:
   ```powershell
   npm --prefix server run dev
   ```
6. Run **Staff - Login with username identifier**. Expected: `200 OK` with `access_token`/`refresh_token` (exercises `resolveStaffLoginIdentifier` doing the username lookup).
7. Run **Staff - Login with email identifier**. Expected: `200 OK` (exercises `resolveStaffLoginIdentifier`'s short-circuit for `@`-shaped identifiers).
8. Run **Staff - Login with bad username fails with generic 401**. Expected: `401` with `{ "error": "Unauthorized" }` (per AC-6, `resolveStaffLoginIdentifier`'s thrown error is still swallowed into a generic 401 by the controller's catch block).
9. Run **Staff - MFA Enroll**. Expected: `200` or Supabase-specific `400` — both mean the request reached the controller through the (untouched) JWT + `userClient` path.
10. Run **Staff - MFA Verify**. Expected: `200`, `401`, or `423` — all are passing outcomes for AC-4's "TOTP verify continues to function identically" (this endpoint's logic was not touched by this issue).
11. Run **Customer - Signup**. Expected: `201 Created` with a `user` object (exercises `createCustomerAuthUser` + `createCustomerProfile`).
12. Run **Customer - Login**. Expected: `200 OK` with `access_token` (this path intentionally still uses the controller's own throwaway sign-in client, not `signInWithPassword()` — see "Scope notes" above).

## Acceptance Criteria Checklist

- [x] **AC-1:** `server/src/shared/auth/api/supabaseAuth.api.ts` exports `resolveStaffLoginIdentifier`, `signInWithPassword`, `getStaffRole`, `getStaffBranch`, `createCustomerAuthUser`, `createCustomerProfile`, and `getCustomerProfileByEmail`, covering the Supabase queries previously written inline in the 4 target files.
- [x] **AC-2:** `staffAuth.controller.ts`, `customerAuth.controller.ts`, `requireRole.middleware.ts`, and `requireBranch.middleware.ts` call the shared functions instead of issuing their own `supabase.from()`/`supabase.auth.*` calls for the queries covered by AC-1 (see "Scope notes" for the two calls deliberately left as-is).
- [x] **AC-3:** No behavioral change — `staffAuth.unit.spec.ts`, `staffAuth.middleware.unit.spec.ts`, `customerAuth.unit.spec.ts`, `staffAuth.integration.spec.ts`, `customerAuth.integration.spec.ts`, and `auth.integration.spec.ts` all pass unmodified against the refactored implementation.
- [x] **AC-4:** Login (username and email, per #18), TOTP verify, `requireRole`, and `requireBranch` all continue to function identically — verified via the unmodified unit/integration suites (`requireRole`/`requireBranch` specifically, since they aren't mounted on any route yet) and via the Postman collection for the two login paths, MFA enroll/verify, and customer signup/login.

## Client-side check

The client already centralizes its Supabase calls in `client/src/shared/auth/api/auth.api.ts` (added by Issue #19's restructure) — `getSupabaseClient()`, `getSession`, `onAuthStateChange`, `signOut`, `refreshSession`, and `setSession` all live there, and `customerAuth.api.ts` already imports `getSupabaseClient()` from it rather than creating its own client. A repo-wide search (`Select-String -Path client/src -Pattern "getSupabaseClient|supabase\.auth\.|createClient\("`) turns up no inline/duplicated Supabase client usage outside `auth.api.ts` and the files that already import from it. No client changes were needed for this issue.

# Issue #19 Verification: Client auth folder restructure (features/auth/ → shared/auth/)

**Issue:** #19 — refactor(client): move `client/src/features/auth/{api,providers,...}` to `client/src/shared/auth/`
**Owner:** James
**Branch:** `refactor/client-auth-shared-folder`
**Sprint:** Sprint 1 — Epic A-1 Addendum
**Commit:** `69f6adc` — refactor(client): move shared auth code to client/src/shared/auth/

## Overview

Pure move + import-path refactor, no behavioral change. The shared `AuthProvider`, `auth.api.ts`, and `auth.types.ts` moved out of `client/src/features/auth/` into `client/src/shared/auth/`, so `features/auth/` now only ever contains staff-/customer-specific code.

## What Changed

- Moved `client/src/features/auth/api/auth.api.ts` → `client/src/shared/auth/api/auth.api.ts`
- Moved `client/src/features/auth/auth.types.ts` → `client/src/shared/auth/auth.types.ts`
- Moved `client/src/features/auth/providers/AuthProvider/` (`AuthProvider.tsx`, `AuthContext.ts`, `useAuth.ts`, `AuthProvider.spec.tsx`) → `client/src/shared/auth/providers/AuthProvider/`
- Updated every relative import that reached into the old location — `StaffAuthGuard`, `StaffLoginForm`, `MfaChallengeForm`, `MfaEnrollForm`, `StaffLoginPage.spec.ts`, `App.tsx`, and the customer-side equivalents (`CustomerAuthGuard`, `CustomerLoginForm`, `CustomerSignupForm`, `OAuthCallbackPage`, `customerAuth.api.ts`) — to `client/src/shared/auth/`

This was already implemented by a teammate before this verification pass; the steps below confirm it against the issue's acceptance criteria rather than re-doing the move.

## Automated Verification

From `client/`, run:

```powershell
npm test -- --run auth
npx tsc -b
npm run lint
```

Confirmed results (already run for this verification):

- `npm test -- --run auth` → 9 test files, 27 tests, all passed (includes `AuthProvider.spec.tsx`, `auth.api.spec.ts`, `customerAuth.api.spec.ts`, `StaffLoginForm.spec.ts`, `StaffAuthGuard.spec.ts`, `StaffLoginPage.spec.ts`)
- `npx tsc -b` → exits clean, no type errors
- `npm run lint` → exits clean, no lint errors

## Manual / Structural Verification

1. From the repo root, inspect `client/src/features/auth/`:
   ```powershell
   Get-ChildItem client/src/features/auth
   ```
   Confirm only `staff/` and `customer/` subfolders are present — no loose files or an `api/`, `providers/`, or `auth.types.ts` directly under `features/auth/`.
2. Inspect `client/src/shared/auth/`:
   ```powershell
   Get-ChildItem -Recurse client/src/shared/auth
   ```
   Confirm `api/auth.api.ts`, `auth.types.ts`, and `providers/AuthProvider/` (`AuthProvider.tsx`, `AuthContext.ts`, `useAuth.ts`, `AuthProvider.spec.tsx`) are present.
3. Confirm no code still points at the old location:
   ```powershell
   Select-String -Path client/src -Pattern "features/auth/(api|providers|auth\.types)" -Recurse
   ```
   Expected result: no matches.
4. Confirm the new location is actually referenced:
   ```powershell
   Select-String -Path client/src -Pattern "shared/auth" -Recurse -List
   ```
   Expected result: matches in `App.tsx` and the staff/customer guards, forms, and API files listed above.

## Acceptance Criteria Checklist

- [x] **AC-1:** `client/src/features/auth/` contains only `staff/` and `customer/` subfolders after the move — no other files or folders remain directly under it
- [x] **AC-2:** `auth.api.ts`, `auth.types.ts`, and the `AuthProvider` (`AuthProvider.tsx`, `AuthContext.ts`, `useAuth.ts`) live under `client/src/shared/auth/`
- [x] **AC-3:** All staff and customer components/guards that previously imported from `features/auth/providers` or `features/auth/api` are updated to import from `client/src/shared/auth/` and continue to function identically
- [x] **AC-4:** No behavioral or test changes beyond import paths — `AuthProvider.spec.tsx` and `auth.api.spec.ts` (and the customer/staff specs that depend on them) continue to pass

## Notes

- No Postman or Supabase artifacts for this issue — it is a client-only file move with no new API routes or DB objects.
- The repo uses `features/auth/customer/` (singular) rather than the `customers/` spelling used in the original planning guide; this does not affect AC-1, which only requires that `features/auth/` contain exclusively the staff/customer subfolders.

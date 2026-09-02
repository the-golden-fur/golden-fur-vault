# Issue #20 Verification: Server auth folder restructure

**Issue:** #20 - refactor(server): move shared auth middleware to `server/src/shared/auth/`
**Sprint:** Sprint 1 - Epic A-1 Addendum
**Scope:** Server-side auth folder restructure, import-path verification, and staff login regression check

## Overview

Issue #20 moves shared server auth middleware out of `server/src/features/auth/` and into `server/src/shared/auth/`. It should be a structure/import-path change only: staff and customer auth behavior must remain unchanged.

During verification, staff login was also checked because the browser was returning `401 Unauthorized` from `/auth/staff/login`. The regression came from the staff email-login contract being partially applied elsewhere: the client still posted `username`, and the server still resolved every login value as a username. The login path now accepts `identifier` while staying backward compatible with `username`.

## Automated Verification

Run these from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run src/shared/auth/middleware/jwt/jwt.middleware.spec.ts src/features/auth/tests/auth.integration.spec.ts src/features/auth/staff/tests/staffAuth.unit.spec.ts src/features/auth/staff/modules/validators/staffAuth.validator.spec.ts
npm --prefix client test -- --run src/features/auth/staff/api/staffAuth.api.spec.ts src/features/auth/staff/modules/validators/staffAuth.validator.spec.ts src/features/auth/staff/components/forms/StaffLoginForm/StaffLoginForm.spec.ts
```

**Follow-up fix (2026-07-04):** the first pass of the identifier fix left `server/src/features/auth/staff/modules/validators/staffAuth.validator.spec.ts` un-updated — it still asserted the old `username`-only shape and was failing (`passes valid input` expected `{ username, password }` echoed back, but the validator now normalizes everything to `{ identifier, password }`). That spec has been rewritten to cover: identifier-shaped input, legacy `username`-shaped input (backward-compat path), email-shaped identifier input, and the missing-field rejection cases.

Also added `console.error('Staff login error:', error)` to the catch block in `staffAuth.controller.ts` (matching the existing pattern already used in `customerAuth.controller.ts`). The controller intentionally still returns a generic `401` to the client either way (per AC-6), but the server terminal will now show _which_ internal step failed:

- `Error: Profile resolution failed` — the `identifier` was treated as a username (no `@`) and the `staff_profiles` lookup by `username` found no row.
- `Error: Authentication failed` — Supabase Auth rejected the email/password pair.

Use this to tell apart "wrong password" from "bad identifier/lookup" when the browser only shows a generic 401.

Expected result:

- Server tests pass, including JWT middleware from `server/src/shared/auth/middleware/jwt/`.
- Staff login route tests pass for username login and email identifier login.
- Client tests pass and confirm staff login posts `identifier`.

## Structural Verification

1. From the repo root, confirm the shared JWT middleware exists in the new shared auth folder:

   ```powershell
   Get-ChildItem server/src/shared/auth/middleware/jwt
   ```

   Expected files:
   - `jwt.middleware.ts`
   - `jwt.middleware.spec.ts`

2. Confirm the old feature-local JWT middleware folder is gone:

   ```powershell
   Test-Path server/src/features/auth/middleware/jwt
   ```

   Expected result: `False`

3. Confirm server auth routes import JWT middleware from the shared path:

   ```powershell
   Select-String -Path server/src/features/auth/**/*.ts -Pattern "shared/auth/middleware/jwt"
   ```

   Expected result: matches in:
   - `server/src/features/auth/staff/staffAuth.routes.ts`
   - `server/src/features/auth/customers/customerAuth.routes.ts`

4. Confirm no code still imports JWT middleware from the old feature path:
   ```powershell
   Select-String -Path server/src/**/*.ts -Pattern "features/auth/middleware/jwt"
   ```
   Expected result: no matches.

## Postman Verification

Use the collection at:

`testing/docs/sprints/sprint1/epicA1/issue-20/postman/issue20.postman_collection.json`

1. Open Postman.
2. Select **Import**.
3. Drag in `issue20.postman_collection.json`, or choose **Files** and browse to the file above.
4. Open the imported collection named **Issue 20 - Server Auth Restructure**.
5. In the collection variables, set:
   - `base_url` to your server URL, usually `http://localhost:3000`.
   - `staff_identifier` to either a staff username or a staff email.
   - `staff_email` to a staff email.
   - `staff_password` to that staff member's password.
   - `customer_email` and `customer_password` to a valid customer account if you want to check the customer JWT-protected route too.
6. Start the server if it is not already running:
   ```powershell
   npm --prefix server run dev
   ```
7. Run **Staff - Login with identifier**.
   Expected result: `200 OK` with `access_token` and `refresh_token`.
8. Run **Staff - Login with email**.
   Expected result: `200 OK` with `access_token` and `refresh_token`.
9. Run **Staff - MFA Enroll uses shared JWT middleware**.
   Expected result: authenticated requests reach the route. A `200 OK` enrollment response or a Supabase MFA-specific `400` means the shared JWT middleware import is working. A `401 Unauthorized` means the token was missing, expired, copied incorrectly, or the login step failed.
10. Run **Customer - Login**, then **Customer - MFA Enroll uses shared JWT middleware**.
    Expected result: same as the staff MFA check.

## Browser Regression Check

1. Start the full app:
   ```powershell
   npm run dev
   ```
2. Open the client in the browser, usually:
   `http://localhost:5173/staff/login`
3. Open DevTools with `F12`, then choose the **Network** tab.
4. Log in with a valid staff username and password.
5. Confirm `/auth/staff/login` returns `200`, not `401`.
6. Sign out if needed, then log in again with the same staff member's email and password.
7. Confirm `/auth/staff/login` returns `200`, not `401`.

Ignore browser-extension-only messages such as `Unchecked runtime.lastError: Could not establish connection. Receiving end does not exist.` They are not produced by this app. The app failure to watch is the `/auth/staff/login` HTTP status.

**If step 5 still returns `401` for username+password (email login working is a separate, already-passing path):** check the terminal running `npm --prefix server run dev` for a line starting `Staff login error:`.

- `Error: Profile resolution failed` means the `staff_profiles` lookup `.eq('username', identifier)` found no row for the exact string typed. This is a data/casing issue, not a code path shared with the email login (which skips this lookup entirely). In the Supabase Dashboard, open **Table Editor → staff_profiles** and confirm the `username` column value is byte-for-byte identical (same case) to what's being typed — the lookup is case-sensitive.
- `Error: Authentication failed` means the username resolved to an email fine, but Supabase Auth rejected the password itself — re-check the password, or check that account in **Authentication → Users** in the dashboard.

## Acceptance Criteria Checklist

- [x] **AC-1:** Shared JWT middleware lives under `server/src/shared/auth/middleware/jwt/`.
- [x] **AC-2:** JWT middleware test is colocated as `server/src/shared/auth/middleware/jwt/jwt.middleware.spec.ts`.
- [x] **AC-3:** Staff and customer auth routes import JWT middleware from `server/src/shared/auth/middleware/jwt/`.
- [x] **AC-4:** No server code imports JWT middleware from the old `server/src/features/auth/middleware/jwt/` location.
- [x] **AC-5:** Auth behavior remains unchanged after the move: staff/customer JWT-protected MFA endpoints still authenticate through the shared middleware.
- [ ] **Regression:** Staff login accepts both username-compatible payloads and email identifier payloads without returning an unintended `401`. Automated tests pass for both paths; live browser confirmation of the username+password path is still outstanding as of 2026-07-04 (see "If step 5 still returns 401" above).

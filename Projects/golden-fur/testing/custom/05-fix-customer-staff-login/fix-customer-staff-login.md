# Fix Customer/Staff Cross-Login - Root Cause and Verification

Type: Custom fix (not tracked against a specific sprint/epic backlog item)
Branch: `fix/customer-staff-login`

Reported symptom: a staff member could log into the customer portal, and a
customer could log into the staff portal. Doing so also triggered a cluster of
console/network errors: `406 Not Acceptable` on `customer_profiles`/
`staff_profiles` `theme_preference` reads, `400` on `POST
/auth/customers/mfa/enroll`, `403 Forbidden` on `GET /staff/:id`, and `400` on
`POST /auth/v1/token?grant_type=refresh_token`.

## Root Cause

Customers and staff are two profile tables (`customer_profiles`,
`staff_profiles`) layered over **one shared Supabase Auth `auth.users` table**.
Nothing enforced that an authenticated account could only reach the portal
matching its own profile table:

1. **`customerLoginController`** (`server/src/features/auth/customers/customerAuth.controller.ts`)
   called `signInWithPassword` and returned a session for _any_ valid Supabase
   Auth credential pair - it never checked that a `customer_profiles` row
   existed for that account. A staff member's own email/password would log
   them into the customer portal.
2. **`staffLoginController`** (`server/src/features/auth/staff/staffAuth.controller.ts`)
   via `resolveStaffLoginIdentifier` (`server/src/shared/auth/api/supabaseAuth.api.ts`)
   only validated `staff_profiles` membership for **username**-shaped input
   (`identifier` without `@`). An email-shaped `identifier` skipped that
   lookup entirely and went straight to `signInWithPassword` - so a
   customer's email/password logged them into the staff portal.
3. Even if a cross-role session existed (from the above, or from directly
   navigating to the other portal's URL with an existing session),
   **`CustomerAuthGuard.tsx` never checked role/profile membership at all**
   (only "is there a session"), and **`StaffAuthGuard.tsx` fetched
   `staff_profiles` role via `GET /staff/:id` but silently ignored a failed
   lookup** (`role` just stayed `null`, and nothing gated on that) - so both
   guards rendered the protected dashboard regardless of whether the signed-in
   user actually belonged there.
4. Downstream of #3, `ThemeProvider` (`client/src/pages/App/App.tsx`,
   `client/src/shared/api/preferences.api.ts`) picks which profile table to
   query for `theme_preference` **from the URL path**, not the verified
   role, and used `.single()` - which throws PostgREST's `406`/`PGRST116`
   ("0 rows") the moment a cross-role (or not-yet-verified) session queries
   the wrong table for its own id. The `mfa/enroll` `400` and `GET /staff/:id`
   `403` were the same underlying cross-role session hitting endpoints that
   correctly reject a non-member of that role.

## Fix

**Server (root cause - reject cross-role credentials at login):**

- `server/src/features/auth/customers/customerAuth.controller.ts`:
  `customerLoginController` now looks up `customer_profiles` by
  `account_email` (via the existing `getCustomerProfileByEmail`) after a
  successful `signInWithPassword`, and returns a generic `401 Unauthorized`
  (no session/tokens) if no row exists.
- `server/src/features/auth/staff/staffAuth.controller.ts`:
  `staffLoginController` now looks up `staff_profiles.role` by the
  authenticated user's id (via the existing `getStaffRole`) after a
  successful `signInWithPassword`, regardless of whether the identifier was
  a username or an email, and throws into the existing generic-`401` catch
  path if no row exists.

**Client (defense in depth - stop rendering the wrong dashboard for any
session that reaches it directly, e.g. a manually-typed URL or a session
from before this fix):**

- `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx`:
  the existing `getStaffProfile` call now tracks a `profileStatus` state
  (`'loading' | 'ok' | 'denied'`). A failed lookup (the `403` from
  `GET /staff/:id`) sets `'denied'`, which signs the user out and redirects
  to `/staff/login` instead of falling through to render the dashboard.
- `client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx`:
  added the same pattern via a new `hasProfile('customer', userId)` check
  (`client/src/shared/api/preferences.api.ts`) - a lightweight
  `customer_profiles` existence check guarded by the table's existing
  "read your own row" RLS policy. `'denied'` signs the user out and
  redirects to `/login`.
- In both guards, the MFA-pending session-storage flag redirect is still
  honored immediately (unchanged behavior), ahead of the new profile check.
- `client/src/shared/api/preferences.api.ts`: `getThemePreference` now uses
  `.maybeSingle()` instead of `.single()`, so a 0-row match (the wrong-table
  case, or the brief window before a cross-role guard finishes signing the
  user out) resolves to "no preference" instead of a `406`.

**Tests updated/added** (mocking changes plus new coverage for the fixed
behavior, no unrelated behavior changes):

- `server/src/features/auth/customers/tests/customerAuth.unit.spec.ts`,
  `customerAuth.integration.spec.ts` - added a `customer_profiles`-lookup
  mock to the existing success-path tests, and a new test asserting `401`
  when the account has no `customer_profiles` row.
- `server/src/features/auth/staff/tests/staffAuth.unit.spec.ts`,
  `server/src/features/auth/tests/auth.integration.spec.ts` - updated the
  shared `supabase.from` mock to answer both the username→email lookup and
  the new role lookup, and added a new test asserting `401` when an
  email-identifier login succeeds against Supabase Auth but has no
  `staff_profiles` row.
- `client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.spec.ts`,
  `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.spec.ts` -
  mocked the new profile checks (defaulting to "found" so existing cases are
  unaffected), and added a new test per guard confirming a denied profile
  check signs the user out and redirects instead of rendering the dashboard.

## Automated Verification

From `server/`:

```powershell
npm.cmd run test
npx tsc --noEmit
```

From `client/`:

```powershell
npm.cmd run test
npx tsc -b
```

Expected: all tests pass (176 server, 109 client as of this fix), both
typechecks clean.

## Manual Verification

You'll need one real staff account and one real customer account (different
email addresses) in your Supabase project, and both `server/` and `client/`
dev servers running (`npm.cmd run dev` in each).

1. **Staff email/password can no longer log into the customer portal.** Go to
   the customer login page (`/login`), enter a **staff** account's email and
   password, and submit. Confirm it's rejected (generic "invalid
   credentials"/`401`-style error) - not a successful login.
2. **Customer email/password can no longer log into the staff portal.** Go to
   `/staff/login`, enter a **customer** account's email and password (the
   `identifier` field accepts email), and submit. Confirm it's rejected the
   same way.
3. **Staff login with username still works normally.** Log into `/staff/login`
   using a staff account's **username** (not email) and correct password.
   Confirm it succeeds and lands on `/staff`.
4. **Staff login with email still works normally.** Log into `/staff/login`
   using that same staff account's **email** and password. Confirm it
   succeeds too (this is the path that was previously vulnerable - confirm
   it still works for a _real_ staff account, only rejecting mismatched
   ones).
5. **Customer login still works normally.** Log into `/login` with a real
   customer account's email/password. Confirm it succeeds and lands on
   `/portal`.
6. **No stray console/network errors.** With DevTools open (Console +
   Network tabs, "Preserve log" on) repeat steps 3-5. Confirm there is no
   `406` on `customer_profiles`/`staff_profiles` theme_preference reads, no
   `400` on `mfa/enroll`, and no `403` on `GET /staff/:id` during a normal,
   same-role login and dashboard load.
7. **Direct-navigation defense in depth.** While signed in as a **customer**
   (session still valid), manually change the browser URL to a `/staff/...`
   route. Confirm you're bounced back to `/staff/login` (not shown the staff
   dashboard, even briefly with broken data). Repeat in the other direction:
   while signed in as **staff**, navigate to a `/portal/...` route and
   confirm you're bounced to `/login`.

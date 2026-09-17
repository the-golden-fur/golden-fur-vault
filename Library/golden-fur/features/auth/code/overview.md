---
title: Auth — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, auth]
project: golden-fur
---

Handles everyone's login for Golden Fur: staff signing into the internal
system and customers signing into the booking portal, plus everything that
guards those sessions afterward — TOTP-based MFA (mandatory for
Admin/Supervisor/Superadmin, optional for everyone else), role checks on
protected routes, Google/Facebook sign-in for customers (including
linking a social login to an existing email/password account instead of
creating a duplicate), and staff password reset.

**Part of:** [[M01-staff-authentication-access-control|M01 — Staff Authentication & Access Control]]

## Client-side (`client/src/features/auth/`)

Split into two independent sub-features, `customer/` and `staff/`, each with
its own routes, pages, forms, and API layer — they share almost nothing
except the `shared/auth` Supabase client wrapper (outside this feature).

### customer/api/
- **`customerAuth.api.ts`** — `signup`/`login` post to the Express
  `/auth/customers/*` endpoints. `signInWithGoogle`/`signInWithFacebook`
  call Supabase's `signInWithOAuth` directly and redirect the browser to
  the provider. `handleOAuthCallback` reads the `access_token`/
  `refresh_token` Supabase drops in the URL hash after the provider
  redirects back, establishes the session client-side, then POSTs the
  bearer token to `/auth/customers/oauth/callback` so the server can
  merge-or-create the `customer_profiles` row. `updateCustomerPassword`
  calls Supabase directly (self-service password change/add from
  Settings).

### customer/components/
- **`buttons/GoogleOAuthButton.tsx`**, **`buttons/FacebookOAuthButton.tsx`** —
  one button each, call `signInWithGoogle`/`signInWithFacebook` on click.
- **`buttons/SocialAuthButtons.tsx`** — lays the two buttons out side by
  side under a "or continue with" divider.
- **`forms/CustomerLoginForm.tsx`** — email/password login plus the two
  social buttons inline. After a successful password login it calls
  `getMfaStatus` to check if this customer previously turned MFA on in
  Settings, and if so redirects to the MFA challenge page instead of the
  portal (MFA is opt-in for customers but enforced every login once on).
- **`forms/CustomerSignupForm.tsx`** — full name/email/password signup
  form, same social buttons.
- **`notices/AccountMergeNotice.tsx`** — a small "Your account was linked
  successfully" message shown for a few seconds on `OAuthCallbackPage`
  when the OAuth login matched (merged into) an existing profile rather
  than creating a new one.

### customer/guards/
- **`CustomerAuthGuard/CustomerAuthGuard.tsx`** — wraps every `/portal/*`
  route. Confirms a session exists, confirms the signed-in user actually
  has a `customer_profiles` row (a valid Supabase session alone isn't
  enough — staff and customers share the same Supabase Auth users, so a
  staff session landing on `/portal` gets signed out), checks MFA status
  and forces the challenge page if enrolled-but-not-yet-verified
  (`aal2`), then renders the portal shell (`AppShell`) with the
  notification bell and message compose button.

### customer/pages/
- **`CustomerLoginPage.tsx`** / **`CustomerSignupPage.tsx`** — the
  marketing-style split-screen layout (feature list on the left, form on
  the right) hosting `CustomerLoginForm`/`CustomerSignupForm`.
- **`CustomerMfaChallengePage.tsx`** — thin wrapper around the shared
  `TotpChallengeForm` component for customers.
- **`OAuthCallbackPage.tsx`** — the page Google/Facebook redirect back to.
  Runs `handleOAuthCallback` once on mount, shows a loading message, then
  either an error, the `AccountMergeNotice` (briefly, before navigating
  to `/portal`), or navigates straight to `/portal`.

### customer/modules/validators/
- **`customerAuth.validator.ts`** — Zod schemas: signup requires a
  non-empty name, valid email, 8+ character password; login just requires
  a valid email and non-empty password.

### customer/ (routes & types)
- **`customerAuth.routes.ts`** — wires `/login`, `/signup`, `/auth/callback`,
  `/portal/mfa/verify` (all public) and `/portal`, `/portal/settings`,
  `/portal/notifications` (behind `CustomerAuthGuard`).
- **`customerAuth.types.ts`** — request/response shapes
  (`CustomerSignupPayload`, `CustomerLoginPayload`, `OAuthCallbackResult`).

### staff/api/
- **`staffAuth.api.ts`** — `login` posts to `/auth/staff/login`.
  `mfaEnroll`/`mfaVerify` drive TOTP setup and challenge.
  `forgotPassword` requests a reset email. `establishRecoverySession`
  reads the `access_token`/`refresh_token`/`type=recovery` hash fragment
  Supabase's password-recovery email link lands on (same pattern as the
  customer OAuth callback) and sets the session client-side.
  `updateStaffPassword` calls Supabase directly to set the new password.

### staff/components/forms/
- **`StaffLoginForm.tsx`** — username-or-email + password login, plus an
  inline "Forgot password" mini-form. After login it calls `getMfaStatus`
  to learn the caller's role and enrollment state: Admin/Superadmin are
  routed to MFA enroll-or-verify unconditionally (mandatory), anyone else
  only if they'd previously opted in.
- **`MfaChallengeForm.tsx`** — 6-digit TOTP code entry, used by
  `MfaChallengePage`. Surfaces the server's exact error message so a 423
  lockout ("Too many invalid MFA codes...") isn't hidden behind a generic
  "wrong code" string.
- **`MfaEnrollForm.tsx`** — an older TOTP-enrollment form (QR code + code
  entry) that is no longer imported anywhere; `MfaEnrollPage` now uses the
  shared `TotpEnrollPanel` component instead. Left in the tree but dead
  code as of this reading.
- **`StaffResetPasswordForm.tsx`** — the page the emailed reset link
  actually lands on. Calls `establishRecoverySession` on mount to verify
  the link and log the recovery session in, then lets the staff member
  set and confirm a new password (8+ characters).

### staff/guards/
- **`StaffAuthGuard/StaffAuthGuard.tsx`** — wraps every `/staff/*` route.
  Loads the caller's real `staff_profiles.role` and username from the
  server (a JWT alone only proves "authenticated", not which staff role),
  enforces MFA (`aal2`) for Admin/Supervisor/Superadmin or anyone who
  opted in, shows a mandatory MFA setup modal for not-yet-enrolled
  Admin/Superadmin instead of a page that would error, and runs a
  role-tiered inactivity timeout (30 min for Admin/Superadmin up to 8
  hours for Groomer/Vet/Pet Assistant) via `useInactivityTimeout`,
  warning with `SessionExpiryModal` before signing out.

### staff/modules/validators/
- **`staffAuth.validator.ts`** — Zod schemas for login (identifier +
  password), a 6-digit TOTP code, forgot-password email, and reset
  password (with a confirm-password match check).

### staff/ (routes & types)
- **`staffAuth.routes.ts`** — wires `/staff/login`, `/staff/mfa/enroll`,
  `/staff/mfa/verify`, `/staff/reset-password` (public) and `/staff`,
  `/staff/settings`, `/staff/notifications` (behind `StaffAuthGuard`).
- **`staffAuth.types.ts`** — request/response shapes
  (`StaffLoginPayload`, `StaffLoginResponse`, `TotpEnrollResponse`, etc).

Every `.module.css` file in this feature (login/signup page and form
styling) is pure CSS with no logic and is skipped above.

## Server-side (`server/src/features/auth/`)

Also split into `customers/` and `staff/` sub-folders, joined by a thin
top-level shim.

### Top-level shim
- **`auth.controller.ts`** — one line: re-exports `staffLoginController`
  from `staff/staffAuth.controller.ts` (legacy import path kept alive).
- **`auth.routes.ts`** — mounts `staff/staffAuth.routes.ts` and
  `customers/customerAuth.routes.ts` both under `/auth`.
- **`auth.types.ts`** — re-exports the shared `AuthenticatedRequest`/
  `JwtPayload` types plus a couple of legacy `StaffLoginRequest`/
  `StaffLoginResponse` interfaces.

### Controller & routes (staff)
- **`staffAuth.controller.ts`** — `staffLoginController` resolves a
  username-shaped identifier to an email (`resolveStaffLoginIdentifier`),
  signs in with Supabase, then explicitly checks the account has a
  `staff_profiles` row — without this check, a customer's own
  email/password would also work as a staff login, since both share the
  same Supabase Auth user pool. It also clears a one-time
  `temp_credential_ciphertext`/`_iv` (the emailed temporary password)
  after a first successful login. `mfaEnrollController`/
  `mfaVerifyController`/`mfaStatusController`/`mfaUnenrollController`
  drive TOTP setup, verification (with a lockout counter after repeated
  wrong codes, see `mfaLockout.service.ts`), status, and removal.
  `forgotPasswordController` calls Supabase's `resetPasswordForEmail` and
  best-effort logs an in-app "Password reset requested" notification.
- **`staffAuth.routes.ts`** — wires `/staff/login`, `/staff/mfa/*`,
  `/staff/forgot-password`, plus (a bit outside pure auth, but living in
  this file) `staffPreferencesController` and
  `staffNotificationPreferencesController` for the Settings > Preferences
  tab (theme/font-size/weight-unit and per-event notification channel
  toggles), both scoped to the caller's own `staff_profiles` row via a
  request-scoped Supabase client built from the caller's own bearer
  token.
- **`middleware/requireBranch/requireBranch.middleware.ts`** — looks up
  the caller's role and `branch_id` and attaches them to `req.user`,
  401 if unauthenticated, 403 if no matching staff row.
- **`middleware/requireMfa/requireMfa.middleware.ts`** — for
  Admin/Supervisor/Superadmin, rejects (403 "MFA required") any request
  whose JWT `aal` isn't `aal2`, i.e. hasn't completed a TOTP challenge
  this session.
- **`middleware/requireRole/requireRole.middleware.ts`** — a middleware
  *factory*: `requireRole(['Admin', 'Superadmin'])` returns middleware
  that 403s unless the caller's `staff_profiles.role` is in that list.
  This is the RBAC building block other features' routes use to
  role-gate endpoints.

### Controller & routes (customers)
- **`customerAuth.controller.ts`** — `customerSignupController` creates
  the Supabase Auth user via the admin API (skips the confirmation email,
  which would otherwise hit a 2/hour rate limit), inserts a
  `customer_profiles` row, then signs in to hand back a session.
  `customerLoginController` signs in, then — same reasoning as staff login
  in reverse — rejects the login if no `customer_profiles` row exists for
  that email, so a staff member's credentials can't reach the customer
  portal. `customerMfaEnrollController`/`Verify`/`Status`/
  `UnenrollController` mirror the staff MFA endpoints. 
  `customerOauthCallbackController` is the security-sensitive one: it
  takes the bearer token the client got from Supabase after the
  Google/Facebook redirect, verifies it against Supabase
  (`supabase.auth.getUser`), then calls `mergeOrCreate` to either link
  this OAuth identity to an existing profile or create a new one.
- **`customerAuth.routes.ts`** — wires `/customers/signup`, `/login`,
  `/mfa/*`, `/oauth/callback`, plus the same preferences/notification-
  preferences endpoints as the staff side, scoped to `customer_profiles`.

### Service
- **`services/accountMerge.service.ts`** — `mergeOrCreate(session)` is the
  account-merge logic: it reads the OAuth provider, email, display name,
  and provider ID off the Supabase session's user object. If a
  `customer_profiles` row already exists for that `account_email`
  (e.g. the customer originally signed up with email/password, then later
  clicks "Continue with Google" using the same address), it **merges** —
  updates `primary_auth_provider` (and `facebook_id` for Facebook) on the
  *existing* row rather than creating a second profile. If no row exists,
  it **creates** a new one. Throws `MissingProviderEmailError` if the
  provider never handed Supabase a confirmed email (e.g. an unconfirmed
  Facebook email) — the controller turns that into a clear 422 instead of
  a generic failure.

### Types & validators
- **`customers/customerAuth.types.ts`** — `CustomerAuthInput`,
  `CustomerProfile` (including `primary_auth_provider` and
  `facebook_id`).
- **`customers/modules/validators/customerAuth.validator.ts`** — Zod:
  signup (name, email, 8+ char password), login, and a 6-digit TOTP code
  regex.
- **`staff/staffAuth.types.ts`** — `StaffLoginPayload`,
  `StaffAuthContext`.
- **`staff/modules/validators/staffAuth.validator.ts`** — *not* Zod (the
  only validator in this feature that isn't): a hand-rolled
  `safeParse`-shaped object for login (accepts either `identifier` or a
  legacy `username` field) and for the TOTP code, matching Zod's
  `{success, data}`/`{success, error}` result shape so callers don't need
  to know the difference.

## How it connects

A staff login goes `StaffLoginForm` → `POST /auth/staff/login` →
`staffAuth.controller.ts`'s `staffLoginController`, which authenticates
against Supabase Auth and then checks the `staff_profiles` table before
issuing a session; a customer login follows the same shape against
`customer_profiles`. Once signed in, `StaffAuthGuard`/`CustomerAuthGuard`
on the client and `requireMfa`/`requireRole`/`requireBranch` on the server
gate everything downstream — `requireRole` in particular is the shared
RBAC primitive other features' route files call to restrict endpoints to
specific staff roles. OAuth sign-in is Supabase-native on the client
(`signInWithOAuth`), with the account-merge decision made server-side in
`accountMerge.service.ts` against `customer_profiles`. `staff_profiles`
rows themselves are created by a separate flow — see
[[M01-01-staff-account-creation|Staff Account Creation]] — which this
feature's login/RBAC code depends on but doesn't create.

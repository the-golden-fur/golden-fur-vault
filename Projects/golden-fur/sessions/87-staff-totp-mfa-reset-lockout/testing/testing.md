# Staff (and customer) TOTP MFA "random reset" lockout fix

Branch: `fix/staff-totp-mfa-verified-factor-reset` (already committed as
`b7de85d`).

## The request, verbatim

> As a developer, I want the staff MFA TOTP codes to not be refreshed
> randomly, so that users don't lose access to their account. Somehow, TOTP
> codes in google authenticator randomly resets, and still prompts for a
> TOTP code. There's no longer a QR code to scan, making it impossible to
> access. I want you to determine what is causing this random reset and fix
> it.
> — task description, referencing `Architectural-Change-History.docx`

Follow-up clarification given mid-session: the lockout is usually noticed
after a redeploy/restart (`npm run dev`), and the only reliable fix so far
has been resetting the local database, which works again for a while before
drifting back.

See `../plan.md` for the near-beginner walkthrough (glossary included) —
this doc only covers verification.

## Root cause / Context

`enrollTotpFactor` (`server/src/shared/auth/api/supabaseAuth.api.ts`), the
shared helper both the staff and customer "start MFA enrollment" endpoints
call, had a three-tier conflict-recovery fallback for the case where
Supabase Auth reports a factor with the same name already exists. Tier 1/2
clean up stray _unverified_ factors and retry — safe. Tier 3, reached only
when the conflict survives that retry (meaning a real, already-_verified_
factor is what's conflicting), deleted **any** factor — verified or not —
and immediately minted a brand-new one with a new secret and new QR code.
That tier-3 deletion is the actual "codes randomly reset" bug: a working
authenticator app code stops validating with no warning, and the person is
never guaranteed to see the replacement QR that was silently generated in
its place.

Three separate places could end up calling "start enrollment" again for an
account that was already fully enrolled and verified, each one a path to
hitting that tier-3 conflict:

- `StaffLoginForm.tsx` defaulted `mfa_enrolled` to `false` whenever the
  post-login "am I already enrolled?" status check errored or timed out —
  most likely right after a server restart, matching the reported pattern —
  routing an enrolled account into the enroll screen instead of the
  code-entry screen.
- `MfaEnrollPage.tsx` rendered the "scan this QR" panel and started a new
  enrollment the instant it loaded, with no check first for whether the
  account was already enrolled — reachable via a stale bookmark, the
  back/forward button, or a second tab.
- `SecurityTab.tsx`'s "which roles are mandatory" role set was missing
  Supervisor (even though `StaffAuthGuard.tsx`'s own mandatory-MFA check and
  its `MfaSetupModal` already included Supervisor), so an unenrolled
  Supervisor visiting Settings → Security would get a second, independent
  enrollment panel racing the guard's own popup.

## What changed

### Server

- `server/src/shared/auth/api/supabaseAuth.api.ts` — `enrollTotpFactor`'s
  tier-3 "delete verified factors too and retry" fallback is removed
  entirely. If a conflict survives the unverified-cleanup retry, the
  function now just returns that conflict as-is instead of touching
  anything. A verified factor can now only ever be removed by an explicit,
  user-initiated unenroll action, never as a side effect of enrolling.
- `server/src/features/auth/staff/staffAuth.controller.ts` and
  `server/src/features/auth/customers/customerAuth.controller.ts` —
  `mfaEnrollController` / `customerMfaEnrollController` now call
  `getTotpEnrollmentStatus` first. If the account is already enrolled, they
  return **409** (`{"error": "MFA is already enrolled for this account."}`)
  and never call `enrollTotpFactor` at all. This closes the door at the API
  level regardless of which client screen or bug tries to re-enroll.

### Client

- `client/src/shared/api/mfa.api.ts` — `MfaApiResult<T>` now also carries
  the raw HTTP `status`, so callers can distinguish "409 already enrolled"
  from a generic error.
- `client/src/shared/components/TotpEnrollPanel/TotpEnrollPanel.tsx` — a
  second layer of defense: if `enrollMfa` comes back 409, the panel now
  shows "MFA is already set up for this account." instead of a broken/empty
  enroll form, and calls a new optional `onAlreadyEnrolled` prop (falls back
  to `onEnrolled` if not supplied) instead of ever offering a "start over"
  action that could unenroll a working credential.
- `client/src/features/auth/staff/pages/MfaEnrollPage/MfaEnrollPage.tsx` —
  now re-checks real enrollment status (`getMfaStatus`) before rendering
  anything. While that check is pending, no QR form is shown at all; if the
  account turns out to already be enrolled, it redirects to
  `/staff/mfa/verify` instead of ever starting a new enrollment; the panel's
  new `onAlreadyEnrolled` also routes there as a belt-and-suspenders catch.
- `client/src/features/auth/staff/components/forms/StaffLoginForm/StaffLoginForm.tsx`
  — `isMfaRole` now includes `Supervisor` (matching `StaffAuthGuard.tsx`'s
  own list); and a failed/errored `getMfaStatus` call after login now shows
  "Unable to confirm your account security status. Please try signing in
  again." instead of silently treating the account as unenrolled and
  routing it to the enroll screen.
- `client/src/pages/SettingsPage/tabs/SecurityTab.tsx` —
  `MANDATORY_MFA_ROLES` now includes `Supervisor`, so a Supervisor without
  MFA sees the same "MFA is required for your role... it will keep
  appearing until enrollment is finished" message the other mandatory roles
  see, with no second inline enrollment panel racing the guard's popup.

## Manual test — step by step

Both dev servers must be running first: the server (`cd server && npm run
dev`, listening on `http://localhost:3000`) and the client (`cd client &&
npm run dev`, listening on `http://localhost:5173`). Have a REST client
(Postman, Insomnia, or `curl`) available for scenario A.

All staff test accounts use the password `password123` and follow the
pattern `<branch>.<role>N@goldenfur.com`, e.g. `makati.admin1@goldenfur.com`,
`makati.supervisor2@goldenfur.com` (see
`supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts`). Pick an account you
know is **not yet MFA-enrolled** for scenarios C and D — if every seeded
account on your local database has already been enrolled from earlier
testing, either use a role/branch combo you haven't touched yet, or reset
MFA on one first (Settings → Security → **Disable MFA**, while signed in as
that account and already past a code challenge).

### A. The original bug repro, confirmed fixed — re-enrolling an

already-verified account no longer destroys it

This is the core regression test: it directly repeats the exact request
sequence that used to silently swap out a working authenticator secret.

1. Open `http://localhost:5173`, click **Staff Login**, sign in with a
   fresh (not-yet-enrolled) Admin account, e.g. `makati.admin2@goldenfur.com`
   / `password123`.
2. You should land on **Set Up MFA** (a QR code and a 6-digit input). Scan
   the QR with an authenticator app (Google Authenticator or similar) and
   enter the 6-digit code it shows. Confirm you land on the staff
   **Dashboard** — this account is now fully enrolled and verified.
3. Note the authenticator app's current 6-digit code for this account (it
   changes every 30 seconds, so keep the app open).
4. In your REST client, log in via the API directly to get a fresh access
   token:
   - `POST http://localhost:3000/auth/staff/login`
   - Body (JSON): `{"identifier": "makati.admin2@goldenfur.com", "password": "password123"}`
   - Copy the `access_token` from the response.
5. Now call the enroll endpoint again for this already-enrolled account:
   - `POST http://localhost:3000/auth/staff/mfa/enroll`
   - Header: `Authorization: Bearer <access_token from step 4>`
   - No body needed.
   - **Confirm the response is `409`** with
     `{"error": "MFA is already enrolled for this account."}` — not a `200`
     with a new QR code/secret. Before this fix, this call would have
     silently deleted the account's real factor and returned a brand-new
     QR/secret instead.
6. Back in the browser, sign out and sign back in as
   `makati.admin2@goldenfur.com` / `password123`. You should land on the
   **code-entry challenge** screen (not a QR code). Enter the **same**
   6-digit code your authenticator app is currently showing for this
   account (from step 3's app entry — it will have rotated to a new code by
   now, but from the same, still-intact secret). Confirm it's accepted and
   you land on the Dashboard. If the original authenticator entry had been
   silently replaced, this step would fail with "invalid code" and there
   would be no QR code anywhere to re-scan — exactly the reported bug.

### B. Navigating directly to `/staff/mfa/enroll` as an already-enrolled account

1. While still signed in (or sign back in) as the `makati.admin2@goldenfur.com`
   account from scenario A, past its MFA challenge, on the Dashboard.
2. Click the browser's address bar, type
   `http://localhost:5173/staff/mfa/enroll`, and press Enter — simulating a
   stale bookmark or the back button landing here.
3. Confirm the page briefly shows the **Set Up MFA** card with no QR
   code/input flashing into view, then **redirects you to
   `/staff/mfa/verify`** (the code-entry screen), not a fresh QR code. If
   you're prompted for a code there, entering your authenticator app's
   current code should work — confirming the account's real factor was
   never touched.

### C. Supervisor mandatory-MFA popup + Settings → Security — only one

enrollment flow active

1. Sign in as a Supervisor account you've confirmed is **not yet
   enrolled**, e.g. `makati.supervisor2@goldenfur.com` / `password123`.
2. Confirm a popup/modal titled **Set up multi-factor authentication**
   appears over the app (this is `MfaSetupModal`, triggered because
   Supervisor is a mandatory-MFA role) — it should show a QR code and a
   6-digit input, exactly like the dedicated enroll screen.
3. **Without completing it**, open a new tab (or use the same tab if the
   modal doesn't block navigation) and go to
   `http://localhost:5173/staff/settings` (or click the Settings icon in
   the navbar), then the **Security** tab.
4. Confirm the Security tab shows the text "MFA is required for your role
   and is not yet set up. Complete setup in the popup — it will keep
   appearing until enrollment is finished." and **does not** also render a
   second QR code/enrollment form inline on the page. Before this fix, an
   unenrolled Supervisor would have seen a second, independent
   `TotpEnrollPanel` here at the same time as the modal's — two enrollments
   racing each other.
5. Go back to the modal, scan its QR code, enter the code, and confirm it
   closes and the Security tab (if still open) updates to "MFA is enabled
   on your account."

### D. Golden path — first-time enrollment for a fresh account still works

1. Sign in as any never-enrolled staff/admin account not used above, e.g.
   `southwoods.admin1@goldenfur.com` / `password123` (or any role — for a
   non-mandatory role like Receptionist, first enroll voluntarily via
   Settings → Security instead of being forced at login).
2. Confirm you land on **Set Up MFA** with a real QR code and a secret/key
   displayed, exactly as before this session's changes.
3. Scan the QR with an authenticator app, enter the 6-digit code, and
   confirm you land on the Dashboard with no errors.
4. Sign out and sign back in with the same account/password. Confirm you
   now land on the **code-entry challenge** screen (not a QR code) and that
   your authenticator app's current code is accepted.

## Test suites

Run and confirmed passing earlier in this session (not re-run for this
doc):

- `server`: `npx vitest run` — 62 tests passing across
  `supabaseAuth.api.spec.ts`, `staffAuth.unit.spec.ts`,
  `customerAuth.unit.spec.ts`; `npx tsc --noEmit` clean; `eslint` clean.
- `client`: `npx vitest run` — 58 tests passing across the
  `TotpEnrollPanel`, `StaffLoginForm`, `StaffAuthGuard`, and `SettingsPage`
  suites; `npx tsc --noEmit` clean; `eslint` clean.
- Prettier: clean on every touched file (checked from repo root, per this
  repo's convention).

## Open items

- No `.postman_collection.json` was added — scenario A above is the
  Postman-equivalent regression check for the 409 behavior, but a
  standalone collection covering `/auth/staff/mfa/enroll` and
  `/auth/customers/mfa/enroll` would still be worth adding later for
  repeatable API-level regression coverage.
- The customer-portal equivalent (`customerMfaEnrollController`,
  `/portal/mfa/enroll`) received the same 409 guard server-side, but this
  session's manual test only walks the staff side end-to-end — the
  customer portal's own enroll page wasn't re-checked for the same
  gate-before-render treatment `MfaEnrollPage.tsx` got, since the customer
  login form's error-swallowing and the Settings mandatory-role gap (this
  session's other two fixes) are both staff-only surfaces.
- This fix does not add any monitoring/alerting for a 409 "already
  enrolled" response being hit in practice — if the login-form or
  enroll-page checks still have some other bypass path, there's no signal
  that would surface it beyond a user reporting a lockout again.

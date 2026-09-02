# Staff MFA Verify 500 - Fix and Verification

Type: Custom fix (not tracked against a specific sprint/epic backlog item)
Branch: `dev` (no dedicated branch existed at time of fix)

Reported symptom: signing in as staff (both a mandatory-MFA Admin account and
an optional-MFA Groomer account), going to `/staff/mfa/enroll`, and submitting
the 6-digit code always returned `500` from `POST /auth/staff/mfa/verify`,
regardless of whether the code was correct.

## Root Cause

The server's admin Supabase client (`server/src/config/supabase/supabase.config.ts`,
the `supabase` export) is a **module-level singleton** created once at process
start with the service-role key, and used for every privileged, cross-user
database operation on the server.

`signInWithPassword` in `server/src/shared/auth/api/supabaseAuth.api.ts` was
calling `supabase.auth.signInWithPassword(...)` directly **on that shared
singleton** during every staff login. Supabase-js's `GoTrueClient` defaults to
`persistSession: true`, so a successful sign-in mutates the client's internal
session state and - critically - causes all _subsequent_ requests issued
through that same client (via `.from(...)`) to be sent with `Authorization:
Bearer <that user's access token>` instead of the service-role key. In effect,
the very first staff login on a freshly started server permanently downgrades
the "admin" client to that one user's `authenticated`-role, RLS-restricted
session for the rest of the process's lifetime (until a different login
overwrites it again).

This was invisible for most of the app because most `staff_profiles`/etc.
reads happen to be allowed for `authenticated` users under existing RLS
policies. It became fatal for `mfa_lockouts`
(`supabase/migrations/20260702017_shared_mfa_lockouts_rls.sql`), which only
defines a `select` policy - there is no `insert`/`update` policy at all, since
writes were only ever meant to happen via the trusted service-role client.
`mfaVerifyController` calls `incrementMfaLockout`/`resetMfaLockout`
(`server/src/shared/services/mfaLockout/mfaLockout.service.ts`) after every
verify attempt, which `.upsert()`s into `mfa_lockouts`. With the singleton
downgraded to the logged-in user's session, that upsert was rejected by
Postgres with `42501 - new row violates row-level security policy for table
"mfa_lockouts"`, which `mfaVerifyController`'s catch-all `catch { return
res.status(500)... }` silently turned into a generic `Internal server error`
with no logging - hence the opaque 500 in the browser, for _every_ code
(right or wrong).

This bug is **not new** and unrelated to the Facebook/Google OAuth fix
(commit `35c5a288`) that was originally suspected - it predates it. The exact
same session-pollution hazard was already found and fixed on the _customer_
side back in commit `c856477` (#28), which added a `createSignInClient()`
throwaway-client helper specifically to avoid calling `signInWithPassword` on
the shared singleton, with a comment explaining why. The equivalent staff-side
helper (`supabaseAuth.api.ts`, added later in #33) was never updated to use
that pattern, so it kept calling `signInWithPassword` on the shared client
directly. Reproduced live with a running dev server and confirmed: a fresh,
never-logged-in server's admin client passes RLS-bypass writes fine; the
moment any staff login occurs, the same write starts failing with `42501`.

## Fix

`server/src/shared/auth/api/supabaseAuth.api.ts`:

- Added `createSignInClient()` (mirrors `customerAuth.controller.ts`'s
  existing helper) - a throwaway `createClient(SUPABASE_URL,
SUPABASE_SERVICE_ROLE_KEY)` instance used only for the sign-in call itself
  and then discarded.
- `signInWithPassword(email, password)` now calls
  `createSignInClient().auth.signInWithPassword(...)` instead of
  `supabase.auth.signInWithPassword(...)`, so the shared admin singleton's
  session is never touched by a staff login.

No database/RLS changes were needed - the fix stops the admin client from
ever holding a real user's session, which is the only thing that made the
write path fall out of service-role privileges.

**Tests updated** (mocking changes only, no behavior changes):

- `server/src/shared/auth/api/supabaseAuth.api.spec.ts`
- `server/src/features/auth/staff/tests/staffAuth.unit.spec.ts`
- `server/src/features/auth/tests/auth.integration.spec.ts`

All now mock `@supabase/supabase-js`'s `createClient` and assert against the
throwaway sign-in client instead of `supabase.auth.signInWithPassword`.

## Automated Verification

From `server/`, run:

```powershell
npm.cmd run test
```

Expected result: all test files pass (151 tests as of this fix, including the
3 updated staff-login spec files above).

## Manual Verification

This bug only reproduces after an actual login happens on a given server
process - a server that has never processed a staff login will not show it
even without the fix, so restart the dev server before testing to get a clean
process.

1. From `server/`, stop any running dev server, then start a fresh one:
   `npm.cmd run dev`. Leave it running.
2. From `client/`, run `npm.cmd run dev` (if not already running) and open the
   printed local URL.
3. Sign in at `/staff/login` with a staff account that has **not yet enrolled
   MFA** (either a mandatory Admin/Superadmin account, or any other role -
   both paths go through the same buggy code).
4. Complete enrollment: scan the QR (or use the manual key/URI shown) in an
   authenticator app, enter the current 6-digit code, and submit.
5. Confirm the request succeeds (`200`, no error banner) and you land on
   `/staff` - **not** a red "Invalid verification code." message or a network
   500 in DevTools.
6. Open DevTools > Network, filter on `mfa/verify`, and confirm the response
   status is `200`.
7. As a regression check for the specific root cause: repeat steps 3-6 with a
   **second, different** staff account signing in on the same still-running
   server process (do not restart the server between the two). Before the
   fix, the second account's verify would still fail the same way even though
   it's a totally different user - confirming the fix isn't just "it happened
   to work once."
8. Sign out and sign back in as either account (now enrolled). Confirm the
   `/staff/mfa/verify` challenge screen also succeeds with a correct code on
   a normal login (not just first-time enrollment).

## Follow-up: `/staff/mfa/enroll` Full Page Had an Unscannable, Duplicate QR UI

After the backend fix above, manual testing as a Superadmin still couldn't
scan the QR shown at `/staff/mfa/enroll` (the full-page flow a fresh
Admin/Superadmin login always redirects to first - see `isMfaRole` branch in
`StaffLoginForm.tsx`). This page was **not** the `MfaSetupModal` popup or the
Settings enroll section - both of those already render `TotpEnrollPanel`
(`client/src/shared/components/TotpEnrollPanel/`), which was already fixed
for exactly this in an earlier round: 280x280px QR, a copyable raw base32
secret (not the full `otpauth://` URI), and it surfaces the server's actual
error message instead of a hardcoded one.

`/staff/mfa/enroll` (`MfaEnrollPage.tsx`) instead rendered its own separate,
older `MfaEnrollForm.tsx` component that never got that fix: a small
unstyled `<img>`, no copyable secret (only the full `otpauth://` URI dumped
as text - not something you can type into an authenticator app), and every
error (including a real backend 500) collapsed to a hardcoded "Invalid
verification code." This is also why, when the RLS bug above was still live,
its actual cause was hard to see from the UI alone.

**Fix:** `MfaEnrollPage.tsx` now renders the same `TotpEnrollPanel` the
popup and Settings already use, instead of `MfaEnrollForm`. All three
enrollment surfaces (mandatory popup, Settings, and the full-page redirect)
now share one implementation. `MfaEnrollForm.tsx` itself was left in place,
unused, rather than deleted - deleting existing files wasn't part of this
request.

### Manual Verification (QR fix)

1. With `client/`'s dev server running, sign in as an Admin/Superadmin
   account that has not completed enrollment (or click "Start over" on the
   current stuck screen to get a fresh factor).
2. Confirm you land on `/staff/mfa/enroll` and see a large (280x280px) QR
   code plus a separate "Can't scan? Enter this key manually" box containing
   only the short base32 secret (not the full `otpauth://` link).
3. Scan the QR with an authenticator app (or type just that secret in
   manually) and confirm the app produces a code that this page accepts.
4. If it still fails, confirm the error banner now shows the **real** server
   message (e.g. "Invalid code", "MFA verification locked", or an actual
   `Internal server error` if the backend issue above has somehow
   resurfaced) instead of the old hardcoded "Invalid verification code." -
   that message is itself useful for telling which layer is failing.

## Notes

- This is purely a backend session-management bug; no client-side files were
  touched.
- If a similar 500 ever resurfaces on the _customer_ MFA path, it's `git
grep signInWithPassword` first - `customerAuth.controller.ts` already uses
  the safe `createSignInClient()` pattern, so a regression there would mean
  someone reintroduced a direct call on the shared `supabase` singleton.

## Third Round: Infinite Re-Verify Loop, Unscannable Staff QR, Wrong Issuer Name

Manual testing after the fixes above surfaced three more issues, all client-
side except the issuer name:

**1. Infinite verify loop (customer and staff).** After a successful enroll +
verify, both `CustomerAuthGuard.tsx` and `StaffAuthGuard.tsx` immediately
bounced the user right back to the challenge page, forever. Root cause: both
guards read `aal` off `session.user.aal` -
`(session.user as { aal?: string }).aal` - but **`aal` is a claim inside the
access token's JWT payload, not a field on the Supabase `User` object**.
That read was always `undefined`, so `aal !== 'aal2'` was always `true`,
so `needsAal2` never turned false even immediately after a real aal2 verify -
an infinite redirect loop back to the challenge screen. This bug existed for
both staff and customer identically; it likely only presented as fixed for
staff because the mandatory-role popup path masks it differently on first
enrollment (redirects to `/staff` before the guard's status re-check lands),
whereas customers hit the loop immediately and visibly on every login.

Fixed: added `getSessionAal(session)` to `client/src/shared/auth/api/auth.api.ts`,
which decodes the `aal` claim directly from `session.access_token`'s JWT
payload. Both guards now call this instead of reading `session.user.aal`.

**2. Unscannable QR code for staff (login redirect and Settings), but fine
for customers.** `TotpEnrollPanel.module.css`'s `.qrCode` background was
`var(--color-bg-primary)` - a theme token. The customer theme's
`--color-bg-primary` (`#f7f2e8`, cream) happens to be light, so the QR (an
SVG with a transparent background, black modules only) read fine. The staff
theme's `--color-bg-primary` (`#1f140b`) is near-black, so the same QR
rendered as black-on-near-black - unreadable by any scanner. Fixed: the QR
now always sits on a fixed white background regardless of theme, and is
centered (`margin: 0 auto`) along with the manual-entry secret box beneath
it, matching how the customer version looked (by coincidence of its theme
colors, not by any actual centering rule that existed before).

**3. Authenticator app showed "localhost:5173" as the issuer/app name.**
`enrollTotpFactor(userClient)` called `userClient.auth.mfa.enroll({
factorType: 'totp' })` with no `issuer`, so Supabase fell back to the
project's configured Site URL. Fixed: all three enroll attempts (initial,
retry-after-unverified-cleanup, and the escalated verified-cleanup retry)
now pass `issuer: 'Golden Fur'` explicitly.

### Files changed (this round)

- `client/src/shared/auth/api/auth.api.ts` - added `getSessionAal()`.
- `client/src/features/auth/customer/guards/CustomerAuthGuard/CustomerAuthGuard.tsx`
  and `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` -
  use `getSessionAal()` instead of `session.user.aal`.
- `client/src/shared/components/TotpEnrollPanel/TotpEnrollPanel.module.css` -
  fixed white QR background, centered QR and manual-entry box.
- `server/src/shared/auth/api/supabaseAuth.api.ts` - `enrollTotpFactor` now
  passes `issuer: 'Golden Fur'` on every enroll attempt.
- Test mocks updated to match in `CustomerAuthGuard.spec.ts`,
  `StaffAuthGuard.spec.ts`, `supabaseAuth.api.spec.ts`, and
  `customerAuth.unit.spec.ts` (encoding a fake JWT payload for "already
  aal2" test cases, since `session.user.aal` is no longer read).

### Automated Verification (this round)

```powershell
# from server/
npm.cmd run test
# from client/
npm.cmd run test
npx tsc -b
```

Expected: all tests pass (151 server, 63 client), typecheck clean.

### Manual Verification (this round)

1. Restart both dev servers fresh (`server/`: `npm.cmd run dev`,
   `client/`: `npm.cmd run dev`).
2. Sign in as a **customer** account, go to `/portal/settings`, enroll MFA
   (scan or manually enter the now-centered, white-background QR/secret),
   submit the code. Confirm you land back on Settings with "MFA is enabled
   on your account." - **not** bounced back to a code prompt again.
3. Sign in as a **staff** account (mandatory or optional role), complete
   enrollment at `/staff/mfa/enroll` or `/staff/settings`. Confirm the QR is
   clearly scannable (white background, centered) and that after verifying
   you land on `/staff` (or Settings, for the optional-role/Settings path)
   without looping back to a code prompt.
4. Sign out and back in on either account (already enrolled). Confirm the
   challenge screen accepts a correct code once and proceeds - no loop.
5. Open the authenticator app entry created during enrollment. Confirm the
   app/issuer name reads **"Golden Fur"**, not "localhost:5173".

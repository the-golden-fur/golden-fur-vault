# MFA Enroll/Verify Fix - Verification

Sprint: Sprint 1
Type: Custom fix (not tracked against a specific sprint/epic backlog item)
Branch: `fix/mfa-enroll-and-verify`

This is a custom fix, filed against the recurring Postman report "MFA verify
often fails with TOTP factor not found." It touches the same TOTP/MFA surface
as several Epic A-1 issues (#10, #14, #16, #20, #21), but is not itself one of
them - it lives under `testing/docs/sprints/sprint1/custom/01-fix-mfa/`.

## Why Verify Was Failing

Investigating the report turned up three compounding bugs, not just flaky
Postman code entry:

1. **The login response never carried `role`/`mfa_enrolled`.** `StaffLoginResponse`
   declared those fields, but `staffLoginController` never populated them, so the
   client's redirect-to-enroll-vs-verify branch and the "which roles need MFA"
   check were silently working off `undefined` in production.
2. **The mandatory-MFA role list said `Supervisor` instead of `Superadmin`** in all
   three places that gate it (`requireMfa.middleware.ts` server-side,
   `isMfaRole` in `StaffLoginForm.tsx`, `requiresMfa` in `StaffAuthGuard.tsx`).
   Per the request this fixes, only **Admin** and **Superadmin** should be
   forced into MFA; Supervisor and below are optional.
3. **Repeated Enroll calls piled up orphaned unverified TOTP factors.** Nothing
   ever called `supabase.auth.mfa.unenroll()`, so re-running Enroll against the
   same account (very easy to do across Postman sessions) left multiple
   unverified factors behind. Verify's `listFactors()` lookup then had no
   reliable way to know which factor's secret the tester had actually scanned,
   and accounts that were never enrolled at all correctly - but confusingly -
   400'd with `"No TOTP factor found"`.

There was also no client-side entry point to ever call Enroll for most roles:
`/staff/mfa/enroll` only appeared in the post-login redirect for the (mistyped)
mandatory-MFA roles, and customers had zero MFA UI at all despite the server
endpoints already existing.

## Follow-up Round: Race Condition, Unenroll, Manual Key Entry

After the first pass shipped, manual browser testing against `/portal/settings`
surfaced a real 400 on Enroll: `A factor with the friendly name "" for this
user already exists`. Root cause: `TotpEnrollPanel`'s mount effect called
`enrollMfa()` once, but **React 18 StrictMode double-invokes effects in dev**
(mount -> cleanup -> mount again, by design, to surface exactly this class of
bug) - so two `enroll()` calls raced each other. Both listed zero existing
factors before either had actually created one, so both proceeded to create a
factor, and the second insert collided on Supabase's per-user unique
`friendly_name` constraint. Once created, the surviving unverified factor
could get stuck with nothing on the client able to clear it - the reported
"known gap," filled in this round.

## Third Round: Two `TotpEnrollPanel`s Racing Each Other on `/staff/settings`

The StrictMode fix above closed one race, but a second, more consequential one
turned up in manual testing: an unenrolled Admin/Superadmin visiting
`/staff/settings` would scan a QR, enter a real code from their authenticator
app, and still get rejected - and the "Start over" recovery button would
itself 400 on its own retry.

Root cause: `SettingsPage` rendered its own `TotpEnrollPanel` inline whenever
`!status.mfa_enrolled`, with no exception for the mandatory roles - "defensive"
coverage in case the popup somehow didn't catch it. But `StaffAuthGuard`
already renders `MfaSetupModal` (its own separate `TotpEnrollPanel` instance)
as an overlay on _every_ `/staff/*` page, including Settings, whenever an
Admin/Superadmin isn't enrolled. That meant **two independent panel instances
were mounted at once**, each calling `enrollMfa()` on its own mount. The
per-instance `useRef` guard from the StrictMode fix only stops a single
instance from double-enrolling itself - it can't stop a _second, separate_
instance from also enrolling. Whichever panel's factor was created second
silently invalidated the other one's QR/secret (per the enroll-cleanup
behavior fixed in the first round, since each enroll cycle unenrolls the
other's still-unverified factor before creating its own). Whatever the user
scanned into their authenticator app then no longer matched the currently
live factor by the time they submitted a code - a completely valid TOTP code
for a factor that had already been replaced.

Also fixed while diagnosing this:

- `TotpEnrollPanel`'s verify handler was overwriting every server error with a
  hardcoded `"Invalid verification code."` string, which is exactly what made
  this bug hard to see from the UI alone - a _wrong code_ and a _stale/missing
  factor_ looked identical to the user. It now surfaces the server's actual
  message (`"Invalid code"`, `"No TOTP factor found"`, `"MFA verification
locked"`, etc.).
- The QR code was rendered at 160x160px, too small to reliably scan on most
  phone cameras at normal arm's length. Bumped to 280x280px (`max-width: 100%`
  so it still fits narrow viewports).

This was not a Supabase configuration problem - Authentication > Multi-Factor
Authentication > TOTP was already `Enabled` with a factor limit of 10, which
is unrelated to this bug (the app was creating and immediately invalidating
factors, well under any limit).

## Fourth Round: The Cleanup Couldn't See What It Was Cleaning Up

Even for a genuinely single-instance case (a non-mandatory role, no popup
involved, no second panel), Enroll could still permanently 400 with the same
"already exists" conflict, and the auto-retry never recovered - "Start over"
included.

Root cause: every helper in `supabaseAuth.api.ts` read `data.totp` from
`listFactors()`. `AuthMFAListFactorsResponse`'s type declares the per-type
property (`.totp`) as **verified-only factors**; the actual "everything for
this user, verified and unverified, across every factor type" list is a
_separate_ property, `data.all`. The original controller code (before this
fix) happened to still find unverified factors inside `.totp` in practice
(hence why `find(f => f.status === 'unverified')` there needed a type-cast to
compile at all - the compiler didn't think it belonged there either), but that
behavior isn't something to build new logic on. Reading `.totp` also silently
excludes any non-`totp` factor type from cleanup, and gave no way to
distinguish "genuinely nothing to clean up" from "reading the wrong list."

Fixed: `supabaseAuth.api.ts`'s `enrollTotpFactor`, `getTotpEnrollmentStatus`,
and `unenrollAllTotpFactors` all now read from `data.all` and filter by
`factor_type === 'totp'` explicitly - the one property the SDK actually
documents as complete. `enrollTotpFactor` also gained a third, escalated retry
tier: if the conflict survives the existing unverified-only cleanup and one
retry, it now also attempts to remove a stale _verified_ factor before trying
one final time. That succeeds only if the caller's session is already aal2
(Supabase's own rule); if not, the caller gets back the same honest "already
exists" error rather than a silent infinite loop, since there is no safe way
for the app to remove a verified second-factor without the user proving they
still hold the first one.

**If you're already stuck behind this** (an account that hit the bug before
this round's fix shipped, or hits the aal2 wall above), the client's "Start
over" / Settings "Disable MFA" won't help until the account's stale factor is
cleared once, manually, in the Supabase SQL Editor:

```sql
-- Inspect what's actually there for the stuck account (from the failing
-- request's URL/console error, or Table Editor > staff_profiles/customer_profiles):
select id, friendly_name, factor_type, status, created_at
from auth.mfa_factors
where user_id = '<the stuck user's id>';

-- Once confirmed, clear it (safe for a dev/test account; do not run this
-- against a real user's factor without confirming with them first):
delete from auth.mfa_factors
where user_id = '<the stuck user's id>';
```

After running the `delete`, the next Enroll attempt for that account starts
completely clean.

## Fifth Round: Verify Had the Exact Same `.totp` Bug, Confirmed Live

The Fourth Round fix covered `enrollTotpFactor`, `getTotpEnrollmentStatus`, and
`unenrollAllTotpFactors` - deliberately not the verify controllers, on the
reasoning that verify "wasn't reported as broken on its own." It clearly was:
manual testing produced a clean repro where Enroll visibly succeeded (QR and
manual key rendered), a real code was entered, and Verify still 400'd with
`"No TOTP factor found"`.

`mfaVerifyController` / `customerMfaVerifyController` were the one remaining
place still reading `factorsData.totp.find(...)` directly instead of going
through a shared helper. Before changing anything, we confirmed this live
against the actual database instead of guessing again:

```sql
select id, factor_type, status, created_at, updated_at
from auth.mfa_factors
where user_id = '<the customer's id>';
```

Result: exactly one row, `factor_type = 'totp'`, `status = 'unverified'` -
i.e. the factor from the Enroll call that had just succeeded a few seconds
earlier. Since `.totp` is verified-only (Fourth Round), it was invisible to
`factorsData.totp.find((f) => f.status === 'unverified')`, so `totpFactor` was
always `undefined` for a first-time verify attempt straight after enrolling -
the exact symptom in the very first bug report this whole fix was filed
against, not just a residual edge case from the popup/StrictMode work.

Fixed: added `findTotpFactorForVerify(userClient)` to `supabaseAuth.api.ts`
(prefers a verified factor, falls back to the most recent unverified one, both
read from `.all` filtered to `factor_type === 'totp'`) and switched both
verify controllers to call it instead of inlining their own `.totp`-based
lookup. This is now the fourth and last function in this file that touches
`listFactors()` - all four agree on reading `.all`.

## Sixth Round: MFA Was Never Actually Checked at Login

After successfully enrolling a customer account end-to-end, manual testing
signed out and back in with that same account - and it went straight to
`/portal` with no TOTP prompt at all, as if MFA weren't enabled.

This wasn't a stale-session or "logged back in too fast" issue (there was also
no sign-out button anywhere yet to test that properly, so this round adds
one). It was a real gap: everything shipped so far only ever _enrolled_ an
optional-MFA account (customers, and staff roles below Admin/Superadmin). No
code path ever _challenged_ that account again on a later login. Mandatory
roles were fine, because `StaffAuthGuard`/`StaffLoginForm` gate on
`requiresMfa(role)`, which is role-based and has nothing to do with whether a
lower-priv/customer account chose to turn MFA on for itself.

Concretely:

- `CustomerLoginForm` never checked MFA status at all after login - there was
  no customer-side challenge page, route, or redirect to build on in the first
  place, unlike staff which already had `/staff/mfa/verify` from the mandatory
  flow.
- `StaffLoginForm`'s post-login branch only redirected to a challenge/enroll
  step when `isMfaRole(role)` was true. A Cashier or Groomer who enrolled
  through Settings would still skip straight to `/staff` on every subsequent
  login, because their role alone never required it.
- `StaffAuthGuard`'s `needsAal2` had the identical role-only gate, so even a
  direct/restored session for that same voluntarily-enrolled Cashier never
  got redirected to challenge either.

Fixed:

- Added a customer-side challenge stack that didn't exist before: a new
  shared `TotpChallengeForm` component (code-entry only, no QR/enroll - for an
  _already-enrolled_ factor), a `CustomerMfaChallengePage` at the new
  `/portal/mfa/verify` route, and `customerMfaPending` sessionStorage flag
  handling in `CustomerLoginForm`, mirroring the existing `staffMfaPending`
  pattern.
- `CustomerAuthGuard` now fetches MFA status (same pattern as
  `StaffAuthGuard`) and redirects to `/portal/mfa/verify` whenever
  `mfa_enrolled && aal !== 'aal2'` - customers never get the mandatory popup
  (that's still Admin/Superadmin-only, staff-only), but once they've opted in,
  every login requires the code, exactly like Settings' "MFA is enabled"
  status implies.
- `StaffLoginForm`'s redirect condition is now `isMfaRole(role) ||
mfaEnrolled` instead of `isMfaRole(role)` alone - any staff member with a
  verified factor gets sent to `/staff/mfa/verify`, not just Admin/Superadmin.
- `StaffAuthGuard`'s `needsAal2` is now `(requiresMfa(role) || mfaEnrolled ===
true) && aal !== 'aal2'` - same extension, so a direct/restored session for
  a voluntarily-enrolled lower-priv account is caught too. The mandatory
  popup's own condition (`mfaEnrolled === false`) is unaffected by this
  change, since the added OR-clause only ever fires when `mfaEnrolled` is
  `true`.
- Added a **Sign out** button to `SettingsPage` (staff and customer both,
  under a new "Account" section) - there wasn't one anywhere in the app
  before this round, which made "did I actually get a fresh aal1 session"
  impossible to test cleanly from the UI. Also clears both
  `staffMfaPending`/`customerMfaPending` flags on sign-out for hygiene.

## What Changed (cumulative)

**Server:**

- `server/src/shared/auth/api/supabaseAuth.api.ts`:
  - All MFA helpers read from `listFactors()`'s `data.all` (documented as the
    complete verified+unverified, all-factor-types list) filtered by
    `factor_type === 'totp'`, instead of the per-type `data.totp` property -
    see Fourth and Fifth Rounds above.
  - `enrollTotpFactor(userClient)` - unenrolls the caller's prior _unverified_
    TOTP factors before creating a new one. If Supabase still rejects the
    `enroll()` call with an "already exists" conflict, it cleans up once more
    and retries; if the conflict survives that too, it makes one final
    escalated attempt that also tries to remove a stale _verified_ factor
    (succeeds only if the caller is already aal2) before giving up and
    returning the error as-is.
  - `getTotpEnrollmentStatus(userClient)` - whether the caller has a _verified_
    TOTP factor.
  - `unenrollAllTotpFactors(userClient)` (new) - removes every TOTP factor the
    caller has, verified or not. Supabase itself enforces that removing a
    _verified_ factor requires an aal2 session; per-factor failures are
    returned in the result rather than thrown, so the caller can report
    exactly which factor(s) couldn't be removed instead of a bare 500.
  - `findTotpFactorForVerify(userClient)` (new) - the factor a Verify call
    should challenge: the verified one if present, otherwise the most recent
    unverified one. Used by both verify controllers instead of each inlining
    its own `.totp`-based lookup - see Fifth Round.
  - All four are shared between the staff and customer controllers.
- `staffAuth.controller.ts` / `customerAuth.controller.ts`:
  - `mfaVerifyController` / `customerMfaVerifyController` now call
    `findTotpFactorForVerify` instead of inlining `factorsData.totp.find(...)`
    - this is the fix for the original "TOTP factor not found" bug report.
  - `mfaEnrollController` / `customerMfaEnrollController` go through
    `enrollTotpFactor` instead of calling `userClient.auth.mfa.enroll()`
    directly.
  - Added `mfaStatusController` / `customerMfaStatusController`.
  - Added `mfaUnenrollController` / `customerMfaUnenrollController` (new) -
    returns `{ removed: string[], failed: { factorId, message }[] }`; 400s
    only if _nothing_ could be removed.
- New routes: `GET /auth/staff/mfa/status`, `GET /auth/customers/mfa/status`
  (read-only, no side effects), `POST /auth/staff/mfa/unenroll`,
  `POST /auth/customers/mfa/unenroll` (new). All four are `jwtMiddleware`-gated.
- `requireMfa.middleware.ts` - mandatory-MFA role list fixed to `Admin`/`Superadmin`
  (was `Admin`/`Supervisor`). Also fixed a role-resolution bug: `req.user.role`
  is decoded straight from the JWT, where `role` is the Postgres role claim
  (`"authenticated"`) - not the `staff_role` enum - so it was short-circuiting
  the `staff_profiles` lookup and silently never enforcing MFA for anyone. It
  now only trusts `req.user.role` when it's actually one of the eight
  `staff_role` enum values, otherwise resolves from `staff_profiles`.
- `staffLoginController` / `customerLoginController` were **not** changed - see
  "Known Gap" below for why the login response itself still doesn't carry
  role/enrollment fields.

**Client:**

- `client/src/shared/auth/mfa.types.ts`, `client/src/shared/auth/mfa.validator.ts`,
  `client/src/shared/api/mfa.api.ts` - role-parameterized (`'staff' | 'customer'`)
  MFA client, mirroring the existing `preferences.api.ts` pattern from issue #17.
  Now includes `unenrollMfa(role, accessToken)` alongside `getMfaStatus`/
  `enrollMfa`/`verifyMfa`.
- `client/src/shared/components/TotpEnrollPanel/`:
  - Guards its enroll-on-mount effect with a `useRef` so enrollment is only
    ever kicked off once per real mount, immune to StrictMode's dev-mode
    double-invoke (this is the client-side half of the race fix; the
    server-side retry-on-conflict is the other half, covering non-StrictMode
    callers like Postman or a second browser tab).
  - Now displays the raw base32 `secret` from the enroll response as a
    copyable manual-entry key (`totp.secret`), alongside the QR code, labeled
    "Can't scan? Enter this key manually" - so scanning a camera is no longer
    the only way to complete setup.
  - On an enroll error (e.g. the conflict above, or a stale factor left over
    from before this fix shipped), shows a "Start over" button that calls the
    new unenroll endpoint and retries enrollment, instead of leaving the user
    stuck with no recovery path.
- `client/src/shared/components/MfaSetupModal/` - blocking modal (styled after
  the existing `SessionExpiryModal`) that wraps `TotpEnrollPanel` for the
  mandatory Admin/Superadmin flow.
- `client/src/shared/components/TotpChallengeForm/` (new) - code-entry-only
  counterpart to `TotpEnrollPanel`, for verifying an _already-enrolled_
  factor at login time (no QR/secret, no `enrollMfa()` call).
- `client/src/features/auth/customer/pages/CustomerMfaChallengePage/` (new) +
  route `/portal/mfa/verify` (standalone, outside `CustomerAuthGuard`, mirrors
  `/staff/mfa/verify`) - wraps `TotpChallengeForm` with role `'customer'`.
- `StaffLoginForm.tsx` - `isMfaRole` fixed to `Admin`/`Superadmin`. Post-login
  branching calls the new `GET /staff/mfa/status` immediately after
  `applySession` instead of reading the never-populated login-response fields.
  Redirect condition is now `isMfaRole(role) || mfaEnrolled` (Sixth Round) so
  any account with a verified factor is challenged, not just mandatory roles.
- `CustomerLoginForm.tsx` (Sixth Round) - after `applySession`, calls the new
  `GET /customers/mfa/status`; if enrolled, sets `customerMfaPending` and
  redirects to `/portal/mfa/verify`, mirroring the staff flow that didn't
  previously have a customer-side equivalent at all.
- `StaffAuthGuard.tsx` - `requiresMfa` fixed to `Admin`/`Superadmin`. Fetches
  `/staff/mfa/status` for any signed-in staff session; for Admin/Superadmin who
  are **not yet enrolled**, renders `MfaSetupModal` as a blocking overlay over
  the current `/staff/*` page instead of redirecting to `/staff/mfa/verify`
  (which would 400 - there's no factor to challenge yet). This is what makes
  the popup "always show up as long as MFA isn't enabled" - it re-appears on
  every guarded page load until enrollment completes, not just once right
  after login. `needsAal2` extended in the Sixth Round to also cover
  voluntarily-enrolled non-mandatory roles (`mfaEnrolled === true`), not just
  `requiresMfa(role)`.
- `CustomerAuthGuard.tsx` (Sixth Round, previously did nothing but check
  `session && user`) - now fetches `/customers/mfa/status` and redirects to
  `/portal/mfa/verify` whenever `mfa_enrolled && aal !== 'aal2'`, mirroring
  `StaffAuthGuard`'s pattern (minus the mandatory-popup/role-timeout pieces,
  which don't apply to customers).
- `client/src/pages/SettingsPage/SettingsPage.tsx`:
  - `role: 'staff' | 'customer'` prop; fetches MFA status and shows an
    "enabled" confirmation, a read-only "required, not yet set up" notice for
    Admin/Superadmin, or the optional enroll panel for everyone else.
  - **Does not render its own `TotpEnrollPanel` for Admin/Superadmin** even
    while unenrolled - `MfaSetupModal` (rendered by `StaffAuthGuard` on every
    `/staff/*` page) is the single, exclusive owner of enrollment for those
    two roles. An earlier "defensive" version of this page rendered a second
    panel here too, which raced the modal's panel and is what caused the
    QR/manual-key-mismatch bug described in the Third Round above - see that
    section before reintroducing anything like it.
  - Added a **Disable MFA** button (new) for enrolled, non-mandatory
    roles/customers, calling the new unenroll endpoint and refreshing status
    on success. Not shown for Admin/Superadmin - policy requires them to keep
    MFA on, so there is deliberately no self-service way to turn it off from
    Settings for those two roles.
  - Added a **Sign out** button (new, Sixth Round) under a new "Account"
    section, calling `useAuth().signOut()` and clearing both
    `staffMfaPending`/`customerMfaPending` sessionStorage flags before
    redirecting to the role-appropriate login page. This is the only sign-out
    entry point in the app so far.
- Routes: `GET /staff/settings` (behind `StaffAuthGuard`), `GET
/portal/settings` (behind `CustomerAuthGuard`), and `GET /portal/mfa/verify`
  (standalone, Sixth Round), rendering `SettingsPage`/`CustomerMfaChallengePage`
  respectively. The `/staff` and `/portal` placeholder pages got a plain
  `Settings` link to reach them.

## Known Gap / Needs Follow-up

- **Login response fields left unpopulated on purpose.** `StaffLoginResponse`
  still declares unused `requires_mfa`/`mfa_enrolled`/`role` fields.
  `staffLoginController` has tight, pre-existing unit tests asserting an exact
  JSON body; populating those fields there would mean an extra
  `staff_profiles`/`listFactors` round trip on every login and touching that
  test's exact-match assertions for no behavioral gain, since `/staff/mfa/status`
  is strictly more authoritative (JWT `role` claims can't carry it reliably,
  per the bug fixed above) and is already called immediately after login.
- **`ROLE_TIMEOUT_MS` in `StaffAuthGuard.tsx` and the `getStaffRole(user)` helper
  it uses were not touched**, even though they have the same "JWT `role` claim is
  `'authenticated'`, not the `staff_role` enum" problem fixed above in
  `requireMfa.middleware.ts` - meaning role-tiered session timeouts (#13) may
  currently always fall back to the same threshold in production. Pre-existing,
  separate bug outside this fix's scope; flagging it since it was discovered
  along the way.
- **Disable MFA requires an aal2 session**, by Supabase's own design (you must
  prove you still hold the current factor before removing it). A lower-priv
  staff member or customer who enrolled, then logged back in without ever being
  challenged (since MFA is optional for them, login doesn't force a challenge
  step), will see the Settings "Disable MFA" button fail with a message
  surfaced from Supabase rather than silently succeed. This is intentional
  security behavior, not a bug, but it means "Disable MFA" only reliably works
  in the same session as the most recent successful Verify.
- **No nav shell.** `Navbar.tsx`/`HomePage.tsx` are still empty placeholders
  (issue #17's Known Gap). Settings is reachable only via the plain link added
  to the `/staff` and `/portal` placeholder pages.
- **Postman TOTP codes are still entered by hand.** Consistent with every other
  MFA collection in this project, there is no pre-request script deriving a
  code from the enrollment secret - the collection's Enroll requests print a
  reminder to scan the QR (or manually enter `totp.secret`, matching the new
  client-side manual-key option) and fill in `totp_code` before running the
  paired Verify request.
- **Unrelated, pre-existing console error observed during manual testing:**
  `GET .../staff_profiles?select=theme_preference&id=eq...` and the equivalent
  `customer_profiles` query both return `406` from `getThemePreference()` in
  `client/src/shared/api/preferences.api.ts` (issue #17's theme feature). Seen
  across multiple different staff accounts during this round of testing, so it
  looks like a systemic RLS or missing-column issue on the live project rather
  than one bad row - worth its own investigation. Not touched by this fix;
  `.single()` returns 406 whenever the row lookup doesn't return exactly one
  row (RLS silently filtering the row out is the most likely cause, but the
  `20260702018_shared_add_theme_preference_columns.sql` migration should also
  be confirmed as actually applied to this project, not just present in the
  repo).

## Automated Verification

From `server/`, run:

```powershell
npm.cmd run typecheck
npm.cmd run test
npm.cmd run lint
```

Expected result:

- Typecheck exits cleanly.
- All tests pass (126 tests as of this fix, including
  `enrollTotpFactor`'s multi-tier retry-on-conflict path (unverified cleanup,
  retry, then escalated verified cleanup), `unenrollAllTotpFactors`,
  `findTotpFactorForVerify` (including the exact just-enrolled-unverified
  regression case), both new unenroll controllers, the status endpoints, and
  the updated `requireMfa` role-policy tests).
- Lint exits with 0 errors (3 pre-existing `no-console` warnings in
  `staffAuth.controller.ts`/`customerAuth.controller.ts` are expected,
  unchanged from prior work).

From `client/`, run:

```powershell
npm.cmd run test
npx tsc -b
npm.cmd run lint
```

Expected result:

- All tests pass (60 tests as of this fix, including `TotpEnrollPanel`'s
  StrictMode-double-invoke guard, manual-key display, and "Start over" retry;
  `SettingsPage`'s Disable MFA and Sign out buttons; `TotpChallengeForm`;
  `CustomerLoginForm`'s and `CustomerAuthGuard`'s new MFA-enforcement tests).
- `tsc -b` exits with code 0.
- Lint exits with 0 errors/warnings.

## Supabase Verification

Use the SQL helper in:

`testing/docs/sprints/sprint1/custom/01-fix-mfa/supabase/fix-mfa.sql`

1. Open the Supabase dashboard and select the Golden Fur project.
2. In the left sidebar, click **SQL Editor** > **New query**.
3. Complete the Postman flow below first (specifically, run **Staff Admin - MFA
   Enroll** twice in a row before verifying, to exercise the cleanup path, and
   run the Unenroll requests near the end of each role's section).
4. In the Table Editor, open `staff_profiles`, find your test Admin/Superadmin
   row, and copy its `id`.
5. Open `fix-mfa.sql`, replace both `<user-id>` placeholders with that id, and
   run each `select` one at a time.
6. Confirm the first query's `status` column shows **at most one** `unverified`
   row - never two or more, even though you ran Enroll twice.
7. Confirm the second query's grouped counts agree (`unverified` count is 0 or 1).
8. After running an Unenroll request/button for this user, re-run the first
   query and confirm it now returns **zero rows**.
9. Run the fourth query and confirm it lists all eight `staff_role` values,
   including both `Admin` and `Superadmin`.

## Postman Verification

Use the Postman collection in:

`testing/docs/sprints/sprint1/custom/01-fix-mfa/postman/fix-mfa.postman_collection.json`

### Setup

1. Open Postman and click **Import**.
2. Choose `fix-mfa.postman_collection.json`.
3. Open the imported collection named **Fix MFA - Enroll, Verify, and Login
   Enforcement**.
4. Open the **Variables** tab and set:
   - `base_url` - usually `http://localhost:3000`.
   - `admin_identifier` / `admin_password` - a staff account with role `Admin`
     or `Superadmin` (username or email both work for `identifier`).
   - `lower_priv_identifier` / `lower_priv_password` - a staff account with any
     other role (e.g. `Cashier`, `Groomer`).
   - `customer_email` / `customer_password` - a customer account.
   - `fresh_identifier` / `fresh_password` - a second Admin/Superadmin account
     that has **never** run Enroll, used only for the regression check at the end.
   - Leave `totp_code` and the `*_access_token` variables blank.
5. Install an authenticator app (Google Authenticator, Authy, 1Password, etc.)
   - you'll need it to generate real 6-digit codes from the Enroll responses.
6. Click **Save**.

### AC: Admin/Superadmin mandatory MFA end-to-end

1. Run **Staff Admin - Login**. Confirm `200` and that `admin_access_token` is filled.
2. Run **Staff Admin - MFA Status (before enroll)**. Confirm `200`, `role` is
   `Admin` or `Superadmin`, and `mfa_enrolled` is `false`.
3. Run **Staff Admin - MFA Enroll**. Confirm `200`. Open the Postman Console
   to see the reminder log. Either scan the QR/URI, or manually type
   `body.totp.secret` into your authenticator app's "enter key manually" option.
4. Run **Staff Admin - MFA Enroll (repeat, verifies race/conflict cleanup)**.
   Confirm `200`. This intentionally simulates re-running Enroll before
   finishing - the old bug's most common trigger. Use **this new** secret/QR
   instead (the first one is no longer valid - confirmed via Supabase
   Verification above, only one unverified factor exists).
5. Set `totp_code` to the current 6-digit code, then immediately run
   **Staff Admin - MFA Verify**. Confirm `200` and that `admin_access_token`
   was refreshed.
6. Run **Staff Admin - MFA Status (after enroll)**. Confirm `mfa_enrolled` is now `true`.

### AC: Lower-privilege staff role - optional Settings enrollment and unenroll

1. Run **Staff Lower-Priv - Login**. Confirm `200`.
2. Run **Staff Lower-Priv - MFA Status (before enroll, optional role)**.
   Confirm `200` and that `role` is **not** `Admin`/`Superadmin`.
3. Run **Staff Lower-Priv - MFA Enroll (Settings flow)**. Confirm `200`.
4. Set `totp_code` and run **Staff Lower-Priv - MFA Verify**. Confirm `200`.
5. Run **Staff Lower-Priv - MFA Unenroll (Disable MFA)**. Confirm `200` with a
   non-empty `removed` array and an empty `failed` array (this works because
   step 4 just refreshed the session to aal2).
6. Run **Staff Lower-Priv - MFA Status (after unenroll)**. Confirm
   `mfa_enrolled` is `false` again.

### AC: Customer - optional Settings enrollment and unenroll

1. Run **Customer - Login**. Confirm `200`.
2. Run **Customer - MFA Status (before enroll)**. Confirm `200` and `mfa_enrolled: false`.
3. Run **Customer - MFA Enroll (Settings flow)**. Confirm `200`.
4. Set `totp_code` and run **Customer - MFA Verify**. Confirm `200`.
5. Run **Customer - MFA Status (after enroll)**. Confirm `mfa_enrolled: true`.
6. Run **Customer - MFA Unenroll (Disable MFA)**. Confirm `200` with a
   non-empty `removed` array.

### Regression check - reproduces the original bug report on purpose

1. Run **Regression - Fresh Admin Login** (the never-enrolled account).
2. Run **Regression - Verify Without Enrolling First (expected 400)**. Confirm
   `400` with `error: "No TOTP factor found"`. This is _supposed_ to fail this
   way for a never-enrolled account - that's what the mandatory setup popup
   and the Settings enrollment flow now exist to prevent. If you see this same
   error for an account that already completed Enroll+Verify, use the
   corresponding Unenroll request as a self-service recovery and re-enroll.

## Manual Client Verification

1. From `client/`, run `npm.cmd run dev` and open the printed local URL.
2. Sign in at `/staff/login` with an Admin or Superadmin account that has not
   enrolled MFA. Confirm you land on `/staff/mfa/enroll` (the existing
   full-page flow) and complete it there, OR skip that and confirm the modal
   path below instead.
3. To see the **popup** specifically: sign in as that same not-yet-enrolled
   Admin/Superadmin, then once on `/staff`, refresh the page (or open `/staff`
   in a new tab reusing the same browser session). Confirm a modal titled
   "Set up multi-factor authentication" appears over the `/staff` page, with a
   noticeably large (280x280px) QR code, a manual-entry key labeled "Can't
   scan? Enter this key manually" with a working Copy button, and a 6-digit
   code field - and that it does not redirect you away from `/staff` first.
4. Open the browser DevTools Network tab, filter on `mfa/enroll`, then reload
   the page. Confirm exactly **one** POST to `/auth/staff/mfa/enroll` fires -
   not two (StrictMode double-invoke, fixed in round two) and not two from a
   different cause (a second `TotpEnrollPanel` instance racing the modal's,
   fixed in round three - this specifically regresses if `SettingsPage` is
   changed to render its own enroll panel for Admin/Superadmin again while
   this modal is also active on `/staff/settings`).
5. Complete the code shown for the QR/key from this same load - do not
   navigate away or open another tab mid-setup, since that used to invalidate
   the factor before this fix. Confirm the modal closes and you remain on `/staff`.
6. Refresh `/staff` again. Confirm the modal does **not** reappear.
7. Sign in as a non-Admin/Superadmin staff role (e.g. Groomer). Confirm no
   modal ever appears, on any `/staff/*` page.
8. Navigate to `/staff/settings` as an unenrolled Admin/Superadmin. Confirm the
   mandatory popup appears (as in step 3) **and** the page body underneath only
   shows the read-only "required, not yet set up" text - no second QR/code form
   inline on the page itself. Complete the code from the popup; confirm the
   page then flips to "MFA is enabled on your account." with no Disable button.
9. For a Groomer account (optional role), navigate to `/staff/settings`.
   Confirm no popup appears anywhere, and the QR/manual-key/code-entry panel
   renders inline on the page itself. Complete enrollment, then
   confirm a **Disable MFA** button appears. Click it and confirm the section
   reverts to the optional "not enrolled" state.
10. Sign in as a customer at `/login`, navigate to `/portal/settings`. Confirm
    the same optional MFA section (including Disable MFA once enrolled)
    appears, and that customers never see a mandatory popup anywhere.
11. To exercise the "Start over" recovery path directly: on `/staff/settings`
    or the popup, start enrolling, then in a second tab (same account, same
    browser) also start enrolling before finishing the first. Confirm the
    first tab's enroll panel eventually shows an error and a "Start over"
    button; click it and confirm a fresh QR/key appears without needing to
    reload the page.
12. **Sixth Round - re-login enforcement (this is the actual fix that
    matters most):** using the Groomer account enrolled in step 9, go to
    `/staff/settings` and click **Sign out** (new, under the "Account"
    section). Confirm you land on `/staff/login`.
13. Sign back in as that same Groomer account. Confirm you are redirected to
    `/staff/mfa/verify` and prompted for a code - **not** sent straight to
    `/staff`. Enter the current code from your authenticator app and confirm
    you land on `/staff` afterward.
14. Repeat steps 12-13 for the customer account enrolled in step 10: sign out
    from `/portal/settings`, sign back in at `/login`, confirm you're
    redirected to `/portal/mfa/verify` (not straight to `/portal`), and that
    entering the correct code lands you on `/portal`.
15. Sign in as a staff/customer account that was **never** enrolled. Confirm
    login goes straight to `/staff` or `/portal` with no challenge - MFA
    enforcement should only ever apply to accounts that actually have it on.
16. From `/staff/settings` or `/portal/settings`, click **Sign out** again and
    confirm you land back on the correct login page (`/staff/login` for
    staff, `/login` for customers) each time.

## Notes

- The mandatory-MFA role list is intentionally `Admin` + `Superadmin` only, per
  the request this fixes - `Supervisor` and all roles below it are optional,
  Settings-only, matching how `ROLE_TIMEOUT_MS` in `StaffAuthGuard.tsx` already
  treats `Supervisor` as a step down from `Admin`/`Superadmin`.
- `TotpEnrollPanel` is the one place the QR-code/manual-key/code-entry UI lives
  now; the mandatory popup, the staff Settings section, and the customer
  Settings section all render the same component with a different `role` prop
  rather than three near-identical copies.
- Do not paste Supabase service-role, anon, or project API keys into any Postman
  variable - only the short-lived `access_token` values produced by the Login
  requests belong in this collection, consistent with issue #16's note.

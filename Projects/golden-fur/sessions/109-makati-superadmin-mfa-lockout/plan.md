---
title: Unstick makati.superadmin1's dead-secret MFA lockout
date: 2026-09-16
tags: [session-plan, golden-fur]
project: golden-fur
session: 109-makati-superadmin-mfa-lockout
branch: none (data-only fix, no code change)
---

# 109 — Unstick makati.superadmin1's dead-secret MFA lockout

## What you asked for

> fix makati.superadmin1@goldenfur.com login > MFA failing even if the TOTP
> is right — teammates said southwoods.superadmin1@goldenfur.com works just
> right, and the other TOTP as well, tehre's just somethingw rong with
> superadmin from makati

## What this part of the app does today

**MFA** (Multi-Factor Authentication) means logging in needs two things:
your password, and a rotating 6-digit code from an authenticator app (like
Google Authenticator) on your phone. **TOTP** (Time-based One-Time
Password) is the specific kind of code used: a secret, set up once by
scanning a QR code, that both your phone and the server use to compute the
same 6-digit code every 30 seconds. This app requires MFA for the
Admin, Supervisor, and Superadmin staff roles, so `makati.superadmin1` and
`southwoods.superadmin1` both have to pass a TOTP check on every login at
`/staff/mfa/verify`.

To stop someone from guessing codes forever, there's a **lockout**: the
`mfa_lockouts` table (`server/src/shared/services/mfaLockout/mfaLockout.service.ts`)
counts wrong codes per account. After 5 wrong codes in a row, that account
gets a `locked_until` timestamp 15 minutes in the future and every attempt
made before that timestamp is rejected immediately — the server never even
asks Supabase to check the code, so it doesn't matter whether the code is
right or wrong while locked.

Crucially, **only a successful code check clears the counter to 0.** If
every attempt someone makes is genuinely wrong (not just mistyped, but
wrong because the phone's authenticator entry doesn't match what the
server has on file), each attempt after the first 5 keeps landing while
still "locked," and every one of those failures pushes `locked_until`
another 15 minutes into the future. From the account owner's side this
looks like a lockout that never goes away — they enter what they're
certain is the right code, and it's rejected every time.

There was already one bug like this, fixed one session ago:
**Session 107** (`Projects/golden-fur/sessions/107-mfa-enroll-fix/plan.md`,
merged as commit `99ce6f4`, PR #186, 2026-09-15). The setup page
`/staff/mfa/enroll` used to have no guard against being revisited after
setup was already done (bookmark, back button, stale link). Revisiting it
could silently delete the working, already-scanned factor and issue a
**brand new secret with no error shown** — the phone's authenticator app
kept showing the old, now-dead entry, and every code from that entry would
be "correct-looking but wrong," tripping the same self-renewing lockout
described above. The fix (both a server-side and a client-side change)
stops this from happening **from now on**, but does nothing to repair an
account that was already caught by it **before** the fix merged.

## What's actually wrong with `makati.superadmin1`

I checked the live dev Supabase project (`hikgijuipymfghfuyrjv`, confirmed
against `server/.env` — this is the dev project, not production) directly
with the service-role key already in that file:

- `makati.superadmin1`'s TOTP factor is `status: "verified"`, `created_at:
2026-09-13T03:10:27Z` — **two days before** the session-107 fix merged
  (2026-09-15).
- `southwoods.superadmin1`'s TOTP factor is `status: "verified"`,
  `created_at: 2026-09-16T01:42:10Z` — set up fresh today, **after** the
  fix was already in place.
- `makati.superadmin1`'s `mfa_lockouts` row: `failed_attempts: 7`,
  `locked_until: 2026-09-16T07:12:21Z`. (Checked at 2026-09-16T07:02:43Z —
  still actively locked at the time of this investigation.)
- `southwoods.superadmin1`'s `mfa_lockouts` row: `failed_attempts: 0`,
  `locked_until: null`.

This matches the session-107 bug exactly, just on an account that was
already broken before that fix landed: `makati.superadmin1`'s authenticator
app almost certainly still holds the *original* secret from 2026-09-13,
while Supabase has since been given a *different* one (silently, via the
old enroll bug). Every code the account owner enters is genuinely correct
for the entry on their phone and genuinely wrong for what Supabase actually
checks against — so it keeps failing, keeps re-locking itself for another
15 minutes each time, and will keep doing this forever on its own.

There is also no way for the account owner to fix this themselves: the
"start over" (unenroll) action can only remove a factor from a session that
has *already* passed MFA (Supabase calls this **aal2**), and an account
that can never pass the check can never reach aal2. This needs a one-time
fix from the server side, using the service-role key.

## Why this isn't a seeding problem or branch-specific code

Two follow-up questions worth closing explicitly, since they're the
natural next guess:

**"Is `makati.superadmin1` seeded differently from the other accounts?"**
No. `supabase/seeds/m01-staff-auth/m01-staff-auth.seed.ts`'s `seedStaff`
(lines 136–203) creates every staff account — both branches, all 8 roles,
both account numbers — through **one identical loop**: for each branch
row already in the `branches` table, for each entry in `ROLE_SEEDS`, for
`n` from 1 to `ACCOUNTS_PER_ROLE_PER_BRANCH`, build
`${branchSlug}.${slug}${n}@goldenfur.com`, call
`supabase.auth.admin.createUser(...)`, then insert one `staff_profiles`
row. There is no per-branch or per-account special case anywhere in that
function, and no MFA/TOTP enrollment happens at seed time at all for
*any* account — the seed only creates the login (email + password) and the
`staff_profiles` row. MFA gets enrolled later, by whoever first logs into
that account through the app and scans a QR code. So `makati.superadmin1`
is already "seeded just like other accounts"; re-running or fixing the
seed wouldn't touch this bug, because the seed never touches MFA factors.

**"Is there code that specifically touches `makati.superadmin1`?"** No.
A dedicated Explore pass over the whole repo searched every MFA/TOTP file
(`supabaseAuth.api.ts`, `staffAuth.controller.ts`, `requireMfa.middleware.ts`,
`StaffAuthGuard.tsx`, `mfaLockout.service.ts`) plus a case-insensitive
repo-wide search for "makati" and "southwoods" outside migrations. Every
MFA gating decision is keyed only on **role** (`MANDATORY_MFA_ROLES` in
`requireMfa.middleware.ts`) and **aal level** — never on branch, email
domain, or email prefix. The only "makati"/"southwoods" hits outside
seeds and this branch's own `branches` row are test-fixture strings (e.g.
`'branch-makati'` used as an arbitrary id in
`staffAuth.middleware.unit.spec.ts`) and the `is_vet_branch` flag, which
only affects veterinary booking eligibility, never auth. The divergence
between `makati.superadmin1` and `southwoods.superadmin1` is 100%
**account state that happened to be written to the database at a specific
moment in time** (this account's factor got silently replaced during a
revisit-the-enroll-page moment on 2026-09-13, before PR #186 fixed that
path) — not a difference in what code runs for the two accounts.

## What we're going to change

**Nothing in the app's code.** The session-107 fix already stops this from
happening to any other account going forward, and southwoods.superadmin1
proves it: it was set up after the fix and works fine. This is purely a
one-time repair of `makati.superadmin1`'s existing, already-corrupted
account state in the dev database — two calls with the service-role key,
then a normal re-enrollment by the account owner.

### Step 1 — confirm the target IDs (read-only, already done once)

```
GET {SUPABASE_URL}/auth/v1/admin/users/{makati_superadmin1_user_id}/factors
Headers: apikey / Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY from server/.env>
```

- User id: `b0934b4f-79e3-4f57-a115-4d86879d5e88`
- Current (dead) TOTP factor id: `bce89fb3-5f72-435c-9978-6d54a0223d94`

Re-run this first if any time has passed, in case the account owner has
already tried "start over" or another factor exists — don't delete a
factor id without re-checking it's still this one.

### Step 2 — remove the dead factor

```
DELETE {SUPABASE_URL}/auth/v1/admin/users/b0934b4f-79e3-4f57-a115-4d86879d5e88/factors/bce89fb3-5f72-435c-9978-6d54a0223d94
Headers: apikey / Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
```

This is the Supabase **admin** API (service-role key, not the user's own
session), so it does not require aal2 — this is exactly why it has to be
done this way instead of through the app.

### Step 3 — reset the lockout counter

```
PATCH {SUPABASE_URL}/rest/v1/mfa_lockouts?user_id=eq.b0934b4f-79e3-4f57-a115-4d86879d5e88
Headers: apikey / Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY> / Content-Type: application/json
Body: {"failed_attempts": 0, "locked_until": null}
```

Without this step, even a perfectly successful re-enrollment in Step 4
would still show as "locked" for anyone who checks status before
`locked_until` naturally passes.

### Step 4 — have the account owner re-enroll

1. Delete the old "Golden Fur" entry for this account from their
   authenticator app (it's dead — keeping it just invites confusion).
2. Log in at the normal staff login page with
   `makati.superadmin1@goldenfur.com` and its password.
3. Because the factor no longer exists, `getMfaStatus` now reports
   `mfa_enrolled: false`, so the app routes to `/staff/mfa/enroll` instead
   of `/staff/mfa/verify`.
4. Scan the **new** QR code shown there and enter the 6-digit code it
   produces to confirm setup, same as any new account.

### Step 5 — verify

Re-run the Step 1 `GET .../factors` call:

- Expect exactly one factor, `status: "verified"`, with a **new**
  `id` and a `created_at` of today.
- `GET {SUPABASE_URL}/rest/v1/mfa_lockouts?user_id=eq.b0934b4f-79e3-4f57-a115-4d86879d5e88`
  should show `failed_attempts: 0`, `locked_until: null`.
- Confirm the account can log in and pass `/staff/mfa/verify` end to end.

## Safety notes

- All of the above targets `SUPABASE_URL=https://hikgijuipymfghfuyrjv.supabase.co`
  in `server/.env` — this is the **dev** project, not production
  (`gtqncxqsofqtzrlgxdfm`). Double-check the URL in whatever request tool
  is used before sending Steps 2–3; the service-role key bypasses all
  Row Level Security, so it works against either project without
  complaint if pointed at the wrong one.
- Step 2 deletes exactly one specific factor id, not "all factors for this
  user" — re-check the id from a fresh Step 1 call rather than reusing the
  one recorded above if any time has passed.

## Words you might not know

- **MFA (Multi-Factor Authentication)** — logging in needs two proofs:
  something you know (password) and something you have (a code from your
  phone).
- **TOTP (Time-based One-Time Password)** — the 6-digit code used here,
  changing every 30 seconds, computed from a secret both your phone and
  the server know.
- **Factor** — Supabase's name for one enrolled authenticator entry (one
  secret, tied to one account).
- **aal2 (Authenticator Assurance Level 2)** — a flag on a login session
  meaning "this session has already passed an MFA check," as opposed to
  aal1 ("only a password so far"). Some actions (like removing your own
  factor) are only allowed once you're at aal2.
- **Service-role key** — an admin credential (`SUPABASE_SERVICE_ROLE_KEY`
  in `server/.env`) that can act on any account and bypasses the
  permission checks a normal user session is subject to. Only ever used
  server-side, never shipped to the browser.
- **Lockout** — a temporary block (15 minutes here) on trying more codes
  after 5 wrong attempts in a row.

## How you'll know it worked

See Step 5 above — no separate `testing/testing.md` was written since this
is a one-time data repair with its own inline verification, not a code
change with a regression surface to walk through.

## Result

Steps 2–3 were run against dev (`hikgijuipymfghfuyrjv`) at
2026-09-16 ~07:05 UTC:

- Deleted TOTP factor `bce89fb3-5f72-435c-9978-6d54a0223d94` for
  `makati.superadmin1` (`GET .../factors` confirmed it was the only one
  before deleting; `GET .../factors` after showed `[]`).
- Reset its `mfa_lockouts` row: `failed_attempts: 0`, `locked_until: null`
  (confirmed via `GET`).

Remaining: the account owner needs to do Step 4 themselves (delete the
dead "Golden Fur" entry from their authenticator app, log in, and scan the
new QR code `/staff/mfa/enroll` will now show them, since `mfa_enrolled`
is `false` again).

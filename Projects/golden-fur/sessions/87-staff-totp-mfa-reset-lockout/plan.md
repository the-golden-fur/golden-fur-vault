---
title: Staff TOTP MFA verified-factor reset lockout fix
date: 2026-09-13
tags: [session-plan, golden-fur]
project: golden-fur
session: 87-staff-totp-mfa-reset-lockout
branch: fix/staff-totp-mfa-verified-factor-reset
---

# 87 — Staff TOTP MFA verified-factor reset lockout fix

## What you asked for

> As a developer, I want the staff MFA TOTP codes to not be refreshed
> randomly, so that users don't lose access to their account. Somehow,
> TOTP codes in google authenticator randomly resets, and still prompts
> for a TOTP code. There's no longer a QR code to scan, making it
> impossible to access. I want you to determine what is causing this
> random reset and fix it.
> — task description, referencing `Architectural-Change-History.docx`
> ("As a developer, I want the staff MFA TOTP codes to not be refreshed
> randomly..." — In Progress, Development, Matthew)

Follow-up clarification given mid-session: the lockout is usually noticed
after a redeploy/restart (`npm run dev`), and the only reliable fix so far
has been resetting the local database, which works again for a while
before drifting back.

## What this part of the app does today

Staff members with certain roles (Admin, Supervisor, Superadmin — always;
anyone else, only if they've turned it on themselves in Settings) must
complete TOTP multi-factor authentication (the standard "6-digit code from
an authenticator app" flow, e.g. Google Authenticator) after their
username/password check succeeds.

This app doesn't store or manage the TOTP secret itself at all — that's
100% handled by Supabase Auth's own built-in MFA system
(`auth.mfa.enroll` / `.verify` / `.unenroll` / `.listFactors`), backed by a
table Supabase manages internally (`auth.mfa_factors`). Our code only ever
calls Supabase's API; there's no app-level secret column anywhere to get
corrupted or re-encrypted.

The shared server-side helper for starting enrollment is
`enrollTotpFactor` (`server/src/shared/auth/api/supabaseAuth.api.ts`).
It's used by both the staff and customer "start MFA setup" endpoints. When
Supabase reports a factor with the same name already exists (a
"conflict"), this helper has a fallback: clean up any stray _unverified_
factors and retry. If a real, already-verified factor is what's causing
the conflict, a third "last resort" step kicks in — it removes **any**
factor, verified or not, and immediately creates a brand-new one with a
new secret and a new QR code.

Several places can end up calling that "start MFA setup" endpoint again
for someone who is _already_ fully enrolled and verified — not just
someone doing first-time setup:

- After login, if the "am I already enrolled?" status check fails or
  times out, the app assumes "not enrolled" and sends the user to the
  enrollment screen instead of the code-entry screen
  (`StaffLoginForm.tsx`).
- The enrollment page itself (`MfaEnrollPage.tsx`) shows the "scan this QR"
  screen and immediately starts a new enrollment the moment it loads, with
  no check first for whether this account is already enrolled. It's
  reachable any time (a stale link, the browser back button, a second
  tab), not just during genuine first-time setup.
- On the Settings → Security page, a Supervisor who hasn't enrolled yet
  gets shown two separate "set up MFA now" enrollment flows at the same
  time — one from the mandatory-MFA popup, one inline on the page — because
  the page's own "which roles are mandatory" list is missing Supervisor.
  Two enrollment attempts firing close together is exactly the kind of
  "conflict" that can end up hitting that destructive last-resort step.

## What's wrong / what's missing

1. **A verified, working MFA factor can be silently deleted and replaced**
   as a side effect of the enrollment endpoint being called again — even
   though nobody asked to reset their MFA. This is the actual cause of
   "codes reset for no reason." The account's real secret is gone (so the
   phone's old code stops working), but the person is never guaranteed to
   see the new QR code that was silently generated in its place.
2. **Nothing stops the enrollment endpoint from being called for an
   already-enrolled account** — not the server route, not the enrollment
   page, not the reusable enrollment panel component. Every layer trusts
   the layer above it to only call this when it's genuinely someone's
   first time.
3. **A failed "am I enrolled?" check is treated the same as "not
   enrolled"** at login, which is exactly backwards — it should mean "we
   don't know yet," not "assume the safe-looking but wrong answer."
4. **The Settings page's mandatory-MFA role list is missing Supervisor**,
   causing a real, reproducible double-enrollment race for that role.

## What we're going to change

1. **Stop the enrollment helper from ever deleting a verified factor.** —
   _Which files:_
   `server/src/shared/auth/api/supabaseAuth.api.ts` (the `enrollTotpFactor`
   function — remove its "last resort, delete verified factors too" step;
   if a conflict survives the normal unverified-cleanup retry, that means
   a verified factor genuinely exists, so just report that back instead of
   touching it). — _Why:_ this is the actual destructive operation; taking
   it out closes the hole no matter which caller triggers a conflict.

2. **Make the server refuse to re-enroll someone who's already verified.**
   — _Which files:_ `server/src/features/auth/staff/staffAuth.controller.ts`
   and `server/src/features/auth/customers/customerAuth.controller.ts`
   (their "start MFA enrollment" controllers — check current enrollment
   status first, and return a clear "already enrolled" response instead of
   starting a new enrollment at all). — _Why:_ this closes the door at the
   API level, so it doesn't matter which client screen or bug tries to call
   it — an already-enrolled account can never be re-enrolled by accident,
   from any client, old or new.

3. **Make the enrollment screen check first, instead of assuming.** —
   _Which files:_
   `client/src/features/auth/staff/pages/MfaEnrollPage/MfaEnrollPage.tsx`
   (check real enrollment status before showing anything; if already
   enrolled, send the user to the code-entry screen instead), and
   `client/src/shared/components/TotpEnrollPanel/TotpEnrollPanel.tsx` (the
   reusable "scan this QR" component used by several screens — if the
   server ever does say "already enrolled," show a plain message instead
   of a broken/empty enrollment form). — _Why:_ this is the most directly
   reachable trigger (a stale link or the back button can land here for
   someone who's already set up), so it needs its own check, not just
   reliance on the server.

4. **Stop guessing "not enrolled" when the status check fails.** — _Which
   files:_
   `client/src/features/auth/staff/components/forms/StaffLoginForm/StaffLoginForm.tsx`
   (if the "am I enrolled?" check errors out, show a "please try signing
   in again" message instead of silently treating the account as
   unenrolled and sending it to the enrollment screen). — _Why:_ this
   directly matches the "usually happens right after a restart/redeploy"
   pattern — a fresh restart is exactly when this kind of check is most
   likely to hit a temporary hiccup.

5. **Fix the two places a "mandatory MFA roles" list is missing
   Supervisor**, so it matches the one used everywhere else. — _Which
   files:_ `StaffLoginForm.tsx` (same file as above) and
   `client/src/pages/SettingsPage/tabs/SecurityTab.tsx`. — _Why:_ the
   Settings-page gap causes a real, currently-reproducible double
   enrollment race for Supervisors; the login-form gap is the same
   inconsistency at login time.

## Words you might not know

- **TOTP** — "Time-based One-Time Password," the 6-digit code an app like
  Google Authenticator generates every 30 seconds from a shared secret.
- **factor** — Supabase's term for one enrolled MFA method (here, always
  "one TOTP factor per account"). A factor is either _verified_ (set up
  and confirmed with a real code) or _unverified_ (created but never
  confirmed — e.g. someone scanned a QR but never entered the code).
- **aal2** — "Authenticator Assurance Level 2," Supabase's internal marker
  for "this session has actually completed MFA," which is required before
  Supabase will let you delete a verified factor through its own API.
- **race** — when two things happen at almost the same time and interfere
  with each other, like two "start enrollment" calls firing close together
  and each one confusing the other's in-progress factor for a leftover to
  clean up.
- **defense in depth** — checking the same rule at more than one layer
  (server _and_ client here) so that a bug or bypass at one layer doesn't
  fully defeat the protection.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (written once the
implementation is done).

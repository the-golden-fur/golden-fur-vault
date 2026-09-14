# Stop MFA setup from silently deleting a working authenticator entry

Branch: `fix/staff-mfa-enroll-factor-reset` (golden-fur repo)

## The request, verbatim

> the auth is broken again / what is causing the 401 error? / it just randomly locks me out of superadmin account
>
> it was not an invalid code / it was the same QR scanned code, now it just keeps getting reset / is there something wrong with my env? / since I did make a new supabase ... this started happening after I made a new supabase for dev

> Scope note: the same conversation also raised a 502 Bad Gateway and a dual-`npm run dev` port collision. That turned out to be a separate, purely local dev-environment issue (two independent `npm run dev` processes fighting over ports 3000/5173), not a code bug — no code change was made for it. This session's fix addresses only the MFA lockout root cause below.

## Root cause / Context

`server/src/shared/auth/api/supabaseAuth.api.ts`'s `enrollTotpFactor` had a third fallback tier: if enrolling a new TOTP factor still conflicted after cleaning up unverified ones, it removed **verified** factors too and retried. Supabase only permits removing a verified factor from a session already at AAL2 (i.e., one that has already passed an MFA challenge) — so that fallback could only ever succeed for an account that already had a real, working, verified factor. `/staff/mfa/enroll` (`client/src/features/auth/staff/pages/MfaEnrollPage/MfaEnrollPage.tsx`) has no route guard, so an AAL2 session landing there again (bookmark, browser Back, a stale link) triggers `TotpEnrollPanel`'s unconditional on-mount enroll call, hits the conflict, and silently deletes the real factor before issuing a new one — no error shown, so the user has no idea their authenticator app's saved entry is now for a deleted factor. Every subsequent code fails, and after 5 failures `mfa_lockouts` locks the account for 15 minutes (`server/src/shared/services/mfaLockout/mfaLockout.service.ts`, `LOCKOUT_THRESHOLD = 5`, `LOCKOUT_MINUTES = 15`).

Confirmed directly against the dev Supabase project (`hikgijuipymfghfuyrjv`): the affected account's TOTP factor id and `created_at` were identical before and after the fix was applied and re-tested, proving no further factor replacement occurs. Also confirmed via `git log` that no other recent commit touched any auth-related file, and that the `MfaEnrollForm.tsx` component (a pre-existing, unused dead-code component from before commit `8235bb0`, which switched the live enroll page to `TotpEnrollPanel`) has zero remaining references anywhere in the client.

## What changed

### Server

- `server/src/shared/auth/api/supabaseAuth.api.ts` — `enrollTotpFactor` no longer has the third "remove verified + unverified, retry" tier. A persisting conflict after the unverified-only cleanup is now returned as-is to the caller. The unverified-cleanup-and-retry-once logic (for a genuine double-invoked-mount race) is unchanged.
- `server/src/shared/auth/api/supabaseAuth.api.spec.ts` — replaced the two tests that asserted the old destructive behavior with one regression test proving `unenroll` is never called against a verified factor, even when the enroll conflict persists.

### Client

- `client/src/features/auth/staff/pages/MfaEnrollPage/MfaEnrollPage.tsx` — calls `getMfaStatus('staff', accessToken)` on mount; if `mfa_enrolled` is already `true`, renders `<Navigate to="/staff/mfa/verify" replace />` instead of the enroll panel. A failed status check fails open to "not enrolled" (renders the panel as before) — safe now that the server-side fix means that path can no longer destroy a real factor either way.
- `client/src/features/auth/staff/pages/MfaEnrollPage/MfaEnrollPage.spec.ts` — new: covers the redirect-when-already-enrolled case and the render-panel-when-not-enrolled case.

## Manual test — step by step

This bug only shows up for a staff account whose role requires MFA (Admin, Supervisor, Superadmin) and that has _already_ completed enrollment.

1. Open your web browser and go to `http://localhost:5173`.
2. Click **Staff Login** (top-right corner). Sign in with an Admin/Supervisor/Superadmin account that already has MFA set up (password + that day's 6-digit code).
3. Once you land on the staff **Dashboard**, manually type `/staff/mfa/enroll` into the browser's address bar and press Enter (this simulates the bookmark/back-button accident).
4. **Before the fix:** you'd see a brand-new QR code and secret key — a silent giveaway that your existing setup was just replaced. **After the fix:** you're immediately redirected back to `/staff/mfa/verify` or `/staff` without ever seeing an enroll screen.
5. Go back to the Dashboard, sign out, and sign back in with the same account and the same authenticator app entry you had before step 3. The same 6-digit code that worked before should still work — it was never invalidated.

## Test suites

- `server`: `npm test` — 1148/1148 passing (full suite, including the updated `supabaseAuth.api.spec.ts`).
- `client`: `npm test` — full suite passing, including the new `MfaEnrollPage.spec.ts` (2/2).
- `npx tsc --noEmit` clean in both `client/` and `server/`; ESLint and Prettier clean on every touched file.
- These counts were captured live in-session (not from a separate CI run) after applying the fix.

## Open items

- The recurring "same QR code, keeps failing" root cause is confirmed fixed for future occurrences, but if this bug had already fired for an account before this fix shipped, that account's authenticator app entry is permanently stale — it needs to go through `/staff/mfa/enroll` fresh (a genuinely first-time enrollment, now safe) or use the "Start over" button, not just retry the old code.
- Every staff account enrolls MFA under the same issuer label, `"Golden Fur"` (`enrollTotpFactor`'s `issuer: 'Golden Fur'`). In a dev environment with many seeded staff accounts, this makes it easy to read the wrong entry in an authenticator app if more than one is enrolled there. Not fixed in this session — flagged as a possible follow-up (e.g. a per-account issuer label).

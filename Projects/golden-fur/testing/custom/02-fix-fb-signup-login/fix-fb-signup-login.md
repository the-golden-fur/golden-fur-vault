# Facebook (and Google) OAuth Callback Fixes - Verification

Sprint: Sprint 1
Type: Custom fix (not tracked against a specific sprint/epic backlog item)
Branch: `fix/fb-signup-login`

Filed against a manual report: signing in with Facebook showed "Continue as
Matthew," Facebook accepted it, the browser landed back on
`/auth/callback#` (bare, empty fragment) - and the app then showed a
generic "Sign in failed: OAuth session could not be established," with no
way to tell why.

## First Pass (Wrong Theory)

Assumed the account's Facebook email was unverified; added `scopes:
'email'` to `signInWithFacebook()`/`signInWithGoogle()` plus a
fragment-reading check in `handleOAuthCallback()`. The user confirmed their
Facebook account was already fully verified and reproduced the exact same
generic error with the fix in place - disproving this theory.

## Second Pass (Real But Incomplete Theory)

Found that `client/src/shared/auth/api/auth.api.ts` created the Supabase
client with `detectSessionInUrl: true`, which auto-parses and **strips**
the OAuth redirect's URL fragment the instant any auth method first runs -
and `AuthProvider`'s own `getSession()` call on mount does exactly that,
racing ahead of the callback page. This is a real bug (confirmed by reading
`@supabase/auth-js`'s `GoTrueClient.js`: a failed auto-detected exchange's
error is discarded internally and never surfaced through `getSession()` or
`onAuthStateChange`) and was fixed - `detectSessionInUrl` set to `false`,
with `handleOAuthCallback()` reading the fragment and calling
`client.auth.setSession()` itself. But retesting still showed the exact
same generic error, with the URL fragment already gone by the time the app
checked it (confirmed by the address bar showing no trailing `#`, meaning
our own code had already read-and-cleared it) - meaning something else was
still short-circuiting before the new fragment-reading code even got a
chance to look at what was in it, or was clearing state some other way.

## Confirmed Root Cause (Verified From a Live Network Capture)

Rather than theorize further, we captured the actual browser-level redirect
chain via DevTools Network (Preserve log, filtered to `callback`) during a
real Facebook login attempt. The request to
`gtqncxqsofqtzrlgxdfm.supabase.co/auth/v1/callback?code=...` returned a
`302` whose `Location` response header was:

```text
http://localhost:5173/auth/callback#access_token=eyJ...(valid JWT)...
&expires_at=...&expires_in=3600&provider_token=...
&refresh_token=g63x2c5wrv4&sb=&token_type=bearer
```

This proves Facebook and Supabase were never the problem: the OAuth
exchange succeeds server-side and a real, valid session is handed back in
the fragment every time. Checking DevTools Application > Session Storage
for `http://localhost:5173` immediately after landing on the error page
showed only an unrelated browser-extension key - **no `oauthProvider`
entry** - confirming that the `window.sessionStorage.setItem('oauthProvider',
...)` call made in `signInWithFacebook()`/`signInWithGoogle()` before
redirecting does not reliably survive the round trip through Facebook and
Supabase's domains and back (DevTools also flagged a "Chrome may soon
delete state for intermediate websites in a recent navigation chain" issue
during this same session, consistent with a browser-level cause rather
than an app bug).

`handleOAuthCallback()`'s control flow treated that sessionStorage value as
a **gate**: `if (!provider) { return { data: null, error: 'OAuth session
could not be established' } }`, before ever looking at whether the
fragment actually contained tokens. So even with a perfectly valid,
freshly-issued session sitting in the URL, the callback aborted immediately
because the marker it checked first was gone - the exact failure observed.

## What Changed

`client/src/features/auth/customer/api/customerAuth.api.ts`:

- `handleOAuthCallback()` no longer gates on `getStoredOAuthProvider()`.
  The sessionStorage value is now read best-effort (used only to label
  which provider it was, for the caller's information) and is never a
  precondition for attempting to establish the session. The fragment's own
  `access_token`/`refresh_token` - or an `error`/`error_description` pair -
  are now the only signals that decide the outcome.
- Consolidated the three separate `clearStoredOAuthProvider()` calls
  scattered through the function into one, run immediately after reading
  the (possibly absent) provider value.

`client/src/features/auth/customer/customerAuth.types.ts`:

- `OAuthCallbackResult.provider` widened to `'google' | 'facebook' | null`,
  since it's no longer guaranteed to be known. Nothing downstream
  (`OAuthCallbackPage.tsx`, the backend callback request) ever reads this
  field - it's informational only - so widening it is safe.

`client/src/features/auth/customer/api/customerAuth.api.spec.ts`:

- Added a regression test that drives a callback with valid fragment
  tokens but **no** `oauthProvider` in sessionStorage, asserting it still
  succeeds with `provider: null` in the result - this is the exact bug
  reproduced in isolation.
- Removed the old test that asserted an error when no provider was stored
  (that behavior was the bug, not a spec).

(The `detectSessionInUrl: false` / manual `setSession()` change from the
second pass is unrelated but still correct, and remains in place - see
that pass's write-up above for why.)

## Fourth Round: The Real, Final Error - Confirmed on Facebook's Side, Not This App's

With the third-pass fix in place, Facebook login went further than ever
before and produced a brand new, specific error: **"Sign in failed: Email
is required for account merge,"** with the browser console showing the
`/auth/customers/oauth/callback` request itself returning `500`. This is a
real error thrown by `mergeOrCreate()` in
`server/src/features/auth/customers/services/accountMerge.service.ts` when
`session.user.email` is empty - i.e. the whole client-side OAuth chain now
works end-to-end (confirmed again live: the Network tab showed a request to
the backend callback carrying a real `Authorization: Bearer <JWT>` header),
and Supabase itself has a valid signed-in user - but that user has no email
attached.

This was tracked all the way to ground truth, without any more guessing:

1. Supabase Dashboard > Authentication > Users, searched by this exact
   user's UID, showed `Email: -` for the Facebook-linked account -
   confirming Supabase genuinely never received an email, not a bug in how
   this app reads the session.
2. Deleting that Supabase user and signing in again with a fresh account
   reproduced the identical error, ruling out stale Supabase data.
3. Facebook's **Graph API Explorer** (`developers.facebook.com/tools/explorer`),
   using the Golden Fur app with a freshly generated user token that
   explicitly included the `email` permission, called `GET
/me?fields=id,name,email` directly against Facebook - bypassing this
   app and Supabase entirely. The response came back as `{"id": "...",
"name": "Matthew Escandor Sta Ana"}` - **no `email` key at all**, even
   though the permission was granted and Facebook's Account Center listed
   an email address for the account.

This is conclusive: Facebook itself will not hand over an email for this
account through its own API, regardless of what this app, Supabase, or the
requested OAuth scope do. Per Meta's documented behavior, the `email`
permission only returns a value for a _confirmed_ email - Account Center
listing an address is not the same as Facebook's Graph API treating it as
confirmed. The fix on the Facebook side (not this repo) is to remove and
re-add the email in Accounts Center > Personal details > Contact info,
complete the confirmation Facebook sends to that inbox, and re-verify with
Graph API Explorer before retrying login.

Since this is a legitimate scenario any real user's Facebook/Google account
could hit in production (not just this dev's test account), the backend's
handling of it was still a bug worth fixing: `customerOauthCallbackController`
in `server/src/features/auth/customers/customerAuth.controller.ts` caught
`mergeOrCreate`'s thrown error with a generic `catch` that always returned
`500 Internal Server Error` - the correct status for an unexpected server
fault, not for an expected, user-actionable "your account has no email"
case.

**What changed (server):**

- `accountMerge.service.ts` now exports `MissingProviderEmailError`, a
  dedicated `Error` subclass, and throws that instead of a plain `Error`
  when `session.user.email` is empty.
- `customerAuth.controller.ts`'s `customerOauthCallbackController` catches
  `MissingProviderEmailError` specifically and responds `422` with a clear,
  actionable message ("Your account has no confirmed email address from
  this sign-in provider...") instead of falling through to the generic
  `500` handler. Every other error still returns `500` unchanged.
- `customerAuth.unit.spec.ts`: added a test asserting the `422` response
  and message for this case; updated the `accountMerge.service.ts` mock to
  also export `MissingProviderEmailError` (a distinct class per mocked
  module, matched via `instanceof` the same way the real controller does).

No changes were needed on the client for this round - `handleOAuthCallback()`
already reads `body.error` off any non-`ok` response regardless of status
code, so the `422` surfaces through `OAuthCallbackPage` exactly like the
old `500` did, just with the real message instead of a generic one.

## Automated Verification

From `client/`, run:

```powershell
npx tsc -b
npm.cmd run test
npm.cmd run lint
```

Expected result (confirmed while making this change):

- `tsc -b` exits with code 0.
- All tests pass (63 tests, including the regression test for a missing
  sessionStorage marker with valid fragment tokens).
- Lint exits with 0 errors/warnings.

From `server/`, run:

```powershell
npm.cmd run typecheck
npm.cmd run test
npm.cmd run lint
```

Expected result (confirmed while making this change):

- `typecheck` exits with code 0.
- All tests pass (127 tests as of this fix, including the new
  `customerOauthCallbackController` test for the `422` /
  `MissingProviderEmailError` case).
- Lint exits with 0 errors (3 pre-existing `no-console` warnings, same ones
  noted in `custom/01-fix-mfa/fix-mfa.md`, are expected and unchanged).

## Manual Client Verification

1. From `client/`, run `npm.cmd run dev` and open the printed local URL.
2. Go to `/login`, click **Continue with Facebook**, complete the Facebook
   consent screen. Confirm you land on `/portal` (or see the account-merge
   notice) - not the generic error - even though the underlying
   sessionStorage marker may or may not survive the round trip. Note: this
   will still fail with "Your account has no confirmed email address from
   this sign-in provider..." until the Facebook account being tested with
   has a _confirmed_ email (see the Fourth Round above) - that is a
   Facebook-account-side prerequisite, not something this app's code can
   route around.
3. Repeat with **Continue with Google** and confirm the same success path
   (Google reliably provides a verified email, so this should succeed with
   any real Google account).
4. To reproduce the sessionStorage-loss regression without needing a real
   Facebook flow: open DevTools Console and run
   `sessionStorage.removeItem('oauthProvider')`, then navigate to
   `http://localhost:5173/auth/callback#access_token=<any value>&refresh_token=<any value>`
   (a fake token is enough to reach `setSession()`; expect Supabase to
   reject it, but the app should now show _that_ rejection - not the old
   "no provider stored" short-circuit which would have returned instantly
   without ever calling `setSession()`).
5. To exercise the new `422` path directly without a real Facebook account:
   sign in with an account/session whose Supabase user has no email (e.g.
   via the flow above with a token from a real session that lacks one), or
   temporarily point a test request at `/auth/customers/oauth/callback`
   with a valid bearer token for a no-email user. Confirm the response is
   `422` with a body containing `"Your account has no confirmed email
address from this sign-in provider..."`, and that the callback page
   displays that exact message rather than a generic one.
6. If Facebook/Google login still fails after this fix with a _different_
   message than the ones described above, that message is genuine - from
   `setSession()`, from `mergeOrCreate()`, or from the backend callback
   endpoint - use it to decide the next step, not guesswork.

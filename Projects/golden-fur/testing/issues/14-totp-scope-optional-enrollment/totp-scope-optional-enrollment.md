# Issue 14 Verification - Optional TOTP Scope

Sprint: Sprint 1  
Epic: Epic A-1  
Issue: #14 - refactor(server): correct TOTP scope; add optional enrollment endpoints

## What Changed

- Confirmed `requireMfa` only enforces `aal2` for `Admin` and `Supervisor`.
- Added explicit regression tests proving `Receptionist`, `Cashier`, `Groomer`, `Veterinarian`, and `Pet Assistant` are not blocked by `requireMfa` when their session is not `aal2`.
- Kept existing staff MFA enrollment endpoints JWT-only:
  - `POST /auth/staff/mfa/enroll`
  - `POST /auth/staff/mfa/verify`
- Added optional customer MFA endpoints:
  - `POST /auth/customers/mfa/enroll`
  - `POST /auth/customers/mfa/verify`
- Confirmed customer login remains password/session based and does not require MFA.

## Automated Verification

From `server/`, run:

```powershell
npm.cmd test -- --run src/features/auth/staff/tests/staffAuth.middleware.unit.spec.ts src/features/auth/customers/tests/customerAuth.unit.spec.ts src/features/auth/customers/tests/customerAuth.integration.spec.ts
npm.cmd run typecheck
npm.cmd run lint
```

Expected result:

- The focused Vitest run passes all tests.
- TypeScript exits successfully.
- ESLint exits successfully. Current output may include existing `no-console` warnings in `customerAuth.controller.ts`; there should be no lint errors.

## Manual API Verification

Use the Postman collection in:

`testing/docs/sprints/sprint1/epicA1/issue-14/postman/issue14.postman_collection.json`

### Postman Setup

1. Open Postman.
2. In the left sidebar, click **Collections**.
3. Import or open **Issue 14 - Optional TOTP Scope**.
4. Click the collection name, not an individual request.
5. Open the **Variables** tab.
6. Set these values in the **Current value** column:

- `base_url`: local server URL, for example `http://localhost:3000`
- `staff_username`: staff username to test
- `staff_password`: staff password to test
- `customer_email`: customer email to test
- `customer_password`: customer password to test

Leave these blank until the steps below tell you to fill them:

- `staff_access_token`
- `customer_access_token`
- `totp_code`

7. Click **Save** on the collection.

Important: Postman has **Initial value** and **Current value** columns. Put tokens and codes in **Current value**. Requests use the current value while you are testing.

Important: `staff_access_token` and `customer_access_token` must be login response JWTs. Do not use the Supabase service-role key, anon key, project API key, or anything that starts with a label like `supabase_service_role_api_key`. The value should be the long `access_token` returned by `Staff - Login` or `Customer - Login`.

⚠️ If Postman's built-in secret scanner ever shows a "Secrets Detected" banner naming a **Supabase Service Role API Key** found in this collection, one of the token variables above has that key pasted into it instead of a real login token. Clear the variable's **Current value**, re-run the matching `Login` request, and paste in the `access_token` from that response instead. A service-role key authenticates as the whole Supabase project, not as one staff member or customer, so using it here is also the most common cause of `No TOTP factor found` below — treat it as a real credential leak, not just a broken test: remove it from the variable immediately, and if you're not certain it stayed local to your machine, rotate it from your Supabase project's API settings.

### Google Authenticator — Exact Setup Steps

Use these steps any time an enroll response gives you a `secret` to add. They apply to both `Staff - Optional TOTP Enroll` and `Customer - Optional TOTP Enroll` — later steps in this doc link back here instead of repeating them.

The enroll response body looks like this (paths matter for step 5 below):

```json
{
  "id": "....",
  "type": "totp",
  "totp": {
    "qr_code": "<svg>...</svg>",
    "secret": "JBSWY3DPEHPK3PXP",
    "uri": "otpauth://totp/...?secret=JBSWY3DPEHPK3PXP&issuer=..."
  }
}
```

Only `totp.secret` goes into Google Authenticator. `totp.uri` is a full URI meant for apps that consume a link directly, and `totp.qr_code` is a raw SVG string, not something Postman can display as a scannable image — that's why these steps use manual key entry instead of scanning a QR code.

1. Open the Google Authenticator app on your phone.
2. Tap the **+** button to add a new entry.
   - Android: the **+** is a floating button in the bottom-right corner.
   - iOS: the **+** is in the top-right corner.
3. A menu appears with two choices: **Scan a QR code** and **Enter a setup key**. Tap **Enter a setup key**.
4. You'll see two fields: **Account name** and **Your key**.
5. In **Account name**, type something you can recognize later, for example `Golden Fur Staff` or `Golden Fur Customer`. This label is only for your own reference and is never sent to the server.
6. In **Your key**, paste the exact value of `totp.secret` from the enroll response. Do not include quotation marks, the `secret` field name, or any surrounding text — only the base32 characters themselves, with no spaces.
7. Below the key field is a **Type of key** selector with two options: **Time based** and **Counter based**. Confirm **Time based** is selected — it's the default, and it's the only mode Supabase supports. Do not switch it to **Counter based**.
8. Tap **Add** (top-right) to save the entry.
9. The new entry appears in your Google Authenticator list showing a 6-digit code with a circular countdown timer next to it. The circular countdown confirms it's time-based — a counter-based entry would show a static refresh icon instead.
10. Read the current 6-digit code. Google Authenticator displays it as two groups of three digits with a space between them (for example `123 456`) purely for readability — when you paste it into Postman's `totp_code` variable, type only the six digits with no space (`123456`).
11. Codes rotate every 30 seconds. If the countdown ring is nearly empty, wait for it to reset and use the fresh code — Supabase validates against a narrow time window, and a code that expires mid-request will be rejected as invalid.
12. If you enroll more than once for the same account (for example, after a failed attempt), add a new Google Authenticator entry for the newest `secret` and delete the older entries so you don't accidentally read a stale code.

### If You See An HTML Error Page

If Postman returns HTML with `Error: Missing or malformed token`, the TOTP code was not checked yet. The request failed before verification because the API did not receive a valid auth header.

Fix it this way:

1. Open the request that failed, for example `Staff - Optional TOTP Verify`.
2. Open the **Headers** tab.
3. Confirm there is a header exactly like this:

```text
Authorization: Bearer {{staff_access_token}}
```

4. Hover over `{{staff_access_token}}` in the request.
5. Confirm Postman shows the actual token value, not an empty value.
6. If it is empty, run `Staff - Login` again and copy the `access_token` into the collection variable `staff_access_token`.
7. Click **Save** on the collection variables.
8. Retry `Staff - Optional TOTP Verify`.

Do not put the TOTP code in the Authorization tab. The TOTP code belongs only in the JSON body:

```json
{
  "code": "{{totp_code}}"
}
```

The auth token belongs in the header:

```text
Authorization: Bearer {{staff_access_token}}
```

### If You See `No TOTP factor found`

If Postman returns:

```json
{
  "error": "No TOTP factor found"
}
```

the request is authenticated, but the token you used for verify does not belong to the same Supabase Auth user that enrolled the TOTP factor.

Fix it this way:

1. Open the collection variables.
2. Clear the **Current value** for `staff_access_token`.
3. Clear the **Current value** for `totp_code`.
4. Do not paste a Supabase service-role key, anon key, or project API key into `staff_access_token`.
5. Run `Staff - Login`.
6. Copy the `access_token` from the login response.
7. Paste that exact token into the **Current value** for `staff_access_token`.
8. Click **Save**.
9. Run `Staff - Optional TOTP Enroll` using that same `staff_access_token`.
10. Use the new `secret` from this latest enroll response in Google Authenticator.
11. Copy the fresh 6-digit code from that new authenticator entry.
12. Paste it into the **Current value** for `totp_code`.
13. Click **Save**.
14. Run `Staff - Optional TOTP Verify` before the code expires.

Enroll and verify must use the same staff login token unless you intentionally log in again and enroll again. If you enroll with one token and verify with a different token, Supabase may not find the factor.

If you have several failed authenticator entries for the same staff account, delete the old entries from Google Authenticator and keep only the newest secret from the newest successful enroll response.

### AC-1: Admin and Supervisor Require MFA

1. Create or use an Admin staff account with a valid `aal1` access token.
2. Call a route protected by `requireMfa`.
3. Confirm the response is `403` with the MFA-required error.
4. Repeat with a Supervisor `aal1` token.
5. Complete TOTP verification and retry with an `aal2` token.
6. Confirm the route is no longer blocked by `requireMfa`.

### AC-2: Lower Staff Roles Are Never Blocked

1. Create or use staff accounts for these roles:
   - Receptionist
   - Cashier
   - Groomer
   - Veterinarian
   - Pet Assistant
2. Use an `aal1` token for each role.
3. Call the same route protected by `requireMfa`.
4. Confirm none of these roles receives `403 MFA required`.

### AC-3: Lower Staff Roles Can Opt In

1. In Postman, open `Staff - Login`.
2. Open the **Body** tab.
3. Confirm the body contains:

```json
{
  "username": "{{staff_username}}",
  "password": "{{staff_password}}"
}
```

4. Click **Send**.
5. Confirm the response is `200 OK`.
6. In the response body, copy the full `access_token` value.
7. Click the collection name **Issue 14 - Optional TOTP Scope** in the left sidebar.
8. Open the **Variables** tab.
9. Paste the copied token into the **Current value** cell for `staff_access_token`.
10. Make sure `staff_access_token` is not a Supabase service-role key or anon key.
11. Click **Save**.
12. Open `Staff - Optional TOTP Enroll`.
13. Open the **Headers** tab.
14. Confirm this header is present:

```text
Authorization: Bearer {{staff_access_token}}
```

15. Hover over `{{staff_access_token}}` and confirm Postman previews the actual login token.
16. Click **Send**.
17. Confirm the response is `200 OK`.
18. In the response body, copy the `secret` value out of the `totp` object.
19. Follow [Google Authenticator — Exact Setup Steps](#google-authenticator--exact-setup-steps) above to add that `secret` and read a fresh 6-digit code.
20. In Postman, click the collection name again.
21. Open **Variables**.
22. Paste the 6-digit code into the **Current value** cell for `totp_code`.
23. Click **Save**.
24. Open `Staff - Optional TOTP Verify`.
25. Open the **Headers** tab and confirm:

```text
Authorization: Bearer {{staff_access_token}}
```

26. Open the **Body** tab and confirm:

```json
{
  "code": "{{totp_code}}"
}
```

27. Hover over both variables and confirm Postman previews real values.
28. Click **Send** before the authenticator code expires.
29. Confirm a `200 OK` response with refreshed session tokens, or `{ "success": true }` if Supabase does not return a refreshed session.

If you get `401 Unauthorized` with HTML and `Missing or malformed token`, repeat steps 6-10 and make sure `staff_access_token` is saved in the collection's **Current value** column.

If you get `400` with `{ "error": "No TOTP factor found" }`, this is not about the code you typed — `listFactors()` came back empty for whoever your `staff_access_token` authenticates as. Check, in order: (1) `staff_access_token` is a real `access_token` from `Staff - Login`, not a service-role/anon/API key — see the [callout](#postman-setup) above; (2) you ran `Staff - Optional TOTP Enroll` with that exact same token before verifying; (3) you haven't logged in again as a different account between enroll and verify. Then repeat the full login → enroll → verify sequence with one fresh `staff_access_token`, and don't reuse a secret from an earlier attempt.

If you get `401` with `{ "error": "Invalid code" }`, the auth header worked, but the TOTP code was rejected. Generate a fresh code in Google Authenticator, update `totp_code`, save, and send again immediately.

### AC-4: Customer Optional TOTP Endpoints Exist

1. Run `Customer - Login`.
2. Confirm the response is `200 OK`.
3. Copy the `access_token` from the response body.
4. Click the collection name.
5. Open **Variables**.
6. Paste the token into the **Current value** cell for `customer_access_token`.
7. Click **Save**.
8. Run `Customer - Optional TOTP Enroll`.
9. Confirm a `200 OK` response with Supabase MFA enrollment data, and copy the `secret` value out of the `totp` object.
10. Follow [Google Authenticator — Exact Setup Steps](#google-authenticator--exact-setup-steps) above to add that `secret` and read a fresh 6-digit code.
11. Paste the code into the collection variable `totp_code` under **Current value**.
12. Click **Save**.
13. Run `Customer - Optional TOTP Verify` before the code expires.
14. Confirm a `200 OK` response with refreshed session tokens, or `{ "success": true }`.

If you get `{ "error": "No TOTP factor found" }` here, the same rule applies as in AC-3: it means `customer_access_token` isn't a real login token for the same customer that just enrolled — usually a pasted service-role/anon key, a stale token, or enroll and verify running against two different accounts.

### AC-5: Customer MFA Is Never Required At Login Or Payment

1. Run `Customer - Login`.
2. Confirm login returns `200` and session tokens without requiring a TOTP code.
3. Run the current customer payment flow with the same customer token.
4. Confirm no payment route requires `/auth/customers/mfa/verify` before payment can proceed.

## Notes

- No application table, RLS policy, database function, or migration is required for this issue.
- TOTP factors are managed by Supabase Auth MFA, not `staff_profiles` or `customer_profiles`.

# Issue 16 Verification - TOTP Attempt Lockout

Sprint: Sprint 1  
Epic: Epic A-1  
Issue: #16 - refactor(server): TOTP attempt limiting

## What Changed

- Added `public.mfa_lockouts` with one row per Supabase Auth user.
- Enabled RLS so authenticated users can only select their own lockout row.
- Added shared `mfaLockout.service.ts` for check, increment, and reset behavior.
- Wired staff and customer TOTP verify endpoints to the same shared service.
- Invalid TOTP attempts increment the counter. The fifth consecutive failure returns `423 Locked` with retry-after data.
- Successful TOTP verification resets `failed_attempts` to `0`.

## Automated Verification

From `server/`, run:

```powershell
npm.cmd test -- --run src/shared/services/mfaLockout/mfaLockout.service.spec.ts src/features/auth/staff/tests/staffAuth.unit.spec.ts src/features/auth/customers/tests/customerAuth.unit.spec.ts
npm.cmd run typecheck
npm.cmd run lint
```

Expected result:

- The focused Vitest run passes.
- TypeScript exits successfully.
- ESLint exits successfully. Existing `no-console` warnings may still appear in `customerAuth.controller.ts`; there should be no lint errors.

## Supabase Verification

Use the SQL helper in:

`testing/docs/sprints/sprint1/epicA1/issue-16/supabase/issue16.sql`

1. Open the Supabase dashboard.
2. Select the Golden Fur project.
3. In the left sidebar, click **SQL Editor**.
4. Click **New query**.
5. Open `issue16.sql` from this folder and paste its contents into the editor.
6. Click **Run**.
7. Confirm the first result includes `id`, `user_id`, `failed_attempts`, `locked_until`, `last_attempt_at`, and `created_at`.
8. Confirm constraints show `user_id` is unique and references `auth.users(id)`.
9. Confirm `rowsecurity` is `true`.
10. Confirm the only normal client policy is SELECT with `auth.uid() = user_id`; there should be no normal authenticated INSERT or UPDATE policy.

## Postman Verification

Use the Postman collection in:

`testing/docs/sprints/sprint1/epicA1/issue-16/postman/issue16.postman_collection.json`

### Setup

1. Open Postman.
2. Click **Import**.
3. Choose `issue16.postman_collection.json`.
4. Open the imported collection named **Issue 16 - TOTP Attempt Lockout**.
5. Open the **Variables** tab.
6. Set `base_url` to the local API, usually `http://localhost:3000`.
7. Set `staff_username` and `staff_password` to a staff account with an enrolled TOTP factor.
8. Set `customer_email` and `customer_password` to a customer account with an enrolled TOTP factor.
9. Leave `totp_code` as `000000` for the lockout test, unless that code is accidentally valid at the moment.
10. Click **Save**.

### AC-3 and AC-5: Staff Lockout

1. Run `Staff - Login`.
2. Confirm the response is `200 OK`.
3. Confirm the collection variable `staff_access_token` is now filled with the response `access_token`.
4. Run `Staff - TOTP Verify Invalid Code` four times.
5. Confirm each of the first four responses is `401` with `{ "error": "Invalid code" }`.
6. Run `Staff - TOTP Verify Invalid Code` a fifth time.
7. Confirm the response is `423 Locked`.
8. Confirm the response includes `retry_after_seconds` and `locked_until`.
9. Immediately run `Staff - TOTP Verify Invalid Code` again.
10. Confirm it still returns `423 Locked` without a normal pass/fail result.

### AC-6: Customer Uses The Same Lockout Behavior

1. Run `Customer - Login`.
2. Confirm the response is `200 OK`.
3. Confirm the collection variable `customer_access_token` is now filled with the response `access_token`.
4. Run `Customer - TOTP Verify Invalid Code` four times.
5. Confirm each of the first four responses is `401` with `{ "error": "Invalid code" }`.
6. Run `Customer - TOTP Verify Invalid Code` a fifth time.
7. Confirm the response is `423 Locked`.
8. Confirm the response includes `retry_after_seconds` and `locked_until`.

### AC-4: Successful Verify Resets Attempts

1. Use a staff or customer account that is not currently locked.
2. Send one invalid TOTP code and confirm `401 Invalid code`.
3. Generate a fresh valid 6-digit TOTP code from the authenticator app for that same account.
4. Replace `totp_code` with the valid code in the collection variables.
5. Run the matching verify request before the code expires.
6. Confirm the response is `200 OK`.
7. In Supabase SQL Editor, run:

```sql
select failed_attempts, locked_until
from public.mfa_lockouts
where user_id = '<the auth.users id for the tested account>';
```

8. Confirm `failed_attempts` is `0` and `locked_until` is empty.

## Notes

- Staff and customers both authenticate through Supabase Auth, so the lockout row is keyed by `auth.users.id`.
- Do not paste Supabase service-role, anon, or project API keys into Postman token variables. Use only `access_token` values returned by the login requests.

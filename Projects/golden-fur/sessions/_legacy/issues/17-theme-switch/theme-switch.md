# Issue 17 Verification - Staff/Customer Theme Switch

Sprint: Sprint 1
Epic: Epic A-1 Addendum
Issue: #17 - refactor(client/server): staff/customer theme switch (theme_preference + ThemeToggle)

## What Changed

- Added `theme_preference` (`text`, `CHECK IN ('light','dark','system')`, default `'system'`) to both `staff_profiles` and `customer_profiles`. No new RLS migration - the existing self-update policies already cover the new column.
- `ThemeProvider` still applies the role-based palette (`data-theme='staff'/'customer'`) automatically by route, unchanged. It now also resolves a `light`/`dark`/`system` mode, fetched for the signed-in user, and applies the resolved light/dark value as a `data-color-mode` attribute on `<html>`.
- `themeContext.ts`'s `ThemeMode` is now `{ role: 'staff' | 'customer'; mode: 'light' | 'dark' | 'system' }`, exposed via context alongside a `setMode` function.
- Added `ThemeToggle`, a reusable light/dark/system switch control that reads/writes the theme via context.
- Added `client/src/shared/api/preferences.api.ts`: reads `theme_preference` directly via the Supabase client (covered by the existing self-select RLS policy), and PATCHes it through the new server routes when the user changes it.
- Added `PATCH /auth/staff/preferences` and `PATCH /auth/customers/preferences`, both authenticated by `jwtMiddleware` and updating only `theme_preference` on the caller's own profile row (via a per-request Supabase client scoped to the caller's JWT, so the existing self-update RLS policy - not a service-role bypass - is what allows the write).

## Known Gap / Needs Follow-up

- **AC-3 (ThemeToggle in navigation):** The staff/customer authenticated app shell (`Navbar`, `HomePage`, etc.) does not exist yet in this codebase - those files are still empty placeholders reserved for a later epic. `ThemeToggle` is built, functional, and exported from `client/src/shared/components/ThemeToggle/`, but it is **not yet mounted into a real navigation bar**, since none exists to mount it into. This matches the issue's own note that placement is unconfirmed with James in Figma. Once the nav shell lands, drop `<ThemeToggle />` into it - no further wiring should be needed.
- Migration is numbered `20260702018` rather than the `20260702017` named in the issue doc - `016`/`017` were already consumed on disk by Issue #16's `mfa_lockouts` migrations, so this issue's migration was bumped to the next free number.

## Automated Verification

From `server/`, run:

```powershell
npm.cmd run typecheck
npm.cmd run lint
```

From `client/`, run:

```powershell
npm.cmd test
npm.cmd run lint
```

Expected result:

- Both TypeScript checks exit successfully.
- Both ESLint checks exit successfully (server keeps its two pre-existing `no-console` warnings in `customerAuth.controller.ts`/`staffAuth.controller.ts`; there should be no errors).
- The full client Vitest run passes, including the existing `ThemeProvider.spec.ts`, unmodified.

## Supabase Verification

Use the SQL helper in:

`testing/docs/sprints/sprint1/epicA1/issue-17/supabase/issue17.sql`

1. Open the Supabase dashboard.
2. Select the Golden Fur project.
3. In the left sidebar, click **SQL Editor**.
4. Click **New query**.
5. Open `issue17.sql` from this folder and paste its contents into the editor.
6. Click **Run**.
7. Confirm the first result has one row per table (`staff_profiles`, `customer_profiles`) with `data_type = text`, `is_nullable = NO`, and `column_default` containing `'system'`.
8. Confirm the second result shows both `..._theme_preference_check` constraints, each referencing `theme_preference` and the three allowed values (`light`, `dark`, `system`).
9. Confirm the last result (policy listing) only shows the pre-existing policies (e.g. "Staff can update their own profile", "Customers can update their own profile.") - no new policy rows were added by this migration.

### Manual constraint check (optional)

In the SQL Editor, run the following against a real row (replace the id), and confirm it errors with a check-constraint violation:

```sql
update public.staff_profiles set theme_preference = 'neon' where id = '<a staff id>';
```

## Postman Verification

Use the Postman collection in:

`testing/docs/sprints/sprint1/epicA1/issue-17/postman/issue17.postman_collection.json`

### Setup

1. Open Postman.
2. Click **Import**.
3. Choose `issue17.postman_collection.json`.
4. Open the imported collection named **Issue 17 - Theme Switch Preferences**.
5. Open the **Variables** tab.
6. Set `base_url` to the local API, usually `http://localhost:3000`.
7. Set `staff_identifier` and `staff_password` to a valid staff account (username or email both work).
8. Set `customer_email` and `customer_password` to a valid customer account.
9. Click **Save**.

### AC-4: Staff Preferences Persist

1. Run `Staff - Login`.
2. Confirm the response is `200 OK`.
3. Confirm the collection variable `staff_access_token` is now filled in.
4. Run `Staff - Update Preferences (dark)`.
5. Confirm the response is `200 OK` with body `{ "theme_preference": "dark" }`.
6. In Supabase SQL Editor, run `select theme_preference from public.staff_profiles where id = '<that staff id>';` and confirm it now returns `dark`.

### AC-1/AC-4: Invalid Values Are Rejected

1. Run `Staff - Update Preferences (invalid value)`.
2. Confirm the response is `400` with an `error` field - the `neon` value is rejected before it ever reaches the database CHECK constraint.

### Auth Is Required

1. Run `Staff - Update Preferences (no token)`.
2. Confirm the response is `401 Unauthorized`.

### AC-4: Customer Preferences Persist (mirrors staff)

1. Run `Customer - Login`.
2. Confirm the response is `200 OK` and `customer_access_token` is filled in.
3. Run `Customer - Update Preferences (light)`.
4. Confirm the response is `200 OK` with body `{ "theme_preference": "light" }`.
5. Run `Customer - Update Preferences (invalid value)` and confirm `400`.
6. Run `Customer - Update Preferences (no token)` and confirm `401`.

## Manual Client Verification

Since there is no staff/customer app shell yet to click a real toggle in, verify the client wiring directly:

1. From `client/`, run `npm.cmd run dev` and open the printed local URL.
2. Sign in as a staff user (via `/staff/login`) or a customer (via `/customers/login`), whichever exists in your test data.
3. Open the browser DevTools console and confirm no errors were logged by `ThemeProvider` on load.
4. In the **Elements/Inspector** tab, confirm `<html>` has both a `data-theme` attribute (`staff` or `customer`, matching the route) and a `data-color-mode` attribute (`light` or `dark`) - confirming AC-2 and AC-5 together (mode layered on top, palette unchanged).
5. In the DevTools console, run:
   ```js
   window.matchMedia("(prefers-color-scheme: dark)").matches;
   ```
   and confirm `data-color-mode` matches this value when no explicit preference has been set yet (mode defaults to `system`).

## Notes

- Staff and customers both use the same shape of endpoint (`PATCH .../preferences`) and the same client helper (`preferences.api.ts`), keyed off the `role` passed into `ThemeProvider` - no parallel implementation per role.
- The PATCH handlers use a per-request Supabase client built from the caller's own `Authorization` header (same `getUserClient` pattern already used in `staffAuth.controller.ts`/`customerAuth.controller.ts`), so the write is authorized by the existing self-update RLS policy rather than a service-role bypass.

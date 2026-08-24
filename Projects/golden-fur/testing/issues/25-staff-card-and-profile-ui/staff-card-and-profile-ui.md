# Issue #25 Verification: StaffCard Component and Staff Profile UI

**Issue:** #25 — feat(staff): StaffCard component and staff profile UI
**Owner:** James
**Branch:** `feat/staff-card-and-profile-ui`
**Base:** `dev`
**Depends on:** #22 (profile CRUD backend), #23 (avatar upload backend), #24 (unavailability block backend) merged
**Sprint:** Sprint 1 — Epic B, M01 Staff Auth & Access Control

## Overview

Adds the first staff-facing profile UI: a self-service `StaffProfilePage` (avatar, contact fields, communication preference, Unavailability Block management) plus the reusable `StaffCard`, `AvatarUploader`, and `UnavailabilityBlockForm` building blocks that Issue #26's admin staff list will reuse without modification. All new client code talks to the `#22–#24` REST endpoints through a new `client/src/features/staff/api/staff.api.ts` wrapper; no server code changes.

## What Changed

- **Added** `client/src/features/staff/staff.types.ts` — client-side mirrors of the server's `StaffProfile`, `UnavailabilityBlock`, and their update/create payload shapes.
- **Added** `client/src/features/staff/modules/validators/staff.validator.ts` (+ spec) — `zod` schemas mirroring the server validators: profile update fields, an avatar file mime/size guard, and the unavailability block create payload (quick-action XOR a valid start/end range).
- **Added** `client/src/features/staff/api/staff.api.ts` (+ spec) — `getStaffProfile()`, `updateStaffProfile()`, `uploadAvatar()`, `listUnavailabilityBlocks()`, `createUnavailabilityBlock()`, `cancelUnavailabilityBlock()`, `listStaff()`. All follow the existing `fetch` + `{ data, error }` result pattern used by `mfa.api.ts`/`preferences.api.ts`. `staff.routes.ts` is mounted at the server root (not under `/auth`), so these call `${API_BASE_URL}/staff/...` directly.
- **Moved + generalized** `client/src/features/staff/components/UnavailabilityStatusBadge/` → `client/src/features/staff/components/badges/UnavailabilityBlockBadge/UnavailabilityBlockBadge.tsx` (+ module CSS, + spec). Behavior is unchanged (still a direct Supabase read, matching the RLS fix from issue #15) but now: reads `end_time` so the label reads `Unavailable until HH:MM` instead of a generic "unavailable" string, is styled from CSS module tokens (`--color-status-neutral-*`, `--color-warning-*`, `--radius-pill`) instead of inline styles, and accepts an optional `refreshKey` prop so callers can force a re-check after creating/cancelling a block.
- **Modified** `client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx` — updated the import/usage to the moved, renamed badge.
- **Added** `client/src/features/staff/components/forms/AvatarUploader/` — dropzone + file-picker upload with client-side mime/size validation, an uploading spinner (`.animate-spin`), a fade-in on the new avatar (`.animate-fade-in`), and an inline error on validation/server failure.
- **Added** `client/src/features/staff/components/forms/UnavailabilityBlockForm/` — a quick-action button ("Unavailable until end of shift") and a custom start/end/reason form. Takes a `staffId` prop rather than always assuming "me", so #26 can pass a different target for the Admin-on-behalf-of case without modification.
- **Added** `client/src/features/staff/components/cards/StaffCard/` — presentational card (avatar or initials fallback, display name, role badge, optional branch name, `UnavailabilityBlockBadge`) driven only by a `staffId` + already-fetched `profile` prop, so #26's admin list can render it directly from a `listStaff()` response.
- **Added** `client/src/features/staff/pages/StaffProfilePage/` — the self-service profile page: loads the logged-in staff member's profile via `getStaffProfile()`, renders `AvatarUploader`, an editable contact-info form (`updateStaffProfile()`), the `UnavailabilityBlockBadge`, and the `UnavailabilityBlockForm`.
- **Added** `client/src/features/staff/staff.routes.ts` and **modified** `client/src/routes.tsx` — registers `/staff/profile` behind the existing `StaffAuthGuard`, alongside `staffAuthRoutes`. (Not in the issue's own Affected Files table, but required for `StaffProfilePage` to be reachable/verifiable — `staff.routes.ts` is explicitly named in the Epic B design doc's Files sheet as owned by this feature.)
- **Modified** `client/src/features/auth/staff/staffAuth.routes.ts` — added a "My Profile" link next to the existing "Settings" link on the placeholder staff dashboard, for discoverability during manual verification.
- **Modified** `client/src/styles/variables/typography.css` — added the 4 Epic B semantic tokens the design sheet calls for but that were missing from the codebase: `--text-heading-lg` (27px), `--text-heading-md` (25px), `--text-button` (19px), `--text-label` (12px).
- **Modified** `client/src/styles/variables/spacing.css` — added the 3 new layout tokens from the design sheet: `--staff-card-min-width` (260px), `--avatar-size-card` (48px), `--avatar-size-profile` (96px).
- **Fixed** `client/vite.config.ts` — added a dev-server proxy entry for `/staff` (see "Bug fix: profile page stuck on 'Loading your profile...'" below).
- **Hardened** `client/src/features/staff/api/staff.api.ts` — every success-path `response.json()` call now goes through a `parseBody()` helper that catches parse failures and returns `{ data: null, error }` instead of throwing, so a bad response can no longer leave a caller's loading state stuck forever.

### Design sheet compliance

Per `Sprint1-EpicB-Design.xlsx` → Styles: no new color tokens were introduced. `StaffCard` uses `--color-surface` / `--color-border` / `--radius-sm` / `--shadow-card`; `AvatarUploader` uses `--color-accent-gold-primary` / dashed `--color-border` / `--color-error-bg`/`-text`; `UnavailabilityBlockForm` uses `--color-accent-gold-primary` and the shared `--color-surface`/`--color-border` input pattern from `StaffLoginForm.module.css`; `UnavailabilityBlockBadge` uses `--color-status-neutral-*` / `--color-warning-*` / `--radius-pill`.

### Scope notes

- No server code changed — this issue is entirely `client/`.
- The badge's data source is unchanged from issue #15 (direct Supabase read against `staff_unavailability_blocks`, relying on the RLS fix from that issue). It was **not** switched to the new `staff.api.ts` REST wrapper, to avoid introducing a real `fetch` dependency into `StaffAuthGuard`'s render path (which has no network mocking in its existing test suite).
- `StaffCard` accepts an optional `branchName` prop (not in the issue's literal AC-5 wording) since the design sheet calls for a branch line on the card; #26 can pass a resolved name once it has branch data. Omitted, the card simply doesn't render a branch line.

## Bug fix: profile page stuck on "Loading your profile..."

**Symptom:** `/staff/profile` rendered the badge/shell but hung forever on "Loading your profile...". DevTools showed `406` noise from an unrelated theme-preference query, then repeated `Uncaught (in promise) SyntaxError: Unexpected token '<', "<!doctype "... is not valid JSON` pointing at the profile page.

**Root cause:** `client/vite.config.ts`'s dev proxy only forwarded `/auth/customers` and `/auth/staff` to the API server on port 3000. `staff.api.ts` calls `${API_BASE_URL}/staff/:id` with no `/auth` prefix (per its own comment — `staff.routes.ts` is mounted at the server root), and `VITE_API_BASE_URL` is unset, so those requests are relative and depend entirely on the dev proxy. With no matching proxy rule, Vite's SPA fallback served `index.html` (status `200`) for every `/staff/:id` fetch. `getStaffProfile()`'s success path did `await response.json()` with no `.catch`, so parsing the HTML as JSON threw inside an unawaited `.then()` chain — an unhandled rejection that never reached `setIsLoading(false)`, leaving the page stuck.

**Fix:**

1. `client/vite.config.ts` — added a `/staff` proxy entry to `http://localhost:3000`. Because the client also has a page route at `/staff/profile`, the entry uses a `bypass` function that lets browser navigations (`Accept: text/html`) fall through to the SPA, while `fetch`/XHR calls (the app's `Accept` header doesn't request HTML) get proxied to the API.
2. `client/src/features/staff/api/staff.api.ts` — added `parseBody()` so a non-JSON success response resolves to `{ data: null, error: 'Request failed...' }` instead of throwing, matching the existing `parseError()` pattern for non-2xx responses. This is defense-in-depth: it stops this exact "silently stuck loading forever" failure mode from recurring if the API is ever unreachable for any other reason.

**Verified:** with the dev servers running, logged in as a seeded account (`makati.groomer1@goldenfur.com`) and calling `GET http://localhost:5173/staff/<uid>` with the session's bearer token now returns `200 application/json` with the real profile body (previously returned the SPA's `index.html`). A direct navigation to `http://localhost:5173/staff/profile` still correctly returns the SPA shell.

**Unrelated, not fixed here (pre-existing, out of scope for #25):**

- `406` on `staff_profiles`/`customer_profiles` `theme_preference` selects (`client/src/shared/api/preferences.api.ts`, `ThemeProvider`) — cosmetic console noise only; `getThemePreference()` already treats any error as "no stored preference" and falls back to `system`, so it doesn't block rendering.
- A `400` on `POST /auth/staff/mfa/enroll` may appear if you test with an account that has a stale/partial TOTP factor from a previous enroll attempt — not something #25's changes touch.

## Automated Verification

From the repository root in PowerShell:

```powershell
npm --prefix client test -- --run
npm --prefix client run build
npm --prefix client run lint
```

Expected result: all 30 client Vitest files / 100 tests pass, `tsc -b && vite build` completes with no type errors, and `eslint .` reports 0 problems.

To run just the files touched by this issue:

```powershell
npm --prefix client test -- --run src/features/staff
```

## Structural Verification

1. Confirm the new/moved feature files exist:

   ```powershell
   Get-ChildItem client/src/features/staff -Recurse -File
   ```

   Expected: `staff.types.ts`, `staff.routes.ts`, `api/staff.api.ts` (+ spec), `modules/validators/staff.validator.ts` (+ spec), `components/badges/UnavailabilityBlockBadge/*`, `components/forms/AvatarUploader/*`, `components/forms/UnavailabilityBlockForm/*`, `components/cards/StaffCard/*`, `pages/StaffProfilePage/*`. No `components/UnavailabilityStatusBadge/` folder remains.

2. Confirm `StaffAuthGuard` points at the new badge location:

   ```powershell
   Select-String -Path client/src/features/auth/staff/guards/StaffAuthGuard/StaffAuthGuard.tsx -Pattern "UnavailabilityBlockBadge"
   ```

   Expected: two matches (the import and the JSX usage).

3. Confirm the new design tokens exist:

   ```powershell
   Select-String -Path client/src/styles/variables/spacing.css,client/src/styles/variables/typography.css -Pattern "staff-card-min-width|avatar-size-card|avatar-size-profile|text-heading-lg|text-heading-md|text-button|text-label"
   ```

   Expected: all 7 tokens found.

## Manual Browser Verification

This requires a running server (`#22`–`#24` merged and reachable) and Supabase project with `.env`/`.env.local` values set for both `client` (`VITE_API_BASE_URL`, `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) and `server`. Use a seeded staff account (any role) with a known username/password — see issue #22's doc if you need to locate or create one in Supabase Studio's **Table Editor → staff_profiles**.

### Step 1: Start the server and client

```powershell
npm --prefix server run dev
```

In a second terminal:

```powershell
npm --prefix client run dev
```

Open the local Vite URL shown in the terminal, usually `http://localhost:5173`.

### Step 2: Sign in and open the profile page

1. Go to `/staff/login` and sign in with a seeded staff account.
2. On the staff dashboard placeholder, click **My Profile** (or navigate directly to `/staff/profile`).

Expected result:

- The page shows a rounded panel (matches `--radius-xl` / `--shadow-card`) with an avatar (or a "+" placeholder), the staff member's display name, role, an availability badge, an editable contact-info form, and an "Unavailability Block" section. — **AC-1**

### Step 3: Edit and save profile fields

1. Change the **Display name** field (and optionally phone/emergency contact/communication preference).
2. Click **Save Profile**.

Expected result:

- A "Profile saved." confirmation appears and the heading above the form updates immediately to the new name, with no page reload. — **AC-2**
- In Supabase Studio (**Table Editor → staff_profiles**), the row's `display_name` (and any other edited fields) reflect the change.

### Step 4: Upload an avatar

1. Click **Upload avatar** and pick a PNG/JPEG/WEBP under 5MB.

Expected result:

- A brief spinner overlay shows while uploading, then the new image fades in and replaces the placeholder. — **AC-3**

2. Try uploading an unsupported file (e.g. a `.gif` or a file over 5MB, renamed with a `.png` extension won't trigger the mime check — use an actual oversized/unsupported file).

Expected result:

- An inline red error message appears (e.g. "Unsupported file type...") and no request is sent (check the Network tab — no `POST /staff/:id/avatar` call). — **AC-3**

### Step 5: Create an Unavailability Block

1. In the "Unavailability Block" section, click **Unavailable until end of shift**.

Expected result:

- A "Unavailability block created." message appears, and the badge near the top of the identity section updates to `Unavailable until HH:MM` without a manual refresh. — **AC-4**

2. Try creating a second overlapping block (quick action again, or a custom range that overlaps).

Expected result:

- An inline error appears with the server's overlap message (`Block overlaps an existing unavailability block`).

3. To confirm the block was actually persisted, open **Table Editor → staff_unavailability_blocks** in Supabase Studio and find the row for this `staff_id`.

### Step 6: Confirm StaffCard renders independently

`StaffCard` has no page of its own yet (it's wired into an admin list in #26), so confirm it via its automated spec instead:

```powershell
npm --prefix client test -- --run src/features/staff/components/cards/StaffCard/StaffCard.spec.ts
```

Expected result: all `StaffCard` tests pass, including the one asserting it renders correctly from only a `staffId` + `profile` object (no page/route dependency). — **AC-5**

## Acceptance Criteria Checklist

- [x] **AC-1:** `StaffProfilePage` renders the logged-in staff member's avatar, display name, contact fields, and communication preference, sourced from `getStaffProfile()` — `StaffProfilePage.spec.ts` ("renders the avatar, display name, contact fields, and comms preference"); manual Step 2.
- [x] **AC-2:** Editing and saving a field calls `updateStaffProfile()` and reflects the update in the UI without a full page reload — `StaffProfilePage.spec.ts` ("saving an edited field..."); manual Step 3.
- [x] **AC-3:** `AvatarUploader` shows upload progress, then the new avatar, on successful upload; shows an inline error on validation failure — `AvatarUploader.spec.ts`; manual Step 4.
- [x] **AC-4:** `UnavailabilityBlockForm`'s quick-action button creates a block via #24's API and `UnavailabilityBlockBadge` updates to reflect it without a manual refresh — `UnavailabilityBlockForm.spec.ts` + `UnavailabilityBlockBadge.spec.ts` (`refreshKey` re-check test); manual Step 5.
- [x] **AC-5:** `StaffCard` renders correctly with only `staffId` + fetched profile data as input, independent of `StaffProfilePage` — `StaffCard.spec.ts`; manual Step 6.

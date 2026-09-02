# Issue #45 Verification: Admin Services List + Create/Edit Form UI

**Issue:** #45 — feat(maintenance): admin services list + create/edit form UI
**Owner:** James
**Branch:** `feat/admin-services-ui`
**Base:** `dev`
**Depends on:** #40 merged (services CRUD backend)
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

> Delivered in the same working session as #46 (`feat/package-builder-ui`).
> #46 depends on #45's shared components, so if the two are split into
> separate PRs, this branch must merge first. See
> `testing/docs/issues/46-package-builder-ui/` for #46's own doc.

## Overview

Adds `AdminServicesPage` at `/staff/admin/maintenance/services` — a
category/branch/status-filterable list of every service with per-row branch
availability toggles (Makati / Southwoods), plus a create/edit form that
includes the Grooming-only size×coat pricing matrix editor. Also lands the
two components the rest of Epic A reuses (`StatusBadge`, `ToggleSwitch`) and
the typed API client for the #40–#41 maintenance endpoints.

## What Changed

- **Added** `client/src/features/maintenance/maintenance.types.ts` — client
  mirrors of the server's `Service`/`ServicePricingTier`/
  `ServiceBranchAvailability`/`Package` shapes and the #40/#41 validator
  payloads. Not in the issue's Affected Files table, but every feature folder
  keeps its types at the root (`staff.types.ts`, `customer.types.ts`), so
  inlining these into the API file would break the established convention.
- **Added** `client/src/features/maintenance/api/maintenance.api.ts` — typed
  fetch wrappers for `GET/POST/PATCH /maintenance/services`,
  `PATCH /maintenance/services/:id/branch-availability`, and the
  `/maintenance/packages` endpoints (shared with #46), following
  `staff.api.ts`'s `{ data, error }` result shape. Also exports
  `listBranches()` — see scope note below.
- **Added** `client/src/features/maintenance/components/shared/StatusBadge/`
  (`.tsx`, `.module.css`, `.spec.ts`) — Active/Inactive pill on the new
  `--color-active-*` / `--color-inactive-*` tokens. Reused by #46–#48.
- **Added** `client/src/features/maintenance/components/shared/ToggleSwitch/`
  (`.tsx`, `.module.css`, `.spec.ts`) — accessible `role="switch"` toggle
  used for branch availability here and enable/disable toggles in #46–#48.
- **Added**
  `client/src/features/maintenance/components/ServicePricingTierEditor/`
  (`.tsx`, `.module.css`, `.spec.ts`) — 4×2 (S/M/L/XL × SC/LC) price grid.
  Emits a sparse tier list; a cleared cell drops out of the payload. Only
  rendered when the form's category is Grooming — hidden entirely (not
  disabled) otherwise, per the issue's dev notes.
- **Added** `client/src/features/maintenance/pages/AdminServicesPage/`
  (`.tsx`, `.module.css`, `.spec.ts`) — the page itself.
- **Added** `client/src/features/maintenance/maintenance.routes.tsx` —
  registers `/staff/admin/maintenance/services` (and #46's
  `/staff/admin/maintenance/packages`) behind `StaffAuthGuard`.
- **Modified** `client/src/routes.tsx` — mounts `maintenanceRoutes`.
- **Modified** `client/src/features/auth/staff/staffAuth.routes.ts` — added
  "Services (Maintenance)" / "Packages (Maintenance)" links to the
  placeholder staff dashboard for discoverability during manual verification
  (same precedent as #26's "Staff Directory" link addition).
- **Modified** `client/src/styles/tokens.css` — added the Styles sheet's new
  color pair to **both** themes: `--color-active-bg/-text` and
  `--color-inactive-bg/-text` (light values from the Design workbook; dark
  values derived from the existing success/neutral pairs).
- **Modified** `client/src/styles/variables/spacing.css` — added the two new
  layout tokens `--admin-table-row-min-height: 56px` and
  `--maintenance-form-max-width: 640px`.

### Scope notes / deviations from the issue spec

- **Branch toggle labels are real names now.** No Express endpoint exposes
  branches (#26 shipped with `Branch <id-prefix>` labels for this reason),
  but `branches` RLS grants SELECT to every authenticated user, so
  `maintenance.api.ts`'s `listBranches()` reads `id, name` directly through
  the shared Supabase client — the same client-side pattern
  `UnavailabilityBlockBadge` already uses. The Makati/Southwoods toggles the
  issue asks for are therefore labeled from live data, not hardcoded. If the
  branch lookup fails, the page still works — only toggle labels degrade.
- **Role gate is in-page, not in the route.** `StaffAuthGuard` handles
  authentication/MFA/session-timeout; the Admin/Superadmin-only check
  resolves the viewer's role from their own row in `GET /staff` and
  redirects others to `/staff/profile` — identical to
  `AdminStaffListPage`/`AdminCustomerListPage` (AC-5's "consistent with the
  pattern used elsewhere").
- **A Status filter (Active only / Inactive only / All) was added** beyond
  AC-1's category/branch filters. The list must show inactive rows somewhere
  (the page is where you *re*activate a service), and AC-4 needs an "active
  services filter view" for the deactivated row to disappear from —
  defaulting the filter to **Active only** satisfies both.
- **Component `.module.css` + `.spec.ts` files** were added even where the
  issue's Affected Files table lists only the `.tsx` — every existing
  component in the repo carries both, and the table is abbreviated the same
  way Sprint 1 issue tables were.

## Automated Verification

From the repository root in PowerShell:

```powershell
npm --prefix client test
npm --prefix client run lint
npm --prefix client run build
```

Expected: **51 test files / 201 tests pass** (16 of them from this issue:
`AdminServicesPage` 7, `ServicePricingTierEditor` 4, `ToggleSwitch` 3,
`StatusBadge` 2), ESLint reports 0 problems, and `tsc -b && vite build`
completes without errors.

To run only this issue's files:

```powershell
npm --prefix client test -- --run src/features/maintenance/pages/AdminServicesPage src/features/maintenance/components/ServicePricingTierEditor src/features/maintenance/components/shared
```

Expected: 4 files / 16 tests pass, named after the ACs they cover.

## Structural Verification

1. New files exist:

   ```powershell
   Get-ChildItem client/src/features/maintenance -Recurse -File | Select-Object FullName
   ```

   Expected: `maintenance.types.ts`, `maintenance.routes.tsx`,
   `api/maintenance.api.ts`, `components/ServicePricingTierEditor/*` (3),
   `components/ServiceMultiSelect/*` (3, from #46),
   `components/shared/StatusBadge/*` (3), `components/shared/ToggleSwitch/*`
   (3), `pages/AdminServicesPage/*` (3), `pages/AdminPackageBuilderPage/*`
   (3, from #46).

2. Route is registered:

   ```powershell
   Select-String -Path client/src/routes.tsx,client/src/features/maintenance/maintenance.routes.tsx -Pattern "maintenanceRoutes|maintenance/services"
   ```

   Expected: `routes.tsx` imports/mounts `maintenanceRoutes`;
   `maintenance.routes.tsx` registers `/staff/admin/maintenance/services`.

3. New style tokens exist in both themes:

   ```powershell
   Select-String -Path client/src/styles/tokens.css -Pattern "color-active-bg|color-inactive-bg"
   Select-String -Path client/src/styles/variables/spacing.css -Pattern "admin-table-row-min-height|maintenance-form-max-width"
   ```

   Expected: two matches each in `tokens.css` (customer + staff themes); two
   matches in `spacing.css`.

## Manual Browser Verification

Requires the local Supabase stack, the API server, and the Vite client all
running, with the module-1 and module-3 seeds applied.

### Step 0: Start everything

1. Start Supabase (Docker Desktop must be running first):

   ```powershell
   npx supabase start
   ```

   If you're unsure the seeds are applied (or want a clean slate), reset —
   **this wipes local data** and re-runs every migration + seed:

   ```powershell
   npx supabase db reset
   ```

2. In one terminal, start the API server:

   ```powershell
   npm --prefix server run dev
   ```

3. In a second terminal, start the client:

   ```powershell
   npm --prefix client run dev
   ```

4. Open the URL Vite prints (usually `http://localhost:5173`).

**Seeded accounts** (all passwords are `password123`):

- Admin: `makati.admin1@goldenfur.com`
- Non-admin: `makati.groomer1@goldenfur.com`

> Admin/Superadmin logins enforce mandatory MFA: on first login a "Set up
> multi-factor authentication" popup appears. Scan the QR code with any
> authenticator app (Google Authenticator, Authy, …) and enter the 6-digit
> code once — subsequent logins just ask for the current code.

### Step 1: Route guard (AC-5)

1. Go to `http://localhost:5173/staff/login` and sign in as the **Groomer**.
2. Navigate directly to
   `http://localhost:5173/staff/admin/maintenance/services`.

Expected: immediately redirected to `/staff/profile`; the services list never
renders. — **AC-5**

3. Sign out, sign in as the **Admin**, and click **Services (Maintenance)**
   on the staff dashboard (`/staff`), or navigate to the URL directly.

Expected: the Services page loads and stays. — **AC-5**

### Step 2: List + filters (AC-1)

Expected on load (with the module-3 seed):

- 21 service rows, each showing **name**, a gold **category badge**
  (Grooming/Hotel/Daycare/Veterinary), **PHP base price**, an **Active**
  StatusBadge, and two labeled toggles (**Makati**, **Southwoods**), both on.
- Three filters above the list: **Category**, **Branch**, **Status**
  (defaulting to _Active only_).

1. Set **Category** to `Veterinary`.

Expected: only the 6 Veterinary rows remain; no page reload (the browser
DevTools **Network** tab shows no new document request). — **AC-1**

2. Set **Category** back to `All categories`, then set **Branch** to
   `Southwoods`.

Expected: only services with their Southwoods toggle on remain (all 21,
until you toggle one off in Step 4). — **AC-1**

### Step 3: Create a Grooming service with the pricing matrix (AC-2)

1. Click **New service**.
2. Expected: the form opens with Category `Grooming` and the
   **Size & coat pricing matrix (Grooming)** grid visible — 4 weight rows
   (S/M/L/XL) × 2 coat columns (Short Coat SC / Long Coat LC).
3. Change **Category** to `Hotel`.

Expected: the matrix disappears entirely (it is not just disabled), and a
**Duration** field appears instead. Switch back to `Grooming` — the matrix
returns. — **AC-2**

4. Fill in: Name `Flea Treatment`, Base price `400`, and all 8 matrix cells
   (e.g. 400/450 · 500/550 · 600/650 · 700/750).
5. Click **Save service**.

Expected:

- A "Service created." banner appears and the new row shows in the list with
  both branch toggles on (the backend defaults both branches to available).
- In Supabase Studio (`http://127.0.0.1:54323` → **Table Editor** →
  `service_pricing_tiers`), 8 new rows exist for the new service's id, one
  per (weight_class, coat_type) pair. — **AC-2**

6. Click **Edit** on the new row, change a single matrix cell (e.g. XL/LC to
   `800`), and save.

Expected: "Service updated." — and in Supabase Studio that one tier row's
price changed while the other 7 are untouched (the PATCH upserts individual
cells; the full set is not resubmitted). — **AC-2**

### Step 4: Branch availability toggles (AC-3)

1. On any Grooming row, click the **Southwoods** toggle.

Expected:

- The toggle flips off instantly with no page reload.
- In Supabase Studio → `service_branch_availability`, that (service, branch)
  row now has `is_available = false`.
- With the **Branch** filter set to `Southwoods`, the row disappears from
  the list (it's no longer offered there). — **AC-3**

2. Toggle it back on. Expected: row returns under the Southwoods filter.

### Step 5: Deactivate / reactivate (AC-4)

1. With **Status** on _Active only_, click **Deactivate** on the `Flea
Treatment` row you created.

Expected: a "Service deactivated." banner, and the row vanishes from the
list without a page reload (it no longer matches _Active only_). — **AC-4**

2. Set **Status** to _Inactive only_.

Expected: the row reappears with an **Inactive** StatusBadge and a
**Reactivate** button. — **AC-4**

3. Click **Reactivate** and set **Status** back to _Active only_.

Expected: the row is back with an **Active** badge.

## Acceptance Criteria Checklist

- [x] **AC-1:** List renders all services, filterable by category and
      branch, each row showing name, category badge, base price, and a
      StatusBadge — `AdminServicesPage.spec.ts` (two AC-1 tests); manual Step 2.
- [x] **AC-2:** Create/edit form saves `base_price`, `category`, and (for
      Grooming only) the full size×coat matrix via `ServicePricingTierEditor`,
      which is hidden for other categories — `AdminServicesPage.spec.ts` (two
      AC-2 tests) + `ServicePricingTierEditor.spec.ts`; manual Step 3.
- [x] **AC-3:** Per-branch availability toggles update immediately without
      a full page reload — `AdminServicesPage.spec.ts` (AC-3 test); manual
      Step 4.
- [x] **AC-4:** Deactivating flips the StatusBadge and removes the row from
      the active-only view without a reload — `AdminServicesPage.spec.ts`
      (AC-4 test); manual Step 5.
- [x] **AC-5:** Non-Admin/Superadmin users cannot reach the page —
      `AdminServicesPage.spec.ts` (AC-5 test); manual Step 1.

No Postman collection or SQL file for this issue: it adds no API route and
no DB object — the endpoints it consumes are covered by
`testing/docs/issues/40-services-crud-backend/`.

# Issue #46 Verification: Package Builder UI

**Issue:** #46 — feat(maintenance): package builder UI
**Owner:** James
**Branch:** `feat/package-builder-ui`
**Base:** `dev`
**Depends on:** #41 (packages CRUD backend), #45 (admin services UI —
StatusBadge/ToggleSwitch + maintenance API client) merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

> Delivered in the same working session as #45 (`feat/admin-services-ui`).
> This issue reuses #45's `StatusBadge`, `maintenance.api.ts`, and
> `maintenance.routes.tsx`, so #45 must merge first if the two ship as
> separate PRs. See `testing/docs/issues/45-admin-services-ui/` for #45.

## Overview

Adds `AdminPackageBuilderPage` at `/staff/admin/maintenance/packages` — a
branch-filterable package list plus a builder form that requires picking a
branch first, then multi-selecting two or more of that branch's available
services and setting a bundled price that is deliberately independent of the
services' price sum. Also lands `ServiceMultiSelect`, the generic
multi-select reused by #47 (promo scope) and #48 (discount scope).

## What Changed

- **Added**
  `client/src/features/maintenance/components/ServiceMultiSelect/`
  (`.tsx`, `.module.css`, `.spec.ts`) — checkbox multi-select. Props are
  deliberately generic per the issue's dev notes: `options: {id, label,
sublabel?}[]`, `selectedIds: string[]`, `onChange(ids)` — nothing
  package-specific, so #47 can feed it packages as well as services without
  forking. Emitted ids preserve option order.
- **Added** `client/src/features/maintenance/pages/AdminPackageBuilderPage/`
  (`.tsx`, `.module.css`, `.spec.ts`) — the page itself: list rows show
  name, branch badge, included-service count, bundled price, and a
  `StatusBadge`; per-row Edit and Deactivate/Reactivate; builder/edit form.
- **Modified** `client/src/features/maintenance/maintenance.routes.tsx` —
  registers `/staff/admin/maintenance/packages` behind `StaffAuthGuard`
  (file created in #45; this issue adds the package route).

Everything else this page relies on (API wrappers incl. `listPackages`/
`createPackage`/`updatePackage`, branch lookup, route mounting in
`routes.tsx`, dashboard link, style tokens) landed under #45 — see that doc.

### Scope notes / deviations from the issue spec

- **Branch is required first, and locked on edit.** The builder hides the
  service list until a branch is chosen (there is no "both branches"
  shortcut — creating the same package at both branches means filling the
  form twice, flagged in the issue as a possible future UX improvement, not
  Sprint 2 scope). When editing, the branch select is disabled: a package is
  permanently one branch's row (MA22), and the #41 update validator accepts
  no `branch_id`.
- **The service picker only offers services available at the chosen
  branch** (from `service_branch_availability`), and only active ones (the
  page fetches the default active-only services list) — matching #41's
  create-time validation so the form can't offer a selection the backend
  would reject.
- **No sum validation on the bundled price** — per #41's dev notes and this
  issue's AC-2, the price input enforces only "positive number". A spec test
  pins this (a ₱1 package over ₱600 of services submits cleanly).
- **Client-side minimum of 2 services** mirrors the #41 validator's
  `min(2)` so the user gets an inline message instead of a 400.

## Automated Verification

From the repository root in PowerShell:

```powershell
npm --prefix client test
npm --prefix client run lint
npm --prefix client run build
```

Expected: **51 test files / 201 tests pass**, ESLint 0 problems, build clean
(same full-suite run as #45's doc — the two issues share a working tree).

To run only this issue's files:

```powershell
npm --prefix client test -- --run src/features/maintenance/pages/AdminPackageBuilderPage src/features/maintenance/components/ServiceMultiSelect
```

Expected: 2 files / 11 tests pass (`AdminPackageBuilderPage` 7,
`ServiceMultiSelect` 4), named after the ACs they cover.

## Structural Verification

```powershell
Get-ChildItem client/src/features/maintenance/pages/AdminPackageBuilderPage, client/src/features/maintenance/components/ServiceMultiSelect -File
Select-String -Path client/src/features/maintenance/maintenance.routes.tsx -Pattern "maintenance/packages"
```

Expected: three files in each folder (`.tsx`, `.module.css`, `.spec.ts`);
one route match.

## Manual Browser Verification

Same stack as #45's doc — Supabase (`npx supabase start`, seeds applied),
API server (`npm --prefix server run dev`), client
(`npm --prefix client run dev`), then open `http://localhost:5173`.

**Seeded accounts** (passwords `password123`): Admin
`makati.admin1@goldenfur.com`, non-admin `makati.groomer1@goldenfur.com`.
Admin logins prompt for TOTP — see #45's doc for the one-time setup note.

### Step 1: Route guard (AC-4)

1. Sign in as the **Groomer** and navigate directly to
   `http://localhost:5173/staff/admin/maintenance/packages`.

Expected: redirected to `/staff/profile`. — **AC-4**

2. Sign out, sign in as the **Admin**, and click **Packages (Maintenance)**
   on the staff dashboard.

Expected: the Packages page loads and stays. — **AC-4**

### Step 2: List + branch filter (AC-1)

Expected on load (with the module-3 seed): **two "Golden Package" rows** —
one per branch — each showing a branch badge (Makati / Southwoods),
**3 services**, **PHP 600.00**, and an **Active** StatusBadge.

1. Set the **Branch** filter to `Makati`.

Expected: only the Makati row remains; no page reload (DevTools **Network**
tab shows no new document request). — **AC-1**

### Step 3: Build a package (AC-2)

1. Set the filter back to `All branches` and click **New package**.

Expected: the form shows Branch / Package name / Bundled price, and where
the service list will go, the note _"Select a branch to pick its available
services."_ — no service checkboxes yet. — **AC-2**

2. Select **Branch: Southwoods**.

Expected: the **Included services** checkbox list appears, listing only
services whose Southwoods toggle is on (each with its category and price as
a sublabel). If you disabled a service's Southwoods availability while
verifying #45 Step 4 and didn't re-enable it, that service must be absent
here. — **AC-2**

3. Fill in: name `Puppy Spa Day`, bundled price `999`, and tick **Bath** and
   **Nail Trim** (any two services work).
4. Click **Save package**.

Expected:

- A "Package created." banner; the new row appears (branch badge
  `Southwoods`, `2 services`, `PHP 999.00`, `Active`) without a reload.
- In Supabase Studio (`http://127.0.0.1:54323` → **Table Editor**):
  `packages` has the new row with `branch_id` = the Southwoods branch, and
  `package_services` has two rows for it. — **AC-2**

5. Sanity-check the price independence: create (or edit) a package whose
   bundled price is far below the selected services' sum, e.g. `1`.

Expected: saves without warning or error — the bundle price is deliberately
not tied to the sum. — **AC-2**

### Step 4: Edit a package (AC-3)

1. Click **Edit** on the `Puppy Spa Day` row.

Expected: the form opens pre-filled; the **Branch** select shows Southwoods
and is **disabled** (a package can't move branches).

2. Tick one more service (e.g. **Ear Cleaning**), change the price to
   `1200`, and click **Save package**.

Expected:

- "Package updated."; the row now shows `3 services` and `PHP 1200.00`
  without a page reload. — **AC-3**
- Supabase Studio → `package_services` now has three rows for the package
  (the service set is replaced wholesale on PATCH).

3. Click **Deactivate** on the row.

Expected: the StatusBadge flips to **Inactive** in place (the row stays
visible — the package list has no active-only filter, deactivated packages
remain manageable). Click **Reactivate** to restore it. — **AC-3**

## Acceptance Criteria Checklist

- [x] **AC-1:** Package list renders, filterable by branch, showing name,
      included service count, bundled price, and StatusBadge —
      `AdminPackageBuilderPage.spec.ts` (two AC-1 tests); manual Step 2.
- [x] **AC-2:** Builder form requires a branch, then name, multi-select via
      `ServiceMultiSelect`, and a bundled price independent of the services'
      sum — `AdminPackageBuilderPage.spec.ts` (two AC-2 tests) +
      `ServiceMultiSelect.spec.ts`; manual Step 3.
- [x] **AC-3:** Editing adds/removes included services and updates
      price/active status without a full page reload —
      `AdminPackageBuilderPage.spec.ts` (two AC-3 tests); manual Step 4.
- [x] **AC-4:** Non-Admin/Superadmin users cannot reach the page —
      `AdminPackageBuilderPage.spec.ts` (AC-4 test); manual Step 1.

No Postman collection or SQL file for this issue: it adds no API route and
no DB object — the endpoints it consumes are covered by
`testing/docs/issues/41-packages-crud-backend/`.

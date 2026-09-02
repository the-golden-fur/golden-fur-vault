# Issue #48 Verification: Discount Management UI

**Issue:** #48 — feat(discounts): discount management UI (SC/PWD toggles)
**Owner:** James
**Branch:** `feat/discount-management-ui`
**Base:** `dev`
**Depends on:** #43 (discounts CRUD backend), #45 (admin services UI —
`StatusBadge`/`ToggleSwitch`) merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

Adds a brand-new `discounts` client feature (`client/src/features/discounts/`
— M12 lives in its own folder, separate from `features/maintenance/`, same
module split the server already uses) with `AdminDiscountManagementPage` at
`/staff/admin/discounts`. Shows the two seeded, government-mandated
discounts (Senior Citizen, PWD) in a clearly labeled section separate from
custom discounts, with a per-row enable/disable toggle and a create form for
custom discounts scoped to a service, package, or category.

## What Changed

- **Added** `client/src/features/discounts/discounts.types.ts` — client
  mirror of `server/src/features/discounts/discounts.types.ts`
  (`Discount`, `DiscountScopeType`, `DiscountCategory`), plus
  `CreateDiscountPayload`/`UpdateDiscountPayload` matching the #43
  validators. `is_mandated` is deliberately absent from both payload types —
  it's unreachable via the API, mirrored client-side by construction.
- **Added** `client/src/features/discounts/api/discounts.api.ts` —
  `listDiscounts`/`createDiscount`/`updateDiscount`, same
  fetch/`authHeaders`/`parseBody` pattern as `maintenance.api.ts`. Reuses
  `listBranches`/`listServices`/`listPackages` from
  `features/maintenance/api/maintenance.api.ts` directly rather than
  duplicating them — those three are shared config data, not
  discount-specific.
- **Added** `client/src/features/discounts/discounts.routes.tsx` — registers
  `/staff/admin/discounts` behind `StaffAuthGuard`, same pattern as
  `maintenance.routes.tsx`.
- **Added**
  `client/src/features/discounts/pages/AdminDiscountManagementPage/`
  (`.tsx`, `.module.css`, `.spec.ts`).
- **Modified** `client/src/routes.tsx` — registers `discountsRoutes`.
- **Modified** `client/src/features/staff/dashboards/staffDashboard.config.ts`
  — adds a "Discounts" tile to the Admin dashboard.

### Scope notes / deviations from the issue spec

- **Scope picker uses plain `<select>` dropdowns, not `ServiceMultiSelect`.**
  The issue's dev notes suggest reusing #46/#47's multi-select pattern
  "extended" with a third category option. A discount's scope is
  structurally single-valued — the #43 `discounts_scope_matches_type` CHECK
  constraint and validator enforce _exactly one_ of
  `scope_service_id`/`scope_package_id`/`scope_category` — so a checkbox
  multi-select (built for "zero or more") would need to be artificially
  constrained to one selection. A native `<select>` per scope type
  (service / package / category) enforces "exactly one" for free and matches
  how every other single-value field on this form (branch, discount type)
  is already built. `ServiceMultiSelect` itself was not touched.
- **The package `<select>` filters to the form's selected branch's
  packages**, since packages are permanently one branch's row (MA22, same
  constraint #46's builder works around) — a discount scoped to a package
  can only reference a package that exists at the discount's own branch.
- **The service `<select>` is not branch-filtered** — services aren't
  branch-locked entities themselves (only their `service_branch_availability`
  toggle is), and neither the issue's ACs nor #43's validator condition
  service scope on branch availability, so all active services are offered
  regardless of branch.
- **A mandated discount's Edit form omits `name` from the PATCH payload
  entirely** rather than resubmitting the current (read-only, unchanged)
  value — avoids any dependency on how the server's rename-guard compares
  old vs. new name.
- **Per-row enable/disable is a `ToggleSwitch`, not a Deactivate/Reactivate
  button** (unlike the Services/Packages pages) — AC-2 names it a "toggle"
  explicitly, and `ToggleSwitch` was already shared/available from #45.

## Automated Verification

From the repository root in PowerShell:

```powershell
npm --prefix client test
npm --prefix client run lint
npm --prefix client run build
```

Expected: **55 test files / 221 tests pass**, ESLint 0 problems, build clean.

To run only this issue's files:

```powershell
npm --prefix client test -- --run src/features/discounts
```

Expected: 1 file / 5 tests pass, named after the ACs they cover.

## Structural Verification

```powershell
Get-ChildItem client/src/features/discounts -Recurse -File
Select-String -Path client/src/routes.tsx -Pattern "discountsRoutes"
Select-String -Path client/src/features/discounts/api/discounts.api.ts -Pattern "export async function (listDiscounts|createDiscount|updateDiscount)"
```

Expected: 6 files under `client/src/features/discounts/` (`discounts.types.ts`,
`api/discounts.api.ts`, `discounts.routes.tsx`, and the page's `.tsx`/
`.module.css`/`.spec.ts`); two matches in `routes.tsx` (import + usage);
three API function matches.

## Manual Browser Verification

Same stack as #45–#47's docs — Supabase (`npx supabase start`, seeds
applied), API server (`npm --prefix server run dev`), client
(`npm --prefix client run dev`), then open `http://localhost:5173`.

**Seeded accounts** (passwords `password123`): Admin
`makati.admin1@goldenfur.com`, non-admin `makati.groomer1@goldenfur.com`.
Admin logins prompt for TOTP — see #45's doc for the one-time setup note.

### Step 1: Route guard (AC-5)

1. Sign in as the **Groomer** and navigate directly to
   `http://localhost:5173/staff/admin/discounts`.

Expected: redirected to `/staff/profile`. — **AC-5**

2. Sign out, sign in as the **Admin**, and click **Discounts** on the staff
   dashboard.

Expected: the Discounts page loads and stays. — **AC-5**

### Step 2: Government-Mandated section (AC-1)

Expected on load (per #44's seed): a **"Government-Mandated"** heading with
**Senior Citizen** and **PWD** rows for each branch (4 rows total if the
branch filter is "All branches" — 2 discount types × 2 branches), each
showing **20%**, its scope, and an **Inactive** `StatusBadge`. A
**"Custom Discounts"** section below it starts empty
("No custom discounts yet."). A note near the top explains discounts are off
by default. — **AC-1**

### Step 3: Enable/disable toggle (AC-2)

1. Click the switch on a **Senior Citizen** row.

Expected: the switch flips, its `StatusBadge` updates to **Active**, and a
"Discount activated." banner appears — no page reload (DevTools **Network**
tab shows no new document request). — **AC-2**

2. In Supabase Studio (`http://127.0.0.1:54323` → **Table Editor**):
   `discounts` shows that row's `is_active = true`.
3. Click the same switch again to turn it back off, confirming it flips both
   directions cleanly.

### Step 4: Create a custom discount (AC-3)

1. Click **New custom discount**.
2. Select a **Branch**, name it `Staff Appreciation`, type `Percentage`,
   value `10`, scope `Category`, category `Grooming`.
3. Click **Save discount**.

Expected: "Discount created."; the new row appears under **Custom
Discounts** showing `10%`, `Category: Grooming`, and **Inactive** (custom
discounts also default to off — `createDiscount` forces this server-side
regardless of what's submitted). — **AC-3**

4. Repeat with scope `Service` (pick one from the dropdown) and then scope
   `Package` (branch's package list) to confirm all three scope types save.

### Step 5: Mandated discount name is read-only (AC-4)

1. Click **Edit** on the **PWD** row.

Expected: the **Name** field is visible but disabled/read-only — typing into
it has no effect. All other fields (type, value, scope) remain editable. —
**AC-4**

2. Click **Edit** on the custom `Staff Appreciation` row created in Step 4.

Expected: its **Name** field is editable (not disabled), confirming the
read-only behavior is specific to mandated rows.

## Acceptance Criteria Checklist

- [x] **AC-1:** Discount management view shows Senior Citizen and PWD in a
      distinct "Government-Mandated" section, per branch, both defaulting to
      Inactive — `AdminDiscountManagementPage.spec.ts`; manual Step 2.
- [x] **AC-2:** Per-discount enable/disable toggle works for both mandated
      and custom discounts without a full page reload —
      `AdminDiscountManagementPage.spec.ts`; manual Step 3.
- [x] **AC-3:** Create-custom-discount form saves name, type, value, and
      scope (service, package, or category) for a specific branch —
      `AdminDiscountManagementPage.spec.ts`; manual Step 4.
- [x] **AC-4:** Editing a mandated discount's name is prevented in the UI
      (field is read-only) — `AdminDiscountManagementPage.spec.ts`; manual
      Step 5.
- [x] **AC-5:** Non-Admin/Superadmin users cannot reach the page —
      `AdminDiscountManagementPage.spec.ts`; manual Step 1.

No Postman collection or SQL file for this issue: it adds no API route and
no DB object — the endpoints it consumes are `server/src/features/discounts/
discounts.routes.ts` (#43), unchanged by this issue.

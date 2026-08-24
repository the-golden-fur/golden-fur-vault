# Issue #47 Verification: Promo Configuration UI

**Issue:** #47 — feat(maintenance): promo configuration UI
**Owner:** James
**Branch:** `feat/promo-config-ui`
**Base:** `dev`
**Depends on:** #42 (promos CRUD backend + automatic expiry), #46 (package
builder UI — `ServiceMultiSelect`) merged
**Sprint:** Sprint 2 — Epic A — M13 Maintenance + M12 Discounts

## Overview

Adds `AdminPromoConfigPage` at `/staff/admin/maintenance/promos` — a
branch-scope/status-filterable promo list plus a create/edit form that
distinguishes date-bounded promos from condition-based ones behind a single
toggle, and lets scope target either "all services" or a specific mix of
services **and** packages in one multi-select.

## What Changed

- **Added** `Promo`/`PromoScopeType`/`PromoBranchScope`/`PromoScopeItem`/
  `CreatePromoPayload`/`UpdatePromoPayload`/`DiscountValueType` to
  `client/src/features/maintenance/maintenance.types.ts` — client mirror of
  the server's `maintenance.types.ts` promo shapes (#42), plus the request
  payloads accepted by the `createPromoValidator`/`updatePromoValidator`.
- **Added** `listPromos`/`createPromo`/`updatePromo` to
  `client/src/features/maintenance/api/maintenance.api.ts` — same
  fetch/`authHeaders`/`parseBody` pattern as every other function in that
  file.
- **Added**
  `client/src/features/maintenance/pages/AdminPromoConfigPage/` (`.tsx`,
  `.module.css`, `.spec.ts`) — the page itself.
- **Modified** `client/src/features/maintenance/maintenance.routes.tsx` —
  registers `/staff/admin/maintenance/promos` behind `StaffAuthGuard`.
- **Modified** `client/src/features/staff/dashboards/staffDashboard.config.ts`
  — adds a "Promos" tile to the Admin dashboard.

### Scope notes / deviations from the issue spec

- **Service/package scope union via a composite id, not a forked component.**
  The issue's dev notes flag that this is "the first form in the app to need
  a scope union across two entity types (service/package) in one selector"
  and says to raise it in the PR if `ServiceMultiSelect` (#46) can't cleanly
  support both rather than silently forking a near-duplicate. It didn't need
  a fork: `ServiceMultiSelect`'s `options`/`selectedIds` are opaque strings,
  so the promo scope picker prefixes ids (`svc:<id>` / `pkg:<id>`) before
  handing them to the existing component, and splits them back into
  `{service_id}` / `{package_id}` scope rows on submit. No changes to
  `ServiceMultiSelect` itself were needed.
- **Orphaned scope selections stay visible when editing.** If a promo's
  existing scope references a service/package that's since gone inactive,
  the edit form still offers that item (labeled "Inactive service"/"Inactive
  package") so opening the form for editing never silently drops a
  selection that a save-without-touching-scope would otherwise wipe out.
- **The scope multi-select is hidden entirely — not disabled — when
  `scope_type` is "All services"**, per the issue's dev notes, mirroring how
  #46's builder hides the service list until a branch is picked.
- **Client-side percentage cap (≤100) and window-shape checks** mirror the
  `#42` validator's `superRefine` rules, so the common mistakes surface as an
  inline message instead of a 400.

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
npm --prefix client test -- --run src/features/maintenance/pages/AdminPromoConfigPage
```

Expected: 1 file / 7 tests pass, named after the ACs they cover.

## Structural Verification

```powershell
Get-ChildItem client/src/features/maintenance/pages/AdminPromoConfigPage -File
Select-String -Path client/src/features/maintenance/maintenance.routes.tsx -Pattern "maintenance/promos"
Select-String -Path client/src/features/maintenance/api/maintenance.api.ts -Pattern "export async function (listPromos|createPromo|updatePromo)"
```

Expected: three files in the page folder (`.tsx`, `.module.css`, `.spec.ts`);
one route match; three API function matches.

## Manual Browser Verification

Same stack as #45/#46's docs — Supabase (`npx supabase start`, seeds
applied), API server (`npm --prefix server run dev`), client
(`npm --prefix client run dev`), then open `http://localhost:5173`.

**Seeded accounts** (passwords `password123`): Admin
`makati.admin1@goldenfur.com`, non-admin `makati.groomer1@goldenfur.com`.
Admin logins prompt for TOTP — see #45's doc for the one-time setup note.

### Step 1: Route guard (AC-5)

1. Sign in as the **Groomer** and navigate directly to
   `http://localhost:5173/staff/admin/maintenance/promos`.

Expected: redirected to `/staff/profile`. — **AC-5**

2. Sign out, sign in as the **Admin**, and click **Promos** on the staff
   dashboard.

Expected: the Promos page loads and stays. — **AC-5**

### Step 2: List + filters (AC-1)

Expected on load: no promos yet (Sprint 2's seed migration, #44, deliberately
leaves the `promos` table empty). The empty-state message reads "No promos
match the selected filters."

1. Create a promo first (Step 3), then return here.
2. Set the **Branch scope** filter to a value that doesn't match your test
   promo, then set **Status** to `All`.

Expected: the list narrows/widens without a page reload (DevTools **Network**
tab shows no new document request). — **AC-1**

### Step 3: Create a date-bounded promo (AC-2, AC-3)

1. Click **New promo**.

Expected: form defaults to **Date range** selected (Start date/End date
inputs visible; no condition note field). — **AC-3**

2. Fill in: name `Summer Sale`, discount type `Percentage`, value `15`,
   start date `2026-08-01`, end date `2026-08-31`, scope `All services`,
   branch scope `Both branches`.

Expected: with scope = "All services", no service/package checklist is
shown at all (not even disabled). — **AC-2**

3. Click **Save promo**.

Expected:

- A "Promo created." banner; the new row appears showing `Both branches`,
  `15% off`, `2026-08-01 to 2026-08-31`, and an **Active** badge. — **AC-2**
- In Supabase Studio (`http://127.0.0.1:54323` → **Table Editor**): `promos`
  has the new row with `scope_type = all_services` and no
  `promo_scope` rows.

### Step 4: Toggle to condition-based (AC-3)

1. Click **New promo** again. Click the **Condition-based** segment.

Expected: the Start date/End date inputs disappear; a single **Condition
note** text field appears instead. — **AC-3**

2. Fill in: name `First Booking Deal`, value `10`, condition note
   `First booking of the month`, scope `Specific services/packages`.

Expected: switching scope to "Specific services/packages" reveals the
multi-select, listing both services (labeled "Service - <category>") and
packages (labeled "Package"). — **AC-2**

3. Tick one service and one package, then **Save promo**.

Expected: "Promo created."; the row shows the condition note text in place
of a date range, and both toggling directions (Step 3 → date range, this
step → condition) saved correctly. — **AC-3**

### Step 5: Exclusivity flag (AC-4)

1. Edit either promo created above and toggle **"Cannot be combined with
   other promos"** on, then save.

Expected: an **Exclusive** badge appears on that row in the list — the
default (off/stackable) is the more permissive option, so its badge only
shows when explicitly turned on. — **AC-4**

## Acceptance Criteria Checklist

- [x] **AC-1:** Promo list renders, filterable by branch scope and active
      status, showing name, discount value/type, and a date range or
      condition note — `AdminPromoConfigPage.spec.ts`; manual Step 2.
- [x] **AC-2:** Config form saves name, dates (or a condition note), discount
      amount/type, scope (all-services or specific service/package
      selection), and branch scope — `AdminPromoConfigPage.spec.ts`; manual
      Steps 3–4.
- [x] **AC-3:** Toggling between "Date range" and "Condition-based" shows
      only the relevant fields, and both save correctly —
      `AdminPromoConfigPage.spec.ts`; manual Steps 3–4.
- [x] **AC-4:** The exclusivity toggle saves and displays correctly on the
      list view — `AdminPromoConfigPage.spec.ts`; manual Step 5.
- [x] **AC-5:** Non-Admin/Superadmin users cannot reach the page —
      `AdminPromoConfigPage.spec.ts`; manual Step 1.

No Postman collection or SQL file for this issue: it adds no API route and
no DB object — the promo endpoints it consumes are covered by
`testing/docs/issues/42-promos-crud-and-expiry/` (if/when that issue's own
doc is written; the routes themselves are `server/src/features/maintenance/
maintenance.routes.ts`, unchanged by this issue).

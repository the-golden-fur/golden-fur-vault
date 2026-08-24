# Issue #35 Verification: Admin Customer Management for Walk-ins

**Issue:** #35 — feat(customers): admin customer management for walk-ins
**Owner:** Alarie
**Branch:** `feat/admin-walkin-customer-management` (bundled — see Note below)
**Base:** `dev`
**Depends on:** #31, #32, #34 merged
**Sprint:** Sprint 1 — M02 Customer Portal & Pet Management

**Note on bundling (Jul 12, 2026):** Issues #31–#35 (all of Epic C) were bundled into a single implementation pass, per user request. This issue is client-only and adds no server routes or DB objects of its own (it composes #31/#32's existing endpoints plus Epic A's existing customer signup endpoint) — see those issues' folders for the API/DB verification behind this flow.

## Overview

Gives Receptionist/Admin/Supervisor/Superadmin a page to look up or create a walk-in customer by email (Modules-Features M02 Process 2), then immediately add a pet to that customer's record without navigating away.

**Confirms the Guide's own affected-files list:** #35 has **zero server-side affected files** in the Guide — this was verified deliberately before implementation, since satisfying AC-2 ("submitting an email that does not already exist creates a new `customer_profiles` row") would otherwise seem to need a new endpoint. It doesn't: `NewWalkInCustomerForm` reuses Epic A's existing `POST /auth/customers/signup` (via the client's existing `customerAuth.api.ts` → `signup()`) for the create path — with a randomly-generated placeholder password the walk-in customer never needs to know (they can use "forgot password" later if they want portal access) — and Issue #31's existing `GET /customers?email=` / `PATCH /customers/:id` for the lookup and update paths.

## What Changed

- **Added** `client/src/features/staff/components/forms/NewWalkInCustomerForm/NewWalkInCustomerForm.tsx` (+ CSS/spec) — two-step form: (1) enter full name + email, check for an existing account; (2) show the found record (offering an update) or a blank one (offering a create), with the rest of the intake fields (contact/emergency/comms).
- **Added** `client/src/features/staff/pages/AdminCustomerListPage/AdminCustomerListPage.tsx` (+ CSS/spec) — role-gated the same way as `AdminStaffListPage` (own role resolved from the already-fetched staff list, not from the Supabase session), guard role list `{'Receptionist', 'Admin', 'Supervisor', 'Superadmin'}` — deliberately the exact same list as the `customer_profiles`/`pets` staff RLS policies from #31/#32, so the UI guard and the database's actual permission boundary agree by construction. Lists all customers, embeds `NewWalkInCustomerForm`, and offers `PetForm` (reused unmodified from #34) against whichever customer was just created/updated.
- **Modified** `client/src/features/staff/staff.routes.ts` — registers `/staff/admin/customers` inside the existing `StaffAuthGuard`-wrapped route group.
- **Modified** `client/src/features/auth/staff/staffAuth.routes.ts` — adds a "Customer Directory" link to the `/staff` dashboard stub, alongside the existing "My Profile"/"Settings"/"Staff Directory" links, so every staff role that can reach `/staff` sees the entry point directly rather than needing to first open Staff Directory (Admin/Superadmin-only) to find it.

**Reconciled during manual verification:** the link was initially added inside `AdminStaffListPage.tsx` (Staff Directory) instead, which meant Receptionist/Supervisor — both authorized to use walk-in intake per AC-1 — had no discoverable path to it at all, since Staff Directory itself is Admin/Superadmin-only. Moved to the `/staff` dashboard stub instead, which every staff role reaches after login regardless of role.

**Found and fixed post-implementation:** `client/vite.config.ts` was missing `/customers` and `/pets` proxy entries (see #34's doc for the full explanation) — this broke both the "Check account" lookup and the customer list on this page identically to #34's pet-loading bug, since both go through the same `customer.api.ts`. Fixed in the same `vite.config.ts` change; restart `npm --prefix client run dev` if you haven't already.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix client test -- --run
npx tsc -b --project client
npm --prefix client run lint
```

## Structural Verification

```powershell
Get-ChildItem client/src/features/staff/pages/AdminCustomerListPage
Get-ChildItem client/src/features/staff/components/forms/NewWalkInCustomerForm
Select-String -Path client/src/features/staff/staff.routes.ts -Pattern "admin/customers"
```

## Manual Browser Verification

You'll need a **Receptionist** (or Admin/Supervisor/Superadmin) staff account, and a **Groomer** (or any non-authorized role) account to confirm the negative case.

### 0. Start both servers

```powershell
# Terminal 1
npm --prefix server run dev
```

```powershell
# Terminal 2
npm --prefix client run dev
```

### 1. AC-1: role gating

1. Log in at `/staff/login` as the **Groomer** account and navigate directly to `/staff/admin/customers`.
   **Expected:** immediately redirected to `/staff/profile`.
2. Log out, log in as the **Receptionist** (or Admin/Supervisor/Superadmin) — the `/staff` dashboard you land on after login shows a **Customer Directory** link alongside My Profile/Settings/Staff Directory. Click it.
   **Expected:** the "Customer Directory" page loads, listing existing customers.

### 2. AC-2: create a new walk-in customer

1. In the **New walk-in customer** panel, enter a full name and an email address you're confident doesn't already exist (e.g. `walkin-test-<timestamp>@example.com`), then click **Check account**.
   **Expected:** "No existing account found. Confirm to create a new customer." plus the rest of the intake fields (contact number, emergency contact, comms channel).
2. Fill in a contact number and click **Create customer**.
   **Expected:** a "Customer saved. Add a pet below if needed." banner appears, and the new customer appears in the list below with a `PetForm` already expanded under their row.

### 3. AC-3: existing-account path

1. In the **New walk-in customer** panel, enter the **same email** you just used in step 2 (with any name — it'll be overwritten by the lookup) and click **Check account**.
   **Expected:** "An account already exists for this email. Confirm to update it instead of creating a duplicate." — and the form is pre-filled with that customer's actual current details (confirming it found the real row, not just echoing your input).
2. Change the contact number and click **Update customer**.
   **Expected:** the customer's row in the list reflects the updated contact number; no duplicate row was created.

### 4. AC-4: add a pet in the same session

1. Immediately after step 2 or 3 above (the `PetForm` should already be expanded for that customer — if not, click **Add pet** on their row), fill in Name/Species/Weight class/Coat type and submit.
   **Expected:** a `PetCard` appears under that customer's row in the list, confirming the pet was created against the right customer.

### 5. AC-5: RLS + requireRole both deny direct access

1. Log in as the **Groomer** account again. Open the browser DevTools console and confirm you cannot reach the underlying data even by bypassing the UI guard — e.g. attempt a raw fetch:

   ```js
   fetch("http://localhost:3000/customers", {
     headers: {
       Authorization: `Bearer ${/* paste the Groomer's access token from Application > Local Storage */ ""}`,
     },
   }).then((r) => r.status);
   ```

   **Expected:** `403` — confirmed independently by #31's automated integration tests (`AC-3: returns 403 for a Groomer`) and RLS (`customer-profile-crud.sql` policy check), matching this issue's AC-5 claim that both layers deny an unauthorized role even if the page were reached directly.

## Acceptance Criteria Checklist

- [x] **AC-1:** `AdminCustomerListPage` is reachable only by Receptionist/Admin/Supervisor/Superadmin; other roles are redirected/denied — unit tests `AC-1: is reachable for a Receptionist...` / `AC-1: redirects a Groomer...`; manual step 1.
- [x] **AC-2:** Submitting an email that doesn't already exist creates a new `customer_profiles` row — unit test `AC-2: creates a new customer when the email does not already exist`; manual step 2.
- [x] **AC-3:** Submitting an email that already exists shows the existing record and, on confirmation, updates it rather than creating a duplicate — unit test `AC-3: shows and updates the existing record...`; manual step 3.
- [x] **AC-4:** After creating/updating a customer, the flow offers to open `PetForm` pre-targeted at that customer, and a submitted pet appears under that customer's record — manual step 4 (component composition covered indirectly by `AdminCustomerListPage.spec.ts` and `PetForm.spec.ts`).
- [x] **AC-5:** A staff member without an authorized role gets 403 from the underlying endpoints even if they reach the page directly by URL — covered by #31/#32's RLS + integration tests (this issue introduces no new endpoints to re-test); manual step 5.

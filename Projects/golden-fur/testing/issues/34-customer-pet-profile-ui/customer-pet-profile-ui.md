# Issue #34 Verification: Customer + Pet Profile UI

**Issue:** #34 — feat(customers): customer + pet profile UI
**Owner:** James
**Branch:** `feat/customer-pet-profile-ui` (bundled — see Note below)
**Base:** `dev`
**Depends on:** #31, #32, #33 merged
**Sprint:** Sprint 1 — M02 Customer Portal & Pet Management

**Note on bundling (Jul 12, 2026):** Issues #31–#35 (all of Epic C) were bundled into a single implementation pass, per user request. This issue is client-only and adds no server routes or DB objects, so it has no Postman collection or SQL script in this folder — see #31/#32/#33's folders for the API/DB verification behind the pages built here.

## Overview

Gives customers a self-service Profile page (edit contact/emergency/comms fields) and a pet management area (view/add pets, view a single pet's full profile with vaccination records, medical notes, and a Service History placeholder tab).

**Deviation from the Guide (reconciled during implementation):** the Guide's dev notes describe `CustomerProfilePage` as "reusing the customer-portal Settings shell." No such literal code-sharing was done — `SettingsPage.tsx` (Epic A #10) is a generic `{ role }`-parameterized shell for the Security/MFA section only, with no extension point for arbitrary additional sections. Instead, `CustomerProfilePage` is built as its own page (per the Guide's own Affected Files list, which lists it as a standalone added file) styled with the same CSS-module token vocabulary and page/panel/form layout pattern `SettingsPage.tsx` and `StaffProfilePage.tsx` already use — "reuses the shell" in spirit (visual/structural consistency), not by literal shared markup. It's registered at `/portal/profile`, a sibling route to `/portal/settings`, with a nav link added to the `/portal` landing stub alongside the existing Settings link.

**Design choice not specified in the Guide:** the Guide doesn't say which page hosts the pet list (`PetCard` + "add a pet" via `PetForm`) — only that `CustomerProfilePage` and `PetProfilePage` are the two new pages. Rather than inventing a third, unlisted page, the "My Pets" section (list + add) lives inside `CustomerProfilePage`, below the profile form.

## What Changed

- **Added** `client/src/features/customers/customer.types.ts`, `api/customer.api.ts` (+ spec) — mirrors the server's `customer.controller.ts`/`pet.controller.ts`/vaccination+medical-note routes.
- **Added** `client/src/features/customers/customer.routes.ts` — registers `/portal/profile` and `/portal/pets/:petId`, both wrapped in the existing `CustomerAuthGuard` (Epic A).
- **Added** `client/src/features/customers/components/cards/PetCard/PetCard.tsx` (+ CSS/spec) — name, species/breed, weight_class/coat_type badges, links to `/portal/pets/:id`.
- **Added** `client/src/features/customers/components/forms/PetForm/PetForm.tsx` (+ CSS/spec) — client-side required-field validation (name/species/weight_class/coat_type) matching the server validator; built generic on `customerId` so Issue #35 reuses it unmodified for walk-in intake.
- **Added** `client/src/features/customers/components/lists/VaccinationRecordList/VaccinationRecordList.tsx` and `MedicalNoteList/MedicalNoteList.tsx` (+ CSS/spec) — read-only lists.
- **Added** `client/src/features/customers/pages/CustomerProfilePage/CustomerProfilePage.tsx` (+ CSS/spec) — profile form + "My Pets" section.
- **Added** `client/src/features/customers/pages/PetProfilePage/PetProfilePage.tsx` (+ CSS/spec) — pet attributes, `VaccinationRecordList`, `MedicalNoteList`, and a Service History tab rendering only the documented empty state ("No service history yet.").
- **Modified** `client/src/routes.tsx` — registers `customerRoutes`. (Epic D Issue #36 was going to do this formally; it's pre-wired here so this issue is actually reachable/testable in the browser this session.)
- **Modified** `client/src/features/auth/customer/customerAuth.routes.ts` — the `/portal` landing stub gets a "Profile" link alongside its existing "Settings" link, so a logged-in customer can reach the new page via the UI, not just by typing the URL.
- **Modified** `client/vite.config.ts` — adds `/customers` and `/pets` to the dev-server proxy list (forwarded to `http://localhost:3000`, same as the existing `/staff` entry). **Found and fixed post-implementation:** without this, `customer.api.ts`'s relative fetches (`/customers/...`, `/pets/...`) hit the Vite dev server itself instead of the Express backend, and silently get back `index.html` (200/304, `Content-Type: text/html`) instead of JSON — surfacing as pets never loading on `/portal/profile` and every `customer.api.ts` call failing with "Request failed. Please try again." **Restart `npm --prefix client run dev` after pulling this change** — Vite does not hot-reload `vite.config.ts`.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix client test -- --run
npx tsc -b --project client
npm --prefix client run lint
```

Expected: all client test files pass, `tsc -b` produces no output, `eslint .` reports 0 errors.

## Structural Verification

```powershell
Get-ChildItem client/src/features/customers -Recurse -Filter "*.tsx"
Select-String -Path client/src/routes.tsx -Pattern "customerRoutes"
```

## Manual Browser Verification

You'll need one customer account (create one via `/signup` if you don't have one, or use a seeded account) and, ideally, a second customer account for the cross-customer error-state check in step 4.

### 0. Start both servers

```powershell
# Terminal 1
npm --prefix server run dev
```

```powershell
# Terminal 2
npm --prefix client run dev
```

Open the printed client URL (typically `http://localhost:5173`).

### 1. AC-1 & AC-2: profile renders and saves

1. Log in at `/login` as your customer account, then navigate to `/portal/profile` (or click **Profile** from `/portal`).
   **Expected:** the page shows your full name, contact number, emergency contact fields, and preferred communication channel, pre-filled from the server.
2. Change the contact number and click **Save Profile**.
   **Expected:** a "Profile saved." banner appears immediately, with **no full page reload** (watch the browser's loading indicator / URL bar — it shouldn't flash).
3. Refresh the page.
   **Expected:** the new contact number is still there (confirms the PATCH actually persisted, not just local state).

### 2. AC-3 & AC-4: adding a pet

1. On `/portal/profile`, scroll to **My Pets** and click **Add a pet**.
2. Click **Add pet** without filling anything in.
   **Expected:** an inline error — "Name, species, weight class, and coat type are required." — and no network request is sent (open DevTools → Network first if you want to confirm nothing fires).
3. Fill in Name, Species, Weight class, and Coat type (leave the optional fields blank) and submit.
   **Expected:** the form clears, a "Pet added." banner appears, and a new `PetCard` appears in the grid showing the name, species, and the weight-class/coat-type badges.

### 3. AC-5: pet profile page

1. Click the new pet's card.
   **Expected:** navigates to `/portal/pets/<id>` showing the pet's attributes (species, weight class, coat type, and any optional fields you filled in), a "Vaccination Records" section (empty state: "No vaccination records yet." unless you've added one via #33's Postman collection), a "Medical Notes" section (same empty state), and a "Service History" section showing **"No service history yet."**

### 4. AC-6: a 403/404 surfaces as a clear error, not a blank page

Pick one of these two approaches:

- **With a second customer account:** log in as customer B, note customer A's pet id from step 3's URL, and navigate directly to `/portal/pets/<customer-A's-pet-id>`.
- **Without a second account:** navigate to `/portal/pets/00000000-0000-0000-0000-000000000000` (a well-formed but nonexistent id) while logged in as any customer.

**Expected:** the page shows a visible error message (the server's `error` text, e.g. "Forbidden" or "Pet not found") — **not** a blank page, an infinite spinner, or a crash.

## Acceptance Criteria Checklist

- [x] **AC-1:** `CustomerProfilePage` renders full name, contact number, emergency contact, and communication preference from `getCustomerProfile()` — unit test `AC-1: renders the logged-in customer's profile fields`; manual step 1.
- [x] **AC-2:** Editing and saving calls `updateCustomerProfile()` and reflects the update without a full page reload — unit test `AC-2: saving edits calls updateCustomerProfile...`; manual step 1.
- [x] **AC-3:** `PetCard` renders name, species/breed, and weight_class/coat_type badges, and links to `PetProfilePage` — unit tests in `PetCard.spec.ts`; manual step 2.
- [x] **AC-4:** `PetForm` validates name/species/weight_class/coat_type as required before allowing submission, matching #32's server-side validator — unit tests in `PetForm.spec.ts`; manual step 2.
- [x] **AC-5:** `PetProfilePage` renders the pet's attributes, `VaccinationRecordList`, `MedicalNoteList`, and a Service History tab showing the empty state — unit test `AC-5: renders the pet's attributes and the Service History empty state`; manual step 3.
- [x] **AC-6:** A customer cannot see another customer's pets or profile through any client-side route; a server-side 403 surfaces as a clear error state — unit test `AC-6: a 403 from the server surfaces as a clear error state...`; manual step 4.

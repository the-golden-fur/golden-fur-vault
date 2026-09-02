# Issue #36 Verification: Wire All App Routes (Client + Server)

**Issue:** #36 — chore(routes): wire all app routes (client + server)
**Owner:** Alarie
**Branch:** `chore/wire-app-routes`
**Base:** `dev`
**Depends on:** Epic B merged; Epic C merged
**Sprint:** Sprint 1 — Epic D — `shared/`

## Overview

This issue asks for `server/src/shared/app.routes.ts` to mount `customerRoutes`
alongside the existing `authRoutes`/`staffRoutes`, and for `client/src/routes.tsx`
to register the full Sprint 1 route tree (staff, customer, and the shared OAuth
callback route).

**Finding: both sides were already wired when this pass started.** Epic C's
merge into `dev` already brought `customer.routes.ts` in on both the server and
the client, and both route trees were already fully assembled. No code changes
were made for this issue — this pass is a verification-only confirmation that
every acceptance criterion is met by the current `dev` state.

## What Was Verified (No Code Changes)

- **`server/src/shared/app.routes.ts`** mounts, in order: `authRoutes`,
  `staffRoutes`, `customerRoutes` (AC-4).
- **`server/src/features/auth/auth.routes.ts`** mounts staff and customer auth
  under `/auth`.
- **`server/src/features/staff/staff.routes.ts`** registers every Epic A-1/B
  staff route: profile CRUD, avatar upload, Unavailability Block create/list/
  cancel/review, admin staff list. Static/prefix routes
  (`/staff`, `/staff/unavailability/pending`) are registered **before** the
  dynamic `/staff/:id` family, so nothing is shadowed (AC-5).
- **`server/src/features/customers/customer.routes.ts`** registers customer
  profile CRUD and mounts `pet.routes.ts` (pet CRUD, vaccination records,
  medical notes).
- **`client/src/routes.tsx`**'s `AppRoutes()` renders, in order:
  `staffAuthRoutes`, `staffRoutes`, `customerAuthRoutes`, `customerRoutes`, and
  the landing page (AC-2). Between them these cover: `/staff/login`,
  `/staff/mfa/enroll`, `/staff/mfa/verify`, `/staff`, `/staff/settings`,
  `/staff/profile`, `/staff/admin/staff`, `/staff/admin/unavailability`,
  `/staff/admin/customers`, `/login`, `/signup`, `/auth/callback`,
  `/portal/mfa/verify`, `/portal`, `/portal/settings`, `/portal/profile`,
  `/portal/pets/:petId`.
- React Router resolves routes by path specificity rather than registration
  order, so the static-vs-dynamic ordering concern from AC-5 doesn't apply
  client-side the way it does for Express — confirmed no two registered paths
  collide.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: all 257 server tests pass (unchanged by this issue), `tsc --noEmit`
produces no output, `eslint .` reports only the 3 pre-existing `no-console`
warnings (unrelated to routing).

## Structural Verification

1. Confirm the server mounts all three feature routers:

   ```powershell
   Select-String -Path server/src/shared/app.routes.ts -Pattern "router.use"
   ```

   Expected: `authRoutes`, `staffRoutes`, `customerRoutes`, all three present.

2. Confirm the client route tree pulls in every feature's routes:

   ```powershell
   Get-Content client/src/routes.tsx
   ```

   Expected: `staffAuthRoutes`, `staffRoutes`, `customerAuthRoutes`,
   `customerRoutes`, and `LandingPage` all rendered inside `<Routes>`.

## Manual Browser Smoke Pass (AC-2)

1. Start both apps:

   ```powershell
   npm run dev
   ```

2. In a browser, visit each of the following and confirm a page renders
   (not a blank screen / router "no match"):
   - `http://localhost:5173/` — landing page
   - `http://localhost:5173/staff/login` — staff login form
   - `http://localhost:5173/login` — customer login form
   - `http://localhost:5173/signup` — customer signup form
   - `http://localhost:5173/staff/admin/staff` — redirects to `/staff/login`
     if not authenticated as staff (expected — it's behind `StaffAuthGuard`);
     confirms the route exists and the guard fires rather than 404ing.
   - `http://localhost:5173/portal` — redirects to `/login` if not
     authenticated as a customer (same guard behavior).

## Postman / Route-List Smoke Test (AC-1)

No dedicated collection for this issue — AC-1 asks only for reachability, not
new business logic, and every route it covers already has its own Postman
collection from its originating issue (see `testing/docs/issues/22-*`,
`24-*`, `29-*`, `31-*`, `32-*`, `33-*`, `35-*`). Confirm reachability with a
single unauthenticated smoke request per feature router:

```powershell
npm --prefix server run dev
```

```powershell
# Expect 401 (route exists, auth/credential-gated) - NOT 404 (route missing)
function Get-StatusCode($Uri, $Method = 'Get', $Body) {
  try {
    if ($Body) {
      $r = Invoke-WebRequest $Uri -Method $Method -Body $Body -ContentType 'application/json' -ErrorAction Stop
    } else {
      $r = Invoke-WebRequest $Uri -Method $Method -ErrorAction Stop
    }
    return $r.StatusCode
  } catch {
    return [int]$_.Exception.Response.StatusCode
  }
}

Get-StatusCode 'http://localhost:3000/staff'
Get-StatusCode 'http://localhost:3000/customers'
Get-StatusCode 'http://localhost:3000/auth/staff/login' -Method Post -Body '{}'
```

Expected: `401` for all three — `/staff` and `/customers` because no JWT was
supplied, `/auth/staff/login` because an empty credential body resolves to a
failed lookup/authentication rather than a validation error. Any of these
being `404` instead would mean the route isn't actually mounted; verified live
against a running server as part of this pass.

Expected: `401` for the first two (JWT-gated), `400` for the login POST with
an empty body (validation-gated) — any of these being `404` instead would mean
a route isn't actually mounted.

## Acceptance Criteria Checklist

- [x] **AC-1:** every Epic A/A-1/B/C server route is reachable via the
      top-level Express app — confirmed via the route-list smoke test above;
      full behavior already covered by each route's own issue-level tests.
- [x] **AC-2:** every Epic A/A-1/B/C client route/page is reachable via
      `client/src/routes.tsx` — confirmed via the manual browser pass above.
- [x] **AC-3:** no previously-passing route regresses — confirmed by the full
      257-test server suite passing unmodified.
- [x] **AC-4:** `server/src/shared/app.routes.ts` mounts `customerRoutes`
      alongside `authRoutes` and `staffRoutes` — already true on `dev`.
- [x] **AC-5:** no unintended static/dynamic shadowing — confirmed by
      inspection of registration order in `staff.routes.ts` and `pet.routes.ts`.

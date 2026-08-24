# Modularize shared/, role-based staff dashboards, navbar logout

Custom request (not tied to an epic/issue). Branch:
`refactor/modularize-shared-and-role-dashboards` (created off `dev` -
`feat/services-packages-admin-ui` had already been merged into `dev` via PR
#56 by the time this work started, so branching from the stale feature
branch would have missed that merge).

## What changed

### 1. Duplicate `shared/` directory resolved

`client/src/features/maintenance/components/shared/` held `StatusBadge` and
`ToggleSwitch` — both fully generic (no maintenance-specific logic; their own
comments said "shared by all four Epic A admin pages"), so they were a second,
competing "shared" concept alongside the real `client/src/shared/`. Moved
both to `client/src/shared/components/` (history preserved via `git mv`) and
updated the two importers (`AdminServicesPage.tsx`,
`AdminPackageBuilderPage.tsx`). The now-empty
`features/maintenance/components/shared/` directory was removed.

Server-side (`server/src/shared/` vs. `server/src/features/*`) was checked
too — no duplicate `shared/` exists there, so no server changes were needed.

### 2. Landing page navbar modularized

`LandingPage.tsx` had ~70 lines of inline marketing-nav JSX mixed into a
1300-line page component. Extracted to
`client/src/pages/LandingPage/components/LandingNavbar/LandingNavbar.tsx`.
It's scoped to the landing page (not moved to the app-wide `shared/`) since
it's a one-off marketing nav, distinct from the authenticated shared `Navbar`
below. IDs/classes were kept identical so `LandingPage.tsx`'s existing
`useEffect` (mobile toggle, stagger-text animation) keeps finding them via
`document.getElementById`/`querySelector` unchanged.

### 3. Shared `Navbar` built; logout moved out of Settings

`client/src/shared/components/Navbar/Navbar.tsx` was previously a 0-byte
stub (never implemented, unused). Built it out as the persistent top bar for
both authenticated areas: brand link, **My Profile**, **Settings**, and
**Sign out** — role-aware (`staff` → `/staff/*`, `customer` → `/portal/*`).
Wired into `StaffAuthGuard` and `CustomerAuthGuard` (rendered once above
`<Outlet />`, not duplicated per page).

`SettingsPage.tsx`'s "Account / Sign out" section was removed — sign out is
an account-wide action, not a page-specific setting, matching the request
("isn't it supposed to be in the navbar?"). `SettingsPage.spec.ts`'s sign-out
test moved to `Navbar.spec.ts`, which now owns that behavior.

Also removed two now-redundant `Link`s from the `/portal` placeholder route
(`customerAuth.routes.ts`) since Profile/Settings are covered by the new
Navbar.

### 4. Role-based staff dashboards + login redirect

Previously `/staff` was a single hardcoded link list showing **Staff
Directory**, **Customer Directory**, **Services**, **Packages** to every
staff role — but three of those four pages already self-gate to
Admin/Superadmin only (`AdminStaffListPage`, `AdminServicesPage`,
`AdminPackageBuilderPage` all redirect non-admins to `/staff/profile`), and
the fourth (`AdminCustomerListPage`) is gated to
Receptionist/Admin/Supervisor/Superadmin. Every other role (Groomer,
Veterinarian, Cashier, Pet Assistant) saw links that just bounced them away.

Built a single, config-driven dashboard instead of one page per role (kept
it DRY rather than adding 7 near-duplicate files):

- `features/staff/dashboards/staffDashboard.config.ts` — maps each
  `StaffRole` to a dashboard slug (`Superadmin`/`Admin` share `admin`, since
  they already share the same `ADMIN_ROLES` permission tier server-side) and
  defines each dashboard's tiles. A tile with a `to` renders as a real link;
  a tile without one renders as a "Coming soon" placeholder — used for every
  module that isn't built yet (M03 Bookings Queue, M04 Grooming Queue, M05
  Care Log, M06 Daycare Check-in, M07 Consultation Queue, M08 Checkout,
  M14-ish Branch Reports for Supervisor). Nothing was invented beyond what's
  actually routed today plus the module names from `temp/context/source.txt`
  (Modules-Features flowcharts) for the placeholder labels.
- `features/staff/dashboards/components/DashboardTile/DashboardTile.tsx` —
  the reusable tile (link vs. placeholder).
- `features/staff/dashboards/pages/StaffDashboardPage/StaffDashboardPage.tsx`
  — resolves the viewer's own role (`getStaffProfile`, same pattern already
  used elsewhere in this codebase) and renders the matching config. Handles
  both `/staff/dashboard` (no slug) and `/staff/dashboard/:roleSlug`; a
  missing or mismatched slug redirects to the viewer's own canonical slug, so
  a role can never land on - or hand-navigate to - another role's dashboard
  shape.
- `/staff` now simply redirects to `/staff/dashboard`
  (`staffAuth.routes.ts`), and `StaffLoginForm.tsx` didn't need to change -
  it already navigated to `/staff` after login, which now resolves through
  to the correct role's dashboard automatically.

Per the request, none of the placeholder modules (Bookings Queue, Grooming
Queue, Care Log, etc.) were built - only the "Coming soon" tiles.

## Why a single StaffDashboardPage instead of 7 pages

The request said "make separate dashboards ... 1 dashboard for groomer, vet,
receptionist, admin, etc." Read literally that could mean 7 files. I went
with one component parameterized by a config map instead, because:

- Each role still gets its own URL (`/staff/dashboard/groomer`,
  `/staff/dashboard/admin`, ...) and its own distinct content - "separate
  dashboards" is satisfied at the URL/content level.
- 7 near-identical page files (same loading/error states, same grid layout,
  differing only in which tiles) is exactly the duplication the request
  opened by asking to reduce.

If you'd rather have literally separate page components per role (e.g. to
let a specific role's dashboard grow custom logic later without touching a
shared file), say so and I'll split them - the config map makes that a
mechanical extraction, not a redesign.

## Pre-existing issue found during verification (not fixed, out of scope)

While screenshotting the new dashboards I found low-contrast page
headings/backgrounds on `/staff/dashboard/*` (and this likely affects other
inner staff/customer pages too). Root cause: `LandingPage.module.css` has an
unscoped `body { background: linear-gradient(...) }` rule. Because
`routes.tsx` imports `LandingPage` statically (not lazily), Vite injects that
CSS globally as soon as the app boots, not only when `/` is visited. It
out-paints the intended `[data-theme='staff'|'customer'] { background-color:
... }` rule (set on `<html>` by `ThemeProvider.tsx`) because `<body>` sits on
top of `<html>` in the paint order, regardless of CSS specificity between the
two selectors. Individual components with an explicit `background` (tiles,
navbar, badges) still render correctly - only bare page backgrounds behind
them are affected.

This predates this branch (verified by inspection: the import chain and both
CSS rules were unchanged by this work) and touches a 1800-line legacy CSS
file with no test coverage, so I didn't fix it here to keep this change's
blast radius scoped to what was asked. Screenshots below show it. Worth a
follow-up ticket if you want it fixed.

## Verification performed

- `npm run test` (client): 53 files / 209 tests passed.
- `npx tsc -b` (client build-mode typecheck): clean, no errors.
- `npx eslint .` (client): clean, no errors/warnings.
- Ran the real dev stack (`npm run dev`, client on :5173 + server on :3000)
  against the seeded Supabase data and drove it with Playwright:
  - `/` renders with the new `LandingNavbar` extracted correctly (screenshot
    `01-landing.png`).
  - Logged in as `makati.admin1` → correctly forced to `/staff/mfa/verify`
    (Admin role requires MFA - untouched behavior, confirms the guard logic
    still runs before the new dashboard redirect).
  - Logged in as `makati.groomer1` → landed on
    `/staff/dashboard/groomer` with the Groomer-only tile set and the new
    Navbar showing My Profile/Settings/Sign out (screenshot
    `03-groomer-dashboard.png`).
  - Clicked **Sign out** in the Navbar → redirected to `/staff/login`
    (screenshot `04-after-signout.png`).
  - Logged in as `makati.receptionist1` → landed on
    `/staff/dashboard/receptionist` with a mixed tile set: one real link
    (Customer Directory) plus three "Coming soon" placeholders (screenshot
    `05-receptionist-dashboard.png`).
  - Opened Settings from the Navbar as the Groomer → confirmed the page no
    longer has its own Sign out button; the only one on screen is the
    Navbar's (screenshot `06-settings-page.png`).
  - No browser console errors in any of the above.
- Dev servers were stopped after verification.

## How to verify yourself

1. From the repo root: `npm run dev` (starts client on :5173 and server on
   :3000 together). If you haven't seeded staff accounts yet:
   `npm run seed:module-1` (creates accounts for every role at both
   branches; all use password `password123`, username pattern
   `<branch>.<role><n>`, e.g. `makati.groomer1`, `southwoods.cashier1`).
2. Open `http://localhost:5173/` - confirm the navbar (Golden Fur brand,
   Services/Branches/Packages & Promos/About, Sign In, Book Now) still looks
   and behaves the same as before (mobile menu toggle included).
3. Go to `http://localhost:5173/staff/login` and sign in as
   `makati.groomer1` / `password123`. You should land on
   `/staff/dashboard/groomer` with one "Grooming Queue - Coming soon" tile.
4. Try `makati.receptionist1` / `password123` - lands on
   `/staff/dashboard/receptionist` with Customer Directory as a working link
   plus three placeholder tiles.
5. Try `makati.supervisor1` / `password123` (will prompt mandatory MFA setup
   since Supervisor requires it) - once past that, lands on
   `/staff/dashboard/supervisor` with Customer Directory + Unavailability
   Approval Queue as working links, plus a Branch Reports placeholder.
6. Try `makati.admin1` / `password123` (also mandatory MFA) - lands on
   `/staff/dashboard/admin` with all five admin tiles (Staff Directory,
   Customer Directory, Unavailability Approval Queue, Services, Packages) as
   working links.
7. From any staff page, click **Sign out** in the top navbar (not in
   Settings) - confirms you're returned to `/staff/login`.
8. Click **Settings** in the navbar - confirms there's no separate Sign out
   button on that page anymore.
9. Manually browse to a mismatched dashboard URL while logged in, e.g. as
   the Groomer visit `http://localhost:5173/staff/dashboard/admin` directly
   - confirms it bounces you back to `/staff/dashboard/groomer` instead of
     showing the Admin tiles.

No DB objects or new API routes were added by this change, so no
Postman/SQL files accompany this doc.

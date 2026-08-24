# Flatten staff dashboards, relocate staff config, add custom error pages/component

Custom request (not tied to an epic/issue). Branch: `dev` (worked directly
on `dev` — no dedicated feature branch existed for this request).

## What changed

### 1. `features/staff/dashboards/` flattened into `features/staff/`

The nested `dashboards/` folder was redundant — everything inside it was
already staff-scoped, so a second staff-scoped subfolder just added a path
segment with no organizing value. Moved (via `git mv`, history preserved):

- `dashboards/pages/StaffDashboardPage/` → `pages/StaffDashboardPage/`
  (now sits next to the feature's other pages, e.g. `AdminStaffListPage`).
- `dashboards/components/DashboardTile/` →
  `components/dashboard/DashboardTile/` (kept the category-folder pattern
  the rest of `staff/components/` already uses — `badges/`, `cards/`,
  `forms/`, `review/` — so `dashboard/` joins that set instead of breaking
  it).
- `dashboards/staffDashboard.config.ts` → `config/staffDashboard.config.ts`
  (new `config/` folder, scoped to this feature — see below for why not
  `client/src/config/`).

Updated every import that pointed at the old paths:
`staff.routes.ts`, `StaffDashboardPage.tsx` (+ its `.spec.ts`),
`DashboardTile.tsx`. Confirmed with a repo-wide grep that no
`dashboards/...` reference was left behind.

### 2. `staffDashboard.config.ts` placement: feature config, not global config

You offered either `client/src/config/` or
`client/src/features/staff/config/`. Went with the feature-scoped option:
`STAFF_DASHBOARD_CONFIG` and `ROLE_TO_DASHBOARD_SLUG` are staff-dashboard
-specific (they key off `StaffRole` and staff-only routes like
`/staff/admin/staff`) — nothing outside `features/staff` imports them today,
so putting them in the app-wide `client/src/config/` (currently empty,
holding only a `.gitkeep`) would suggest a broader scope than they actually
have. If a second feature ever needs config this shape, that's the signal to
promote a shared pattern to `client/src/config/` — not before.

### 3. `shared/auth` and `shared/api/mfa.api.ts` — investigated, not moved

You asked why these aren't under `features/auth`. Checked actual usage
before moving anything:

- `shared/auth/providers/AuthProvider` (`AuthProvider`/`useAuth`/
  `AuthContext`) is imported by ~30 files spanning **every** feature
  (booking, customers, daycare, discounts, grooming, maintenance,
  veterinary, staff) plus `App.tsx` and `SettingsPage.tsx` — not just
  auth-flow screens. It's the app's session state, consumed app-wide.
- `shared/auth/api/auth.api.ts` (`getSupabaseClient`, `getSession`,
  `signOut`, etc.) is imported by `shared/api/preferences.api.ts` (a
  `shared/` file) and by non-auth features like `maintenance.api.ts` and
  `UnavailabilityBlockBadge.tsx` — a `shared/` module depending on it.
- `shared/api/mfa.api.ts` and `shared/auth/mfa.types.ts` /
  `mfa.validator.ts` are consumed by `shared/components/TotpEnrollPanel`
  and `TotpChallengeForm` — again, `shared/` components depending on them.

Moving any of this into `features/auth` would make unrelated features (and
even other `shared/` files) import from `features/auth`, inverting the
"features depend on shared, not on each other" rule the rest of the codebase
follows. You confirmed keeping it in `shared/` — **no files were moved for
this part.**

### 4. Custom errors — server

`server/src/shared/errors/` already had an `AppError` hierarchy
(`NotFoundError`, `ValidationError`, `UnauthorizedError`, `ForbiddenError`,
`ConflictError`) plus `errorHandler.middleware.ts`, but there was no
machine-readable error `code` alongside the HTTP status — only the
human-readable `message`. Added:

- `AppError` gained a 4th constructor param, `code` (defaults to
  `'INTERNAL_ERROR'`), stored as `this.code`.
- Each subclass now passes its own code: `NOT_FOUND`, `VALIDATION_ERROR`,
  `UNAUTHORIZED`, `FORBIDDEN`, `CONFLICT`.
- New `InternalServerError` (500, code `SERVER_ERROR`) — an explicit,
  named class for intentional 500s, instead of always reaching for the
  generic `AppError(msg, 500)` (`storage.service.ts`'s existing throw still
  works unchanged, now defaulting to `INTERNAL_ERROR`).
- `errorHandler.middleware.ts` now includes `code` in every `AppError`
  response body (`{ error, code }`, or `{ error, code, details }` for
  `ValidationError`), and the final unrecognized-error 500 fallback now
  also returns `code: 'SERVER_ERROR'`.
- **Left untouched:** the legacy ad-hoc `.statusCode`-on-a-plain-`Error`
  branch (`requireMfa.middleware.ts`, `requireRole.middleware.ts`,
  `requireBranch.middleware.ts`, booking services, `staffAuth.controller.ts`,
  etc.) — per that branch's own comment, retrofitting those call sites to
  the `AppError` hierarchy was already flagged out of scope for a prior
  issue, so this change doesn't touch their response shape or add `code` to
  them.
- Updated `errorHandler.middleware.spec.ts` for the new `{ error, code }`
  contract and added coverage for `InternalServerError`.

### 5. Custom errors — client (page if routed, component if not)

- **`pages/NotFoundPage/`** — routed page. Added as the catch-all
  `<Route path="*">` in `routes.tsx`, so any unmatched URL now renders a
  proper "404 / Page not found" screen with a link home, instead of a blank
  page.
- **`pages/ServerErrorPage/`** — routed page at `/error`, shows
  "500 / Something went wrong" plus `Error code: SERVER_ERROR`. Not wired to
  auto-redirect from failed API calls (that would mean touching every
  feature's fetch layer, well beyond "add the custom error primitives") —
  it's available as a real, reachable route for anything that wants to send
  the user there.
- **`shared/components/ErrorBoundary/`** — unrouted component (a React
  class component; `componentDidCatch`/`getDerivedStateFromError` have no
  hook equivalent). Catches render-time crashes anywhere below it in the
  tree and shows an inline "Something went wrong" fallback with a
  **Try again** button, instead of the user seeing a blank white screen.
  Wired into `App.tsx`, wrapping `<AppRoutes />`.

## Verification performed

- Server: `npm run test` — 54 files / 500 tests passed. `npm run typecheck`
  — clean. `npm run lint` — clean (3 pre-existing `no-console` warnings,
  unrelated to this change).
- Client: `npm run test` — 78 files / 292 tests passed (including the
  relocated `StaffDashboardPage.spec.ts`/`DashboardTile.spec.ts` and the 3
  new spec files). `npx tsc -b` — clean. `npm run lint` — clean.
- Grepped the whole client tree for any leftover `dashboards/...` import —
  none found.

## How to verify yourself

1. From the repo root: `npm run dev` (client on :5173, server on :3000).
2. Log in as any staff account (e.g. `makati.groomer1` / `password123` —
   seed with `npm run seed:module-1` first if you haven't) and confirm you
   still land on `/staff/dashboard/groomer` with the usual tiles — the
   folder move should be invisible from the UI.
3. Visit a nonsense URL, e.g. `http://localhost:5173/this-does-not-exist` —
   confirm you see the new **404 / Page not found** page with a "Back to
   home" link, instead of a blank screen.
4. Visit `http://localhost:5173/error` directly — confirm you see the new
   **500 / Something went wrong** page with `Error code: SERVER_ERROR`.
5. To see the `ErrorBoundary` component (not a page — no direct URL):
   temporarily throw inside any page component (e.g.
   `throw new Error('test')` at the top of `StaffDashboardPage`), reload,
   confirm you get the inline "Something went wrong" / **Try again** panel
   instead of a blank page, then revert the temporary throw.
6. Server error `code` field: run `npm run test` in `server/` and open
   `src/shared/errors/errorHandler.middleware.spec.ts` — it asserts every
   `AppError` subclass's response now includes `code` (e.g. `NOT_FOUND`,
   `VALIDATION_ERROR`, `SERVER_ERROR`).

## No Postman collection for this request

The `code` field change only affects responses built from the `AppError`
hierarchy — but every currently-wired route error path in this codebase
still uses the pre-existing ad-hoc `.statusCode`-on-`Error` pattern (see
`errorHandler.middleware.ts`'s own comment), which this change deliberately
left alone. There's no live route today that actually throws a
`NotFoundError`/`ValidationError`/etc. to hit over HTTP, so there's nothing
new to exercise via Postman — the contract is verified by the updated unit
tests instead. No DB objects were touched either, so no SQL file accompanies
this doc.

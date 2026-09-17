---
title: Public — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, public]
project: golden-fur
---

Lets a logged-out visitor on the marketing site see the current Packages
and Promos catalog — bundled deals, savings math, and which branches offer
each one — without needing a customer or staff account. It's a thin,
read-only public window onto data that otherwise lives behind staff auth.

**Part of:** [[M13-maintenance-packages-services-promos|M13 · Maintenance (Packages, Services & Promos)]]. No dedicated M-code covers `public` itself — it's a small public-facing wrapper around M13's package/promo/service catalog (plus branch names from `branches`), not a module of its own.

## Client-side (`client/src/features/public/`)

- **`api/publicCatalog.api.ts`** — `fetchPublicPackagesPromos()` calls
  `GET /public/packages-promos` with no `Authorization` header, deliberately.
  Unlike `maintenance.api.ts`'s `listPackages`/`listPromos` (which need a
  staff `accessToken`), this is the version the public marketing pages call.
  It returns `{ data, error }` rather than throwing, parsing a server
  `{ error }` body on failure and falling back to a generic message if the
  response can't be parsed as JSON. Also defines the client-side
  `PublicPackage`/`PublicPromo`/`PublicPackagesPromos` types mirroring what
  the server returns.
- **`api/publicCatalog.api.spec.ts`** (test file) — checks the fetch call is
  made with no second `fetch` argument (i.e. no auth headers) and that a
  non-OK response surfaces the server's `error` message instead of throwing.

## Server-side (`server/src/features/public/`)

- **`public.routes.ts`** — mounts `GET /public/packages-promos`. The
  comment on the router is explicit: "no jwtMiddleware, no requireRole" —
  reserved for read-only content the marketing site needs before a visitor
  has signed up or logged in at all.
- **`public.controller.ts`** — `packagesPromosController` calls the service
  and returns its result as JSON. Because this route sits outside the
  jwt/role middleware chain, it doesn't flow into the app's global error
  handler either, so it formats errors itself the same way
  `maintenance.controller.ts`'s `sendServiceError` does (a `statusCode` off
  the thrown error, defaulting to 500 with a generic "Internal server
  error" message so internals aren't leaked to an anonymous caller).
- **`services/publicCatalog.service.ts`** — `getPublicPackagesPromos()` is
  a read-through that fetches packages, promos, branches, and services in
  parallel, then reshapes them for public display:
  - Packages and promos are loaded via `listPackages`/`listPromos` from
    `maintenance`'s services (using a service-role client), the same
    precedent `booking/services/catalog.service.ts` follows — public
    visitors never query the RLS-gated `packages`/`promos`/`services`
    tables directly.
  - `branch_names` is resolved per package/promo from
    `package_branch_availability`/`promo_branch_availability`, filtered to
    `is_available` rows, falling back to `'Unknown branch'` if a branch id
    can't be matched.
  - `included_services` resolves each package's `package_services` links
    against `listServices({ includeInactive: true })` — inactive services
    are included on purpose, so a package that bundled a service later
    deactivated still shows a name instead of silently dropping it (per
    the comment referencing `packages.service.ts`'s
    `assertServicesExistAndActive`).
  - `individual_total_price` sums the resolved services' `base_price`;
    `savings` is `individual_total_price - bundled_price`, floored at 0 so
    a package never displays as costing more than booking items
    separately.
- **`services/publicCatalog.service.spec.ts`** (test file) — covers the
  happy path (branch names, included services, and savings computed
  correctly) and the fallback path (unresolved branch id becomes "Unknown
  branch", an unresolved service link is dropped from `included_services`
  and excluded from the price/savings math).

## How it connects

Everything this feature returns is borrowed, not owned: packages, promos,
and services come from [[M13-maintenance-packages-services-promos|M13]]'s
maintenance services, and branch names come from the `branches` feature.
`public` adds no new data of its own — it exists only to expose an
already-active, already-public-facing subset of that catalog (active
packages/promos, with branch availability resolved to names) to a visitor
who hasn't logged in yet, while keeping the underlying tables gated behind
staff auth and RLS for everyone else.

---
title: Production deployment hardening (Vercel + Render + Supabase)
date: 2026-08-30
tags: [decision, deployment, vercel, render, supabase, infra, ops]
project: golden-fur
---

Source request (Matthew, 2026-08-30): open a `dev` → `main` PR, and
separately "fix deployment issues — the client side shows HTML only, no
CSS". Asked whether the cause was just `dev` not being merged, and flagged
that env vars are probably missing on Vercel/Render since a lot has changed.
Provided screenshots of the Vercel and Render dashboards.

> **Status: partially shipped.** Code + docs fixes are on golden-fur branch
> `fix/production-deploy-config` → PR
> [#126](https://github.com/the-golden-fur/golden-fur/pull/126) into `dev`.
> Dashboard config (Vercel/Render env vars, Supabase migrations) is
> Matthew's to do — runbook in
> [[57-production-deploy-config]].

Related: [[2026-08-29-online-payment-gate-and-downpayment-holds]] (PayMongo
KYC still pending — informs the "PayMongo stays dormant" decision below).

## What was actually wrong

Three independent problems, not one. Confirmed with live `curl` against the
production URLs plus a local production build.

### 1. Both hosts are frozen at Sprint 1

- Vercel (`golden-fur-client`) and Render (`golden-fur-server`) both deploy
  from `main`.
- `main` HEAD is `17cf1d3` — "land Sprint 1" — 2026-07-15. Render's last
  deploy was that day. `dev` is **114 commits / ~6 weeks / +139k LOC**
  ahead (booking, billing, hotel, veterinary, notifications, reports, the
  landing redesign).
- So everything built since mid-July is simply not live. This is the
  primary cause and merging `dev` → `main` is what fixes it — but it is
  **not sufficient** on its own (see #2, #3).

### 2. The landing page stylesheet is tree-shaken out of the prod build

- `client/src/pages/LandingPage/LandingPage.module.css` (1857 lines) was
  imported purely for its side effect: `import './LandingPage.module.css'`
  with no binding, in both `LandingPage.tsx` and `LandingNavbar.tsx`.
- Vite/rolldown treats an unused CSS-Modules import as side-effect-free and
  **drops it from the production bundle**. It works in `vite dev` (CSS is
  served eagerly), which is why it looked fine locally.
- Verified: the live `assets/index-*.css` (54 KB) contains the design
  tokens, reset, and `[data-theme]` rules but **zero** landing selectors —
  no `.navbar{`, `.hero{`, `.service-card{`. A local `vite build` on `dev`
  reproduces it exactly.
- This is still broken on `dev`. Merging alone would ship it still broken.

### 3. Missing deploy config

- **No `vercel.json` anywhere.** Vercel's Vite preset does not add an SPA
  fallback rewrite, so every route except `/` returns a hard 404
  (`/staff`, `/portal`, `/login`, any in-app refresh). Verified via `curl`.
- **`VITE_API_BASE_URL` is not set on Vercel.** Six client API modules fall
  back to `''` (same origin), so staff/customer login, MFA, profile, and
  preferences calls POST to the Vercel domain and 404 instead of hitting
  Render. (The live JS bundle has no `onrender.com` URL baked in — proof
  it's unset.)
- **Render is missing `SUPABASE_ANON_KEY`** (the dashboard shows only 6
  vars: `CORS_ALLOWED_ORIGINS`, `NODE_ENV`, `SERVER_PORT`,
  `SUPABASE_JWT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`) plus
  every var added since Sprint 1.
- **`CORS_ALLOWED_ORIGINS` on Render** almost certainly still points at
  `localhost:5173` — an unlisted browser origin is rejected outright.
- **Render `SERVER_PORT` vs `PORT`.** `app.ts` only read `SERVER_PORT`;
  Render injects `PORT`. The service is "Live" so port detection has been
  covering for it, but it's fragile.
- **Supabase**: the production project's schema is Sprint-1 era. `dev` has
  M03–M14 migrations. If the updated server boots against the old schema it
  500s everywhere — migrations must be pushed _before_ the server redeploys.

## Decisions

### Deploy topology stays as-is

Vercel (client) + Render (server, free tier) + hosted Supabase, all
deploying from `main`. `dev` is the integration branch; promoting `dev` →
`main` is the release action. Documented in `golden-fur/docs/deployment.md`
(new) — that file is now the source of truth, `render.yaml` (new) mirrors it
for the server.

### Fix the landing CSS by making it a real stylesheet, not a workaround

`LandingPage.module.css` → `LandingPage.css` (plain CSS). The file only ever
contained global + `:global(...)` selectors and was never used as a module
(no `styles.*` references anywhere in the codebase), so this is the correct
shape. All 233 `:global()` wrappers stripped (they're CSS-Modules-only
syntax — a browser ignores literal `:global(.x){}`). Plain `.css`
side-effect imports are always retained by the bundler.

### Resend is being replaced by Brevo — do not invest in Resend setup

Per Matthew: transactional email is moving from Resend to Brevo soon. Until
then, leave `RESEND_API_KEY` unset on any environment where email isn't
provisioned. Email-triggering flows will error there — that is **expected,
not a regression**. `.env.example` and `deployment.md` both note this.

### PayMongo and Facebook login stay dormant — keep the vars, don't populate them

The client has not approved creating a PayMongo account (see
[[2026-08-29-online-payment-gate-and-downpayment-holds]]) or a Facebook app.
The env vars (`PAYMONGO_*`) and the Supabase OAuth provider config stay in
place but unpopulated; the online-payment and FB-login paths stay inactive
(checkout 500s if hit). We are **not** removing them.

Future: add an explicit "disable online payments / disable login methods"
toggle in admin settings, so dormancy is a deliberate configured state
rather than an implicit consequence of absent keys.

### Pin Node ≥ 20

`engines.node >= 20` added to both `client/package.json` and
`server/package.json` — matches CI, keeps Render off an unexpectedly old
default.

## What shipped (golden-fur `fix/production-deploy-config`, PR #126)

- `LandingPage.module.css` → `LandingPage.css`, `:global()` stripped, both
  imports updated. Verified the built CSS now contains the landing rules
  (+28 KB). Client build + 730 tests green.
- `client/vercel.json` — framework/output pinned + SPA rewrite
  (`/(.*) → /index.html`; static files still win via Vercel's filesystem
  check).
- `server/src/app.ts` — `SERVER_PORT || PORT || 3000`.
- `render.yaml` + `docs/deployment.md` (linked from README) — topology, full
  env-var reference, `dev` → `main` runbook, verification `curl`s, known
  gotchas.
- `server/.env.example` — `DAYCARE_SESSION_CAPACITY` documented; Resend and
  PayMongo notes added.

## Not done (Matthew's, needs dashboard access)

Full runbook: [[57-production-deploy-config]]. In order:

1. Push Supabase migrations to the production project.
2. Add the missing Render env vars (`SUPABASE_ANON_KEY`, fix
   `CORS_ALLOWED_ORIGINS`, `STAFF_TEMP_CREDENTIAL_KEY`).
3. Merge PR #126 into `dev`, then open + merge `dev` → `main`.
4. Set `VITE_API_BASE_URL` on Vercel and redeploy.
5. Run the verification checklist.

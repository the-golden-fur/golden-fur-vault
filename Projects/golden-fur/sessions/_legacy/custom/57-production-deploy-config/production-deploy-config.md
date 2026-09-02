# Production Deploy Config — Fix & Release Runbook

Type: Custom (deployment fix + release). Not a sprint/epic backlog item.
Branch: `fix/production-deploy-config` → PR
[#126](https://github.com/the-golden-fur/golden-fur/pull/126) into `dev`.
Decision record: [[2026-08-30-production-deployment-hardening]].

Reported symptom: deployed client "shows HTML only, no CSS"; asked if it was
because `dev` isn't merged to `main`, and whether env vars are missing.

Answer: partly the merge gap (both hosts deploy from `main`, which is frozen
at Sprint 1, 2026-07-15), **plus** a real CSS bug a redeploy wouldn't fix,
**plus** missing config on both hosts. Full diagnosis in the decision record.

---

## What Claude already did (PR #126)

| Change                                                                                            | Effect                                                                                                                                                   |
| ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LandingPage.module.css` → `LandingPage.css`, `:global()` wrappers stripped, both imports updated | Landing stylesheet now ships in the production bundle (was tree-shaken out). Verified: built CSS gains `.navbar{` / `.hero{` / `.service-card{`, +28 KB. |
| `client/vercel.json` (new)                                                                        | Pins framework/output; adds SPA rewrite so every route (not just `/`) resolves and hard-refresh works.                                                   |
| `server/src/app.ts`                                                                               | Binds `SERVER_PORT \|\| PORT \|\| 3000` — Render's injected `PORT` now works without a manual override.                                                  |
| `render.yaml` + `docs/deployment.md` (new, linked from README)                                    | In-repo record of the Vercel/Render/Supabase topology, every env var, and the release runbook.                                                           |
| `server/.env.example`                                                                             | `DAYCARE_SESSION_CAPACITY` documented; Resend→Brevo and PayMongo-dormant notes added.                                                                    |
| `engines.node >= 20` in both `package.json`s                                                      | Matches CI; keeps Render off an old default.                                                                                                             |

Local verification done: `client` build (tsc + vite) green, 730 client tests
green, server `tsc --noEmit` + eslint green, prettier clean on touched files,
built CSS manually confirmed to contain the landing rules with no `:global`.

Not verifiable from here: the Vercel PR-preview is behind Vercel SSO
(Deployment Protection = Standard), and Render/Supabase need dashboard
access.

---

## What Matthew needs to do — in this order

> Do steps 1–2 **before** the server redeploys. A server on new code against
> the old Supabase schema 500s across the board.

### 1. Supabase — push migrations to production

```bash
cd golden-fur
npm run supabase:login
npm run supabase:link       # pick the PRODUCTION project ref
npm run supabase:status     # review local vs remote — expect a long pending list (M03–M14)
npm run supabase:push
```

Then in the Supabase dashboard:

- Confirm the project isn't paused (free tier pauses after ~1 week idle).
- Auth → URL Configuration → Redirect URLs must include
  `https://golden-fur-client.vercel.app`.

### 2. Render — `golden-fur-server` → Environment

Currently set (from the screenshots): `CORS_ALLOWED_ORIGINS`, `NODE_ENV`,
`SERVER_PORT`, `SUPABASE_JWT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`,
`SUPABASE_URL`.

**Add / fix:**

| Variable                    | Action      | Value                                                                                                                                                                                                        |
| --------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `SUPABASE_ANON_KEY`         | **add**     | production anon/publishable key                                                                                                                                                                              |
| `CORS_ALLOWED_ORIGINS`      | **change**  | `https://golden-fur-client.vercel.app` (+ any custom domains). Comma-separated, no spaces, no trailing slash. Currently almost certainly `http://localhost:5173`.                                            |
| `STAFF_TEMP_CREDENTIAL_KEY` | **add**     | base64 → exactly 32 bytes. Reuse the value already in your local `server/.env`, or `openssl rand -base64 32` (a new one just means existing stored temp passwords can't be decrypted — fine if none matter). |
| `NODE_ENV`                  | verify      | `production`                                                                                                                                                                                                 |
| `SERVER_PORT`               | leave as-is | it's been working; `app.ts` now also honours Render's `PORT`                                                                                                                                                 |

**Do NOT add** (deliberately dormant — see decision record):

- `RESEND_API_KEY` / `RESEND_FROM_EMAIL` — email is moving to Brevo. Flows
  that send email will error until then. Expected.
- `PAYMONGO_*` — no client-approved account yet. Online-payment/checkout
  paths 500 if exercised. Expected.

### 3. Merge PR #126 → `dev`

Review + merge [#126](https://github.com/the-golden-fur/golden-fur/pull/126)
(squash, per `pr-to-dev`).

### 4. Open + merge `dev` → `main`

Use the `pr-dev-to-main` skill (rebase merge preferred, never squash). This
is the Sprint-1 → current promotion — 114 commits. Merging auto-triggers
**both** the Vercel build and the Render deploy. Watch both dashboards' logs.

### 5. Vercel — `golden-fur-client` → Settings → Environment Variables

For **Production** and **Preview**:

| Variable                 | Action  | Value                                    |
| ------------------------ | ------- | ---------------------------------------- |
| `VITE_API_BASE_URL`      | **add** | `https://golden-fur-server.onrender.com` |
| `VITE_SUPABASE_URL`      | verify  | production Supabase URL                  |
| `VITE_SUPABASE_ANON_KEY` | verify  | production anon key                      |

Then **Deployments → Redeploy** (env changes don't rebuild on their own).
`vercel.json` now pins Root Directory `client` / framework / output, so no
other dashboard change is needed.

### 6. Verify

```bash
curl -s https://golden-fur-server.onrender.com/health
#   {"status":"ok"}   (first hit after idle can take 30–60s — free instance cold start)

curl -sI https://golden-fur-client.vercel.app/staff/login | head -1
#   HTTP/2 200         (was 404 — SPA rewrite)

CSS=$(curl -s https://golden-fur-client.vercel.app/ | grep -oE '/assets/index-[^"]+\.css')
curl -s "https://golden-fur-client.vercel.app$CSS" | grep -o '.hero{'
#   .hero{            (landing stylesheet is in the bundle)
```

In a browser:

- `/` is fully styled — navbar, hero, service cards, footer.
- Hard-refresh on `/staff` and `/portal` — no 404.
- Staff login works end to end. Network tab: requests go to
  `golden-fur-server.onrender.com`, not the Vercel domain. No CORS errors in
  the console.
- One booking flow end to end (exercises the freshly-migrated schema).
- Expected to NOT work yet: anything that sends an email; online
  (GCash/Maya) payment. Both are dormant by decision.

---

## Rollback

- Vercel and Render both keep prior deploys — "Rollback" / "Redeploy" a
  previous build from either dashboard.
- Supabase migrations are forward-only; a bad migration needs a new
  corrective migration, not a rollback. Review the `supabase:status` diff
  carefully before step 1.

## Follow-ups (backlog)

- Brevo migration for transactional email (replaces Resend).
- Admin setting: explicit "disable online payments" / "disable login
  methods" toggles, so dormant integrations are a configured state, not an
  implicit consequence of missing keys.
- Consider a keep-alive ping to `/health` or a paid Render instance to kill
  the cold-start delay.
- `client/package.json` still has `"golden-fur": "file:.."` — vestigial
  (nothing imports it). Harmless; remove opportunistically.

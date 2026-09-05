# Server production build step (esbuild) + local dist/ cleanup scripts

Branch: `perf/server-esbuild-build-dist-clean` (golden-fur) · vault:
`docs/server-build-step-session-70` (this session record itself).

## The request, verbatim

> read project files > golden fur repo > client and server directory
> see if they need a dist/ directory
> I heard that it's necessary to make the app run faster
> and what happens if I create a dist directory in both client and server?
> I assume I need to change the root directory for vercel and render to
> dist/?
> should dist be pushed to dev/main?

> Scope note — a mid-session follow-up, same person, chat only, sent
> alongside screenshots of the Render "Build" settings page and the Vercel
> "Build and Development Settings" / "Framework Settings" pages:
>
> your goal might eb to optimize build commands, clean the dist locally, etc.

> Follow-up clarifying question and answer — asked because a plain `tsc`
> build step and a bundled `esbuild` build step are meaningfully different
> in risk and effect: "Add a real server build step (Recommended), do what
> else is industry standard."

## Root cause / Context

Not a bug — a missing optimization, found while answering the original
dist/ question. Investigation of the actual repo config confirmed:

- **Client** was already correct: `client/vercel.json` already sets
  `outputDirectory: "dist"`, Vite already produces `client/dist/` on
  `npm run build`, and Root Directory in Vercel was already `client`
  (confirmed against the user's own Vercel screenshot).
- **Server** had no build step: `server/package.json`'s `start` script ran
  `tsx src/app.ts`, which transpiles TypeScript to JavaScript at every
  process boot — in production on Render, not just locally (confirmed
  against the user's own Render screenshot: Build Command was `npm install`,
  Root Directory `server`, no compiled output anywhere).
- `docs/deployment.md` already flagged Render free-tier cold starts as a
  known pain point; the per-boot transpile cost sat directly on top of that.

A naive `"build": "tsc -b"` was ruled out during planning: `server/tsconfig.json`
has `allowImportingTsExtensions: true`, and every server source file imports
its neighbors with an explicit `.ts` extension (e.g. `server/src/app.ts`'s
`import appRoutes from './shared/app.routes.ts'`). TypeScript refuses to emit
JavaScript at all while that option is on, and even without it, plain `tsc`
doesn't rewrite `.ts` endings to `.js` in its output — `node dist/app.js`
would try to `import` files that don't exist. `esbuild` in bundle mode
avoids this: bundling inlines every local file into one output, so no
cross-file import specifiers survive to break at runtime.

## What changed

### Server

- `server/package.json`:
  - New `build` script:
    `esbuild src/app.ts --bundle --platform=node --format=esm --target=node20 --packages=external --sourcemap --outfile=dist/app.js`
  - `start` changed from `tsx src/app.ts` to `node dist/app.js`
  - New `clean` script: `rimraf dist`
  - `esbuild` added to `dependencies` (not `devDependencies` — Render's
    build environment has `NODE_ENV=production` set, which makes `npm`
    skip `devDependencies` during install; `esbuild` must survive that)
  - `tsx` moved from `dependencies` to `devDependencies` — production no
    longer touches it; it's still used by `npm run dev`'s watch mode
  - `rimraf` added to `devDependencies` (cross-platform `dist` deletion,
    matters since local dev here is Windows)
  - `dev`, `predev`, and `typecheck` scripts unchanged
- `server/tsconfig.json`: untouched — `esbuild` doesn't read its
  `noEmit`/`outDir` settings, and `typecheck` (`tsc --noEmit`) remains the
  real type-safety gate, unaffected by the new build step

### Client

- `client/package.json`: added a `clean` script (`rimraf dist`) and
  `rimraf` to `devDependencies`. No other client changes — its build/output
  configuration was already correct.

### Root / deploy config

- `package.json` (repo root): added `clean` — runs both `client`'s and
  `server`'s `clean` scripts in one shot, matching the existing
  `concurrently`-based orchestration pattern already in this file.
- `render.yaml`: `buildCommand` changed from `npm install` to
  `npm ci && npm run build` (also swaps to `npm ci` for reproducible
  installs against the committed lockfile, a minor standard-practice
  addition alongside the core change). `startCommand` (`npm start`) is
  unchanged in the file — it now resolves to the new compiled entrypoint
  under the hood.
- `docs/deployment.md`: server section's Build/Start Command description
  updated to describe the compiled build instead of "no build step; tsx
  runs the TypeScript directly."

## Manual test — step by step

This is a backend build/deploy change with no UI surface — verification was
done from the command line, not the browser.

1. In `server/`, run `npm run build`. Expected: `dist/app.js` and
   `dist/app.js.map` are created; no errors.
2. Run `node dist/app.js` (with the usual local `.env` present), then in
   another terminal run `curl http://127.0.0.1:3000/health`. Expected:
   `{"status":"ok"}` — the same response the old `tsx`-run server gave.
3. In `server/`, `client/`, and the repo root, run `npm run clean`.
   Expected: each `dist/` folder is deleted.
4. **Still needed on the live Render service** (not done as part of this
   session — `render.yaml` documents the intended settings but isn't
   auto-applied): open the Render dashboard → `golden-fur-server` →
   Settings → Build, and change the **Build Command** field from
   `npm install` to `npm ci && npm run build`, matching `render.yaml`. The
   **Start Command** field does not need editing — it's already `npm start`.
   After that's saved, the next deploy will exercise the new build step for
   real; check the Render deploy log for the `esbuild` build output, then
   `curl https://golden-fur-server.onrender.com/health` to confirm it still
   answers.

## Test suites

- `server`: `npm run build` — succeeds, `dist/app.js` (540.2kb) +
  `dist/app.js.map` (1.4mb) produced in 82ms.
- `server`: manual boot test — `node dist/app.js` then
  `curl http://127.0.0.1:3000/health` → `{"status":"ok"}`.
- `server`: `npm run typecheck` (`tsc --noEmit`) — clean, no errors.
- `server`: `npm run lint` — 0 errors, 31 warnings, all pre-existing
  `no-console` warnings unrelated to this change.
- `server`: `npm test` (vitest) — 972/972 tests passing (88 files).
- Root: `npm run format:check` — clean on every file this session touched
  (one unrelated pre-existing Windows-CRLF formatting warning on a file
  this session never edited was left alone, not fixed — out of scope).
- `npm run clean` (root, client, server) — confirmed each removes its
  `dist/` folder.

## Open items

- The live Render dashboard's Build Command field still needs to be updated
  by hand (see step 4 above) — `render.yaml` alone does not push this
  change to the running service.
- Committed on `perf/server-esbuild-build-dist-clean` (golden-fur) and
  `docs/server-build-step-session-70` (this session record, vault); PRs to
  `dev` and `main` respectively opened as the closing step of this session.

---
title: Give the server a real production build step (esbuild), stop transpiling TypeScript at every boot
date: 2026-09-05
tags: [session-plan, golden-fur]
project: golden-fur
session: 70-server-build-step-and-dist-clean
branch: perf/server-esbuild-build-dist-clean
---

# 70 — Give the server a real production build step

## What you asked for

The conversation started as a question, not a change request — whether
`client/` and `server/` need a `dist/` folder, what would happen if one were
created by hand, and whether Vercel/Render's "Root Directory" setting should
point at it. Partway through, the goal shifted to actually making a change:

> your goal might eb to optimize build commands, clean the dist locally, etc.

Asked how far to take "optimize build commands" specifically, the answer was:

> Add a real server build step (Recommended), do what else is industry
> standard

## What this part of the app does today

- **`client/`** — the Vite-built React app (Customer Portal + Staff Console).
  **Vite** is the tool that turns the app's TypeScript/JSX source into the
  plain, minified JavaScript+CSS a browser actually runs. Running
  `npm run build` here already produces a `client/dist/` folder, and
  `client/vercel.json` already tells Vercel (the host serving the client) to
  read its build output from exactly that folder. This part was already
  correct — nothing needed to change about it besides a convenience script
  (see below).
- **`server/`** — the Express API backend. Unlike the client, it had **no
  build step at all**. Its `start` script ran `tsx src/app.ts` — `tsx` is a
  tool that reads TypeScript source and converts ("transpiles") it into
  JavaScript **on the fly, every time the process starts**, rather than once
  ahead of time. That happens identically in local development and in
  production on Render (the host running the server).
- **Render's free tier** spins the server process down after ~15 minutes of
  no traffic. The next request has to wait for the process to start back up
  — a "cold start" — and every cold start was paying the full
  transpile-the-whole-app cost on top of just starting Node itself.

## What's wrong / what's missing

Nothing was broken — the app worked correctly either way. The
inefficiency was that **every single server boot re-did the same
TypeScript-to-JavaScript conversion work**, instead of doing it once at
deploy time and simply running the already-converted JavaScript afterward.
That's the "optimize build commands" ask: move that conversion out of the
hot path (every process start) and into the build step (once, per deploy).

## What we're going to change

1. **Add a real compile step for the server, using `esbuild`.** — _Which
   files:_ `server/package.json`'s new `build` script — _Why:_ `esbuild` is
   a fast bundler (a tool that reads a program's entire file tree and
   produces one merged, plain-JavaScript output file). It's the same
   underlying engine `tsx` already uses, just run once instead of on every
   boot. A plain `tsc` (TypeScript's own compiler) could **not** be used
   here — see "Words you might not know" for why — so `esbuild` in "bundle"
   mode is the fix that actually works with this codebase's existing import
   style.
2. **Point `start` at the compiled file instead of `tsx`.** — _Which files:_
   `server/package.json`'s `start` script now runs `node dist/app.js`
   directly — _Why:_ this is the actual speed win: production no longer
   transpiles anything at boot, it just runs already-converted JavaScript.
   `tsx` stays in use for local development (`npm run dev`), where its
   instant-restart-on-save behavior is still the better trade-off than
   rebuilding a bundle on every keystroke.
3. **Add a `clean` script that deletes the local `dist/` folder.** — _Which
   files:_ `server/package.json`, `client/package.json`, and the root
   `package.json` (a `npm run clean` shortcut that runs both) — _Why:_
   directly answers the "clean the dist locally" part of the ask — a
   convenience for wiping out a stale local build output.
4. **Tell Render to actually run the new build step.** — _Which files:_
   `render.yaml` (`buildCommand` now runs `npm ci && npm run build` instead
   of just `npm install`) — _Why:_ without this, Render would still just
   `npm install` and then try to run `node dist/app.js`, which wouldn't
   exist yet. `render.yaml` documents the intended Render settings but isn't
   automatically applied to the already-existing service — the live
   service's dashboard **Build Command** field needs the same edit by hand.
5. **Update the deployment doc to match.** — _Which files:_
   `docs/deployment.md`'s server section — _Why:_ it previously described
   "no build step; tsx runs the TypeScript directly," which stopped being
   true.

## Words you might not know

- **transpile** — convert code from one form to a functionally-equivalent
  other form; here, TypeScript source into plain JavaScript a browser or
  Node.js can run directly (TypeScript's extra type annotations aren't
  understood by either).
- **bundler** — a tool that starts at one entry file, follows every `import`
  it uses, and produces a single merged output file containing everything
  the program needs. `esbuild` and Vite both are bundlers; `tsx` uses the
  same technology but only transpiles, without necessarily bundling into a
  single output.
- **cold start** — the delay a server pays when it has to start up from
  fully stopped, as opposed to already being warm and running. Render's free
  tier stops the server after a period of no traffic, so the next visitor
  after that pays a cold start.
- **why plain `tsc` couldn't be used** — this codebase's server files import
  each other with an explicit `.ts` file ending (e.g.
  `import appRoutes from './shared/app.routes.ts'`), a convention that only
  works today because `tsx` specially tolerates it at runtime. TypeScript's
  own compiler refuses to produce JavaScript output at all while that
  convention (`allowImportingTsExtensions`) is turned on, and even if it
  didn't refuse, it wouldn't rewrite those `.ts` endings to `.js` in the
  files it produces — so the compiled server would immediately crash trying
  to import files that don't exist. Bundling everything into one file with
  `esbuild` sidesteps the problem entirely: once bundled, there are no
  cross-file `import` statements left to break.
- **dependencies vs. devDependencies** — two lists in `package.json`.
  `dependencies` are installed everywhere, including in production;
  `devDependencies` are meant for local/build-time tools only. `esbuild` had
  to go in `dependencies` (even though it only runs during the build) because
  Render's build environment has `NODE_ENV=production` set, and `npm`
  skips installing `devDependencies` when that variable is present during
  install — a well-known Render gotcha.

## How you'll know it worked

See `testing/testing.md` for the verification record.

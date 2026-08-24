# Issue #37 Verification: Storage Service + Error Classes + CORS Config

**Issue:** #37 — feat(shared): storage service + error classes + CORS config
**Owner:** Matthew
**Branch:** `feat/shared-storage-errors-cors`
**Base:** `dev`
**Depends on:** Epic B #23 merged (avatars bucket + Storage RLS)
**Sprint:** Sprint 1 — Epic D — `shared/`

## Overview

Adds a typed error class hierarchy with one centralized Express error handler,
a bucket-agnostic Supabase Storage wrapper, and an explicit, environment-driven
CORS configuration. All three were previously empty scaffold files (0 bytes,
present since the initial commit) at `server/src/shared/middleware/error/`,
`server/src/errors/`, and `server/src/config/cors/` — none were referenced
anywhere in the codebase. This issue implements the real versions at the paths
the Guide/Design workbook specify (`server/src/shared/errors/`,
`server/src/shared/services/storage/`, `server/src/shared/config/cors/`) and
removes the dead stub folders.

## What Changed

- **Added** `server/src/shared/errors/AppError.ts` — base class
  (`message`, `statusCode`, `isOperational`).
- **Added** `NotFoundError` (404), `ValidationError` (400, optional
  `details`), `UnauthorizedError` (401), `ForbiddenError` (403),
  `ConflictError` (409) — all extend `AppError`.
- **Added** `server/src/shared/errors/index.ts` — barrel export.
- **Added** `server/src/shared/errors/errorHandler.middleware.ts` — the
  centralized Express 4-arg error handler, registered last in `app.ts`, after
  `appRoutes`.
- **Added** `server/src/shared/services/storage/storage.service.ts` —
  `upload(bucket, path, file)`, `getPublicUrl(bucket, path)`,
  `remove(bucket, path)`, generalizing the bucket-specific logic Epic B wrote
  inline in `avatarUpload.service.ts`. Storage failures throw `ConflictError`/
  `AppError` rather than surfacing raw Supabase errors.
- **Added** `server/src/shared/config/cors/cors.config.ts` — builds the
  `cors()` options object from `CORS_ALLOWED_ORIGINS` (comma-separated,
  trimmed); rejects any Origin not on the list.
- **Modified** `server/src/app.ts` — registers `cors(corsOptions)` ahead of
  route mounting and `errorHandler` last, after `appRoutes`.
- **Removed** the dead empty stub folders: `server/src/shared/middleware/error/`,
  `server/src/errors/`, `server/src/config/cors/` (all unreferenced, all
  0-byte placeholder files from the initial commit).
- **Added** `@types/cors` as a server devDependency (the `cors` package ships
  no types of its own).

### Deliberate deviation from the literal AC-2 wording — read before reviewing

AC-2 says: "An unrecognized thrown `Error` (not an `AppError` subclass)
responds with 500 and a generic message." Implemented literally, this broke 4
previously-passing integration tests: `requireMfa.middleware.ts`,
`requireRole.middleware.ts`, `jwt.middleware.ts`, and `staffAuth.controller.ts`
(all pre-Epic-D, per the epic's own Out of Scope section) throw a plain
`Error` with a manually bolted-on `.statusCode` — e.g. `403` for a forbidden
role. Before this issue, there was **no** custom error middleware, so
Express's own default final handler was in effect, and it _does_ honor
`err.status`/`err.statusCode` on any thrown object. Registering a strict
"only `AppError` gets its real status, everything else is 500" handler
silently turned every one of those pre-existing 401/403 rejections into a 500.

`errorHandler.middleware.ts` therefore has three branches, not two:

1. `err instanceof AppError` → its own `statusCode` + `{ error }` (+ `details`
   for `ValidationError`).
2. A plain `Error` with a numeric `.statusCode` property (the ad hoc pattern
   from Epics A/A-1/B) → that `statusCode` + `{ error: err.message }`.
3. Anything else (truly unrecognized — a raw exception, a bare thrown string,
   a Supabase error object with no status) → logged server-side, `500` with a
   generic message.

This keeps AC-2's actual intent — "don't leak internals for an exception
nobody anticipated" — while not silently regressing the three already-shipped
epics that this issue's own Out of Scope section says are _not_ being
retrofitted. Flagging this for the client/reviewer since it reads as a
correction to AC-2's literal text, not just an implementation detail.

## Automated Verification

Run from the repo root in PowerShell:

```powershell
npm --prefix server test -- --run
npm --prefix server run typecheck
npm --prefix server run lint
```

Expected: 257/257 server tests pass (10 in `errorHandler.middleware.spec.ts`,
6 in `storage.service.spec.ts`, 4 in `cors.config.spec.ts`, plus every
previously-existing test — including the 4 that would have regressed under a
literal AC-2 implementation — still green). `tsc --noEmit` produces no
output. `eslint .` reports only the 3 pre-existing `no-console` warnings in
`customerAuth.controller.ts`/`staffAuth.controller.ts` (unrelated to this
issue).

## Structural Verification

1. Confirm the new files exist and the dead stubs are gone:

   ```powershell
   Get-ChildItem server/src/shared/errors
   Get-ChildItem server/src/shared/services/storage
   Get-ChildItem server/src/shared/config/cors
   Test-Path server/src/shared/middleware/error   # expect: False
   Test-Path server/src/errors                    # expect: False
   Test-Path server/src/config/cors               # expect: False
   ```

2. Confirm `app.ts` registers both in the right order:

   ```powershell
   Get-Content server/src/app.ts
   ```

   Expected: `cors(corsOptions)` before `app.use(appRoutes)`; `errorHandler`
   is the last `app.use(...)` call.

## Postman Verification

Exercises CORS and the centralized error handler through **existing** routes
(this issue adds no new route paths of its own — it's cross-cutting
infrastructure). Needs `server/.env`'s `CORS_ALLOWED_ORIGINS` to include
`http://localhost:5173` (the Sprint 0 default).

### A. Start the server

```powershell
npm --prefix server run dev
```

### B. Import and run the collection

1. Postman → **Import** →
   `testing/docs/issues/37-shared-storage-errors-cors/shared-storage-errors-cors.postman_collection.json`.
2. Collection **Variables** tab → confirm `base_url` is `http://localhost:3000`
   (adjust if `SERVER_PORT` differs) and `allowed_origin` matches an entry in
   your `CORS_ALLOWED_ORIGINS`.
3. Run requests **1 → 4** in order. Each has a **Tests** tab that asserts
   automatically.

| #   | Request                                            | Expected                                                                                                                                                                        |
| :-- | :------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | AC-4: GET /health from an allowed Origin           | `200`; `Access-Control-Allow-Origin` header echoes `allowed_origin`                                                                                                             |
| 2   | AC-4: GET /health from a disallowed Origin         | Blocked by CORS — response has no `Access-Control-Allow-Origin` header (falls through to the generic 500 branch of `errorHandler`, since the CORS rejection is a plain `Error`) |
| 3   | AC-1/AC-2: GET /staff with no Authorization header | `401`, `{ "error": "Missing or malformed token" }` — proves `errorHandler`'s legacy-`.statusCode` branch still works for pre-Epic-D middleware                                  |
| 4   | AC-5: comma-separated CORS_ALLOWED_ORIGINS parses  | Manual check — see note below                                                                                                                                                   |

**Note on request 4:** parsing of comma-separated, whitespace-padded origins
is covered by the 4 unit tests in `cors.config.spec.ts` (AC-5) rather than a
live request, since it requires restarting the server with a different
`CORS_ALLOWED_ORIGINS` value to observe. To check manually: set
`CORS_ALLOWED_ORIGINS=http://localhost:5173, http://localhost:4000 ` (note the
padding) in `server/.env`, restart `npm --prefix server run dev`, and re-run
request 1 with `allowed_origin` set to `http://localhost:4000` — expect the
same `200` + echoed header result.

## Acceptance Criteria Checklist

- [x] **AC-1:** `NotFoundError`/`ValidationError`/`UnauthorizedError`/
      `ForbiddenError`/`ConflictError` map to their `statusCode` and
      `{ error }` body (+ `details` for `ValidationError`) — unit tests in
      `errorHandler.middleware.spec.ts`.
- [x] **AC-2:** an unrecognized thrown `Error` responds `500` with a generic
      message and no leaked internals — unit test `falls back to 500...`;
      see the deviation note above re: legacy `.statusCode` errors.
- [x] **AC-3:** `storage.service.ts`'s `upload()` returns a usable URL on
      success and throws a typed error on failure; `remove()` deletes the
      target object — unit tests in `storage.service.spec.ts`.
- [x] **AC-4:** allowed-origin request succeeds, disallowed-origin request is
      rejected — unit tests in `cors.config.spec.ts`; Postman requests 1-2.
- [x] **AC-5:** comma-separated multi-origin values parse correctly,
      including surrounding whitespace — unit test
      `parses a comma-separated multi-origin value...`.
- [x] **AC-6:** `app.ts` registers `cors(corsOptions)` before route mounting
      and `errorHandler` after `appRoutes`; server starts without error under
      `development` and `test` `NODE_ENV` — confirmed by the full test suite
      (which boots the app via `supertest`) and by `npm --prefix server run dev`.

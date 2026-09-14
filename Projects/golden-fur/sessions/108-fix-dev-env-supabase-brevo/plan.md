---
title: Point dev's .env at the right Supabase project and fix stale email keys
date: 2026-09-15
tags: [session-plan, golden-fur]
project: golden-fur
session: 108-fix-dev-env-supabase-brevo
branch: dev
---

# 108 — Point dev's .env at the right Supabase project and fix stale email keys

## What you asked for

A review of the local `.env` files against a screenshot of the Google/Supabase
OAuth console (`golden-fur-vault/temp.txt`) turned up two problems, then:

> proceed with your suggestions
> we're at dev branch, so it should point to the golden-fur-dev
> later, you may switch to main and make its env point to golden-fur
> edit the .example.env files in dev, BUT DONT EDIT THEM IN main

## What this part of the app does today

`golden-fur` is a booking app for a pet grooming/hotel/daycare business. It has
two halves that both run locally: `server/` (an Express API on port 3000) and
`client/` (a React app on port 5173, via Vite). Both halves talk to
**Supabase** — a hosted Postgres database plus an authentication service.
Supabase organizes each customer into a **project**, identified by a random-
looking id (e.g. `hikgijuipymfghfuyrjv`) and given a friendly name in the
Supabase dashboard.

This business actually has **two** Supabase projects: one named
`golden-fur-dev` (for local development) and one named `golden-fur` (the real
one, meant for the `main` branch / production). Each project has its own set
of keys: a **URL**, an **anon key** (safe to expose to a browser; access is
still restricted by database rules), a **service role key** (full access,
server-only, never exposed to the browser), and a **JWT secret** (used to
check that a login token was really issued by that Supabase project).
Supabase also recently introduced a newer key format —
`sb_publishable_...` / `sb_secret_...` — as a replacement for the older
`eyJ...`-style keys (called "legacy JWT" keys here); both formats work today,
the new one is just easier to rotate individually later.

Each half of the app reads its own `.env` file (`server/.env`,
`client/.env`) for these values. `.env` files are deliberately **not** tracked
by git (see `.gitignore`) — every developer's copy is local and hand-edited.
Alongside each real `.env` is a tracked `.env.example`, which only has
placeholder values and exists purely as a template/reference for whoever sets
up the project fresh.

The server also sends transactional emails (e.g. staff temp-password resets)
through **Brevo**, a third-party email-sending service, using a `BREVO_API_KEY`
and `BREVO_FROM_EMAIL` pair read from `server/.env`
(`server/src/shared/email/brevo.client.ts`).

## What's wrong / what's missing

1. **Wrong Supabase project.** Both `server/.env` and `client/.env` on this
   `dev` branch point at the `golden-fur` project (the one meant for `main`),
   instead of `golden-fur-dev`.
2. **Stale email keys.** `server/.env` still has leftover `RESEND_API_KEY` /
   `RESEND_FROM_EMAIL` lines from before the app switched email providers to
   Brevo. The code only ever reads `BREVO_API_KEY` / `BREVO_FROM_EMAIL` — so
   right now, any email-sending code path fails immediately with
   `BREVO_API_KEY is not configured`, and the leftover Resend key/value is
   just dead, confusing config.
3. **Inconsistent key format.** `server/.env`'s anon key already uses the new
   `sb_publishable_...` format, but `client/.env`'s anon key uses the older
   `eyJ...` format — both point at the same project, just in different
   formats, which is confusing to read.
4. **No documented convention.** Nothing in either `.env.example` file
   explains that `dev` and `main` are meant to point at two different
   Supabase projects, so a new developer has no way to know this by reading
   the example file alone.

## What we're going to change

1. **Re-point `server/.env` and `client/.env` at `golden-fur-dev`.** —
   _Which files:_ `server/.env`, `client/.env` — _Why:_ this is the `dev`
   branch; its local environment should use the dev Supabase project, not the
   one meant for `main`. The actual URL/keys come from
   `golden-fur-vault/temp.txt`'s "golden-fur-dev" section (never restated
   here — see the secrets note below). Both `SUPABASE_ANON_KEY` /
   `VITE_SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` will use the newer
   `sb_publishable_...` / `sb_secret_...` format, so server and client match.
2. **Rename the stale email variables.** — _Which files:_ `server/.env` —
   _Why:_ `RESEND_API_KEY`/`RESEND_FROM_EMAIL` → `BREVO_API_KEY`/
   `BREVO_FROM_EMAIL`, matching what `brevo.client.ts` actually reads. The
   real Brevo Development key (already shared with the assistant directly in
   chat, not written here — see secrets note) goes in as the value.
   `BREVO_FROM_EMAIL` needs a verified-sender address confirmed by the human
   working on this before it's set for real.
3. **Document the branch-to-project convention.** — _Which files:_
   `server/.env.example`, `client/.env.example` (on `dev` only) — _Why:_ add a
   short comment noting that `dev` targets `golden-fur-dev` and `main` targets
   `golden-fur`, so this doesn't have to be rediscovered later. `main`'s copies
   of these two files are explicitly left untouched.
4. **(Later, separate step) Mirror this on `main`.** — _Which files:_
   `server/.env`, `client/.env` on the `main` branch — _Why:_ once this `dev`
   change is confirmed working, do the equivalent switch on `main`, pointing
   at the `golden-fur` project and using the Brevo **Production** key
   (already shared in chat). `main`'s `.env.example` files stay untouched.

### A note on secrets

None of the real values (Supabase keys, JWT secret, Brevo API keys) are
written in this plan file, on purpose — this file is version-controlled in
the vault repo, and secrets don't belong in git history. The actual values
are copied directly from `golden-fur-vault/temp.txt` (Supabase) and from the
values the human shared directly in the chat session (Brevo), straight into
the local, git-ignored `.env` files, with nothing copy-pasted through this
document.

## Words you might not know

- **Supabase project** — a self-contained hosted database + auth service
  instance; this app uses two of them (one for `dev`, one for `main`/prod).
- **anon key** — a Supabase API key meant to be used from the browser; safe to
  expose because the database's row-level security rules, not the key, are
  what actually restrict access.
- **service role key** — a Supabase API key with full database access,
  bypassing row-level security; must only ever live on the server, never in
  browser-shipped code.
- **JWT (JSON Web Token) secret** — a shared secret Supabase uses to sign
  login tokens; the server uses it to verify a token wasn't forged.
- **`sb_publishable_` / `sb_secret_`** — Supabase's newer key naming scheme,
  replacing the older `eyJ...`-style anon/service-role keys; functionally
  equivalent today, easier to rotate individually.
- **`.env` vs `.env.example`** — `.env` holds real, secret values and is never
  committed to git; `.env.example` is a checked-in template with placeholder
  values only.
- **Brevo** — the third-party service this app uses to actually send emails
  (password resets, notifications); needs an API key and a verified sender
  address to work.

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks (restart both dev
servers, confirm the app can log in against `golden-fur-dev`, confirm no
`RESEND_` variables remain, confirm `git status` shows only the two
`.env.example` files as changed and never shows the real `.env` files).

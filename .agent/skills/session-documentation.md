# Session documentation

**Purpose:** every AI session (one Claude / Codex / Gemini request thread that
changes the `golden-fur` app) leaves a durable record in this vault — a plan
written so a near-beginner can follow it, a literal click-by-click test
script, and copies of the context files the session used. This is the
project's running changelog. It supersedes the old
`Projects/golden-fur/testing/{custom,issues}/` convention (that tree is
kept verbatim under `Projects/golden-fur/sessions/_legacy/`).

**Use whenever** you (or another AI tool) finish implementing a change in the
`golden-fur` repo — a bug fix, a feature, a schema migration, an architecture
change — in response to a specific request. Write the record as the closing
step of that work, not as a separate follow-up.

**Skip it** for pure vault-only changes (nothing changed in `golden-fur`) and
for trivial non-functional edits (typo fixes, comment wording, formatting-only
diffs) with nothing a human would ever re-verify.

## Where it goes

**One self-contained folder per session:**
`Projects/golden-fur/sessions/NN-<slug>/`

```
Projects/golden-fur/sessions/NN-<slug>/
  plan.md                                  always — the near-beginner plan
  testing/
    testing.md                             always — verification record + manual test
    <slug>.postman_collection.json         if an API route's behaviour changed
    <slug>.sql                             if a migration was added
  reviews/
    <YYYY-MM-DD-HHmm>-<trigger>.md          each code-reviewer pass (written by that agent)
  context/
    <copied files>                         context the session used (see below)
    context-manifest.md                    provenance + referenced-not-copied list
```

- `slug` — short kebab-case summary of the change, e.g.
  `downpayment-per-transaction-policy`.
- **`NN` is one monotonic counter.** It continues from the highest `NN-*`
  under `Projects/golden-fur/sessions/` **and** the frozen legacy
  `sessions/_legacy/{custom,issues}/` — current high-water mark is `63`
  (`_legacy/custom/63-payment-transactions-rework`), so the next session is
  `64`. **List those directories and take max + 1** — never guess (see
  `_legacy/custom/25-policy-fees-and-credit-balances`'s "numbering had
  drifted" note). Issue-linked sessions use the same running `NN`; record
  `closes: [#NN]` in `plan.md`'s frontmatter, not in the folder name.
- `sessions/_legacy/{custom,issues}/` and `sessions/_legacy/reviews-feat/`
  are the pre-2026-09 `testing/` tree, frozen — never add to them.

## Write once, then update in place

The first implementation finish of a session **creates**
`sessions/NN-<slug>/` (at least `plan.md` + `testing/testing.md`). Every
**later** request in the **same session** **updates those same files** —
never a second `NN` for the same session, never a regenerated-from-scratch
doc. A follow-up that is genuinely a distinct, separately-requested piece of
work gets its own `NN`, cross-referenced in prose.

If the session began in **plan-only mode** (see the `plan` skill),
`sessions/NN-<slug>/plan.md` already exists — fill in `testing/` and
`context/` and expand the plan's "How you'll know it worked" pointer; don't
rewrite the plan body.

## `plan.md` — written for a near-beginner

Audience: a first- or second-year CS student who has **not** worked on this
codebase. Define every term the first time it appears. No unexplained jargon,
no "as you know". Short paragraphs. Analogies where they help.

```markdown
---
title: <plain-language title>
date: <YYYY-MM-DD>
tags: [session-plan, golden-fur]
project: golden-fur
session: NN-<slug>
branch: <branch-name or "staged on dev">
closes: [<#issue>, ...] # omit if none
---

# NN — <plain-language title>

## What you asked for

<one plain sentence>, then:

> <the original request, quoted as close to verbatim as available>

## What this part of the app does today

<Name the actual screens and roles. "The receptionist opens the Bookings
Queue page (the list of today's appointments) …". Explain what each named
thing is.>

## What's wrong / what's missing

<In concrete user terms — what a real person sees or can't do.>

## What we're going to change

1. **<plain-words change>** — _Which files:_ `path/to/file` — _Why:_ <reason a
   beginner can follow>
2. …

## Words you might not know

- **migration** — <from scratch>
- **RLS (row-level security)** — …
- **enum** — …
- <only the terms this plan actually uses>

## How you'll know it worked

See `testing/testing.md` for the click-by-click checks.
```

## `testing/testing.md` — the verification record

```markdown
# <Short title, plain language — what changed or what was fixed>

Branch: `<branch-name>` (or "not yet created — staged directly on `dev`")

## The request, verbatim

> <the original ask; add a "Scope note" if unrelated asks were split out,
> mirroring `sessions/_legacy/custom/41-fix-service-downpayment-toggle`>

## Root cause / Context

<Bug fix: what was wrong and why. Feature/architecture change: what existed
before, why it's changing, any history worth recording.>

## What changed

### Database (only if migrations were added)

<New migration file(s), one line each.>

### Server

<File-by-file, the reasoning a reviewer would want — not a full diff.>

### Client

<Same, client-side.>

## Manual test — step by step

<Assume the reader does not know how to navigate this app. Every step names
the exact control, the screen they land on, and what a failure looks like:>

1. Open your web browser and go to `http://localhost:5173`.
2. Click **Staff Login** (top-right corner). Type `<user>` / `<pass>`, click
   **Sign in**. You should land on a page headed **Dashboard**. If you see a
   red error banner instead, stop — the dev server or seed data is not ready.
3. …

<Group scenarios A, B, C… Reference the Postman collection for API-level
checks rather than restating every request in prose.>

## Test suites

<Exact pass/fail counts from actually running them — server and client
separately, e.g. "`server`: `npm run test` — 920/920 passing (87 files);
`npx tsc --noEmit` clean." Never state a count you did not personally run.>

## Open items (only if any)

<Anything deliberately deferred or flagged.>
```

Trim sections that don't apply rather than leaving them empty.

## Context files — copy, with a secrets carve-out

Into `context/`, **copy** every context file the session
actually used to do the work — pasted briefs, roadmap PDFs, meeting
transcripts, spec docs, screenshots. Copying (not linking) keeps the session
record self-contained if the source later moves.

**Never copy a secret or credential file** — a `.env*` file, an API key or
token, credentials of any kind. List those in `context-manifest.md` by path
only.

`context/context-manifest.md`:

```markdown
# Context — NN-<slug>

## Copied into ./context/

- `Ms-Mayuga-brief-2026-08.pdf` — advisor feedback that prompted the change.
  Origin: `Projects/golden-fur/shared/context/…`
- …

## Referenced only (not copied)

- `golden-fur/server/.env` — the staff test-login values for step 2 come
  from here; a secrets file, never copied.
```

Project-wide reference material that isn't session-specific stays canonical in
`Projects/golden-fur/shared/context/` and is only referenced.

## `.postman_collection.json` conventions

Follow `sessions/_legacy/custom/41-fix-service-downpayment-toggle`'s
collection as the template — Postman v2.1.0 schema, collection-level
`variable[]` (`base_url` defaults to `http://localhost:3000`, everything else
blank), numbered requests run top-to-bottom, a login request that captures the
token, `test` scripts asserting the specific field(s) this change is about
(not a generic "200 OK"), and both the "before" failing payload and the
"after" succeeding payload where relevant.

## `.sql` conventions

A **reference copy** of the actual migration file(s) already committed under
`golden-fur/supabase/migrations/`, prefixed with a header comment naming the
source-of-truth path(s) — not a separate seed/fixture script. See
`sessions/_legacy/custom/34-downpayment-and-transaction-history.sql`'s header.

## Cross-linking

No wikilinks required into/out of `sessions/` — it's working/record material,
not `Library/`. A one-line pointer to a relevant
`Library/golden-fur/features/<feature>/` note is fine but optional.

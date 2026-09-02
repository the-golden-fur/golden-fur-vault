---
title: Session records + deterministic hook routing
date: 2026-09-02
tags: [session-plan, golden-fur, tooling]
project: golden-fur
session: 64-session-records-and-hook-routing
branch: chore/session-docs-and-hook-routing (golden-fur) / chore/vault-sessions-restructure (vault)
---

# 64 — Session records + deterministic hook routing

## What you asked for

Give every AI session a durable home in the vault, reorganise the vault
around three clean roles, and make the "when do the PR-time checks run"
decision deterministic instead of relying on the model to remember.

> "Add something like requests/ or sessions/ somewhere in vault repo >
> Projects … optimize all skills, agents and hooks in both repos … only run
> X skills, agents or hooks that signify a session IS FINISHED when I request
> for a PR … the plan skill should only run when I specifically ask not to
> touch code and just plan"

Full running plan: `C:\Users\Matthew\.claude\plans\just-plan-no-code-abundant-flame.md`.

## What this changes (plain words)

A **hook** is a small script the AI tool (Claude Code) runs automatically at
a fixed moment — when you send a message, before a command runs, when the
turn ends. Hooks are _deterministic_: same input, same result. A **skill**
or **agent** is a set of instructions the model _chooses_ to follow — useful
but _probabilistic_. The idea here: let a hook decide _when_, let the
skill/agent do the _work_.

1. **`sessions/` folder in the vault.** Every request thread that changes the
   app gets `Projects/golden-fur/sessions/NN-<slug>/` — a plan written for a
   near-beginner, a click-by-click test script, and copies of the context
   files it used. `NN` is one running counter (this is 64; the previous high
   was the legacy `_legacy/custom/63`).
   _Files:_ the vault's `session-documentation` skill + `session-documenter`
   agent (renamed from `testing-*`).

2. **`shared/` + `Reference/`.** `Projects/golden-fur/` is now just `shared/`
   (project-wide context, decisions, design, research) and `sessions/`. A new
   top-level `Reference/` holds machine-readable workflow files; `Library/`
   and `Reference/` are both regrouped to match the app's own
   `features/<feature>/` folders. `Archive/` and `Resources/` (both empty)
   were removed.

3. **Three new hooks** (both repos, `.claude/settings.json`):
   - `session-router` — reads your message; "just plan / no code" routes to
     the `plan` skill (edit nothing), "open a PR / ship it" routes to the
     finish pipeline.
   - `pr-guard` — refuses `gh pr create` until the verify + review evidence
     exists.
   - `gitkeep-sweep` — adds/removes `.gitkeep` placeholder files so empty
     folders survive a fresh clone.

4. **Finish pipeline.** `pr-to-dev` / `pr-dev-to-main` / vault `pr` now run a
   fixed order: branch → verify-all → auto-fix if red → code review →
   commit → push → PR, then the vault. `pre-commit-checks` is demoted to
   on-request only; `ci-fixer-agent` owns lint/format at PR time.

## Words you might not know

- **hook** — a script a tool runs automatically at a set moment.
- **`UserPromptSubmit` / `PreToolUse` / `Stop`** — the moments Claude Code
  can run a hook: after you hit enter, before a tool runs, when the turn ends.
- **`.gitkeep`** — an empty file put in an otherwise-empty folder so Git
  (which ignores empty folders) will keep the folder.
- **CI parity check** — running locally the same checks the server runs on a
  PR (tests, lint, formatting, build), so nothing fails after you push.

## How you'll know it worked

See `testing/testing.md`.

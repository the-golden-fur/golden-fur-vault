---
title: Trimming the AI tooling so opening a PR stops eating the session limit
date: 2026-09-06
tags: [session-plan, golden-fur, meta, tooling]
project: golden-fur
session: 73-prune-automation-surface
branch: chore/prune-automation-surface
---

# 73 — Trimming the AI tooling so opening a PR stops eating the session limit

## What you asked for

Cut down the skills, agents, and hooks across both repos, grouped by what's
essential vs. unnecessary vs. redundant — because sessions were burning
through the usage limit, worst of all when opening a pull request.

> list down all the skills, agents and hooks in both repos / group them by
> essential, unnecessary and redundant / I noticed that we've been consuming
> too much session limits, especially when I request to open PRs
>
> …proceed with the agents changes plan as well … use the new optimized
> skills, agents and hooks you made for this request so that we use much
> less session limits

## Words you might not know

- **skill** — a checked-in Markdown file of instructions the AI loads when a
  task matches it (e.g. "how to open a PR here"). Lives in `.agent/skills/`
  with thin per-tool copies in `.claude/`, `.gemini/`, `.codex/`.
- **agent / subagent** — a separate AI worker the main session spawns for a
  focused job (run the tests, review the diff). Each one starts "cold": it
  re-reads both repos' `AGENTS.md` and its own instructions before it can
  do anything. That re-reading is the cost.
- **hook** — a shell script Claude Code runs automatically at a fixed moment
  (every prompt, every tool call, every turn end). Configured in
  `.claude/settings.json`.
- **the finish pipeline** — the fixed sequence that runs when you say "open
  a PR": branch → verify CI → review → commit → push → PR → then the same
  for the vault.

## What was wrong

Saying "open a PR" spawned **6–8 cold-start subagents** and ran the full
test suite (both repos) **2–3 times**:

- `ci-verifier` ran the suite once.
- `session-documenter` ran it **again** — its instructions demanded
  pass/fail counts it had personally run.
- `ci-fixer-agent` re-ran `ci-verifier` if anything was red.
- `code-reviewer` booted cold and re-explored the repo.
- `workflow-doc-sync` booted to decide whether docs drifted, and often
  spawned `workflow-documenter` on top of that.
- Then the whole vault side repeated `ci-verifier`.

On top of that, two `Stop` hooks ran shell work (a `git diff`, a
whole-tree `find`) on **every turn end**, and one of them
(`maintenance-reminders`) printed text that pushed the model to spawn even
more agents mid-task.

Separately, the repo carried tooling for four business modules that aren't
being built (Reports, Notifications, Discount compliance, the ISO-25010 QA
questionnaire) — 8 files × 4 tool-adapter copies each = dead weight in every
`AGENTS.md` load.

## What we changed

1. **`code-reviewer` subagent → the built-in `code-review` skill, run
   in-session.** Same gate (`pr-guard` still needs a review summary file in
   the session's `reviews/` folder), but no cold subagent boot. — _Files:_
   `golden-fur/.agent/skills/pr-to-dev.md`, `pr-dev-to-main.md`,
   `.claude/hooks/session-router.sh`; `golden-fur-vault/.agent/skills/pr.md`,
   `.claude/hooks/session-router.sh`; both `AGENTS.md`. Agent + its 4
   adapters deleted.

2. **`session-documenter` out of the PR pipeline.** It still runs at
   implementation-finish; the PR flow only _checks_ the session folder
   exists (a cheap file check, no spawn). And it now takes test counts from
   `ci-verifier`'s run instead of re-running the suites. — _Files:_
   `golden-fur-vault/.agent/skills/session-documentation.md`, the two
   `pr` skills, both `session-router.sh`.

3. **`workflow-doc-sync` is explicit-request only** — removed from the PR
   pipeline. Run it by hand when you want the drift check. — _Files:_
   `golden-fur/.agent/skills/workflow-doc-sync.md`, the two `pr` skills,
   both `session-router.sh`, `AGENTS.md`.

4. **Deleted the three `Stop` hooks** — `maintenance-reminders.sh` and
   `gitkeep-cleanup.sh` (golden-fur), `gitkeep-sweep.sh` (vault) — and the
   `Stop` block in both `.claude/settings.json`. Their intent lives in the
   skill descriptions now. `gitkeep-empty-dir` (the on-request skill) stays.

5. **Deleted dormant-module tooling** — agents `report-generator-agent`,
   `notification-agent`, `discount-compliance-agent`, `qa-iso25010-agent`,
   `domain-doc-sync-agent`, and the skills `daily-sales-report-format`,
   `email-notification-templates`, `discount-senior-pwd-compliance`,
   `iso25010-evaluation-instrument` — all 4 adapter copies each. Recreate
   from git history when a module goes active.

6. **Vault gardening agents deleted** — `backlink-curator`,
   `weekly-reviewer` (+ `weekly-review-format` skill),
   `research-capture-agent`, `skill-agent-auditor`. The work they did is
   done inline via `note-filing` / `vault-librarian` / `cross-linking` /
   `skill-security-audit`.

7. **Removed the superseded `Architectural-Change-History.docx`** from
   `shared/context/architecture/` — `Modules-Features.docx` is the single
   architecture source of truth now.

### The pipeline now

```text
branch (if on dev/main) → ci-verifier ONCE → ci-fixer only if red
→ code-review skill IN-SESSION (write reviews/ summary) → commit → push → PR
→ vault: reuse the same ci-verifier pass, commit, push, PR
```

Worst case: `ci-verifier` (+ `ci-fixer` on red only). Down from 6–8
subagents and 2–3 suite runs.

## How you'll know it worked

See `testing/testing.md`. In short: the `session-router` hook now emits the
6-step pipeline with no `code-reviewer` / `session-documenter` /
`workflow-doc-sync` spawn wording, `pr-guard` still blocks a PR with no
evidence, and both repos still pass lint + format + typecheck.

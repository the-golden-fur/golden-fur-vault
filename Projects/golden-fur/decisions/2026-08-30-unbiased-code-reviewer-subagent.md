---
title: Unbiased code-reviewer subagent
date: 2026-08-30
tags: [decision, tooling, code-review, golden-fur]
project: golden-fur
---

Source request: Matthew — "Add a subagent code reviewer in golden-fur repo
for unbiased code reviews. Only give it read-only perms. Should auto-run
before creating commits, publishing a branch, or opening a PR. Decide where
it places its outputs — somewhere in `Projects/golden-fur/testing`."

> **Status: implemented** (2026-08-30). Agent + adapters added to the
> golden-fur repo, git-workflow skills updated, backstop hook added,
> documentation filed here.

## Problem

Every code change in golden-fur was, in practice, reviewed only by the same
agent (or person) that wrote it, in the same session. That reviewer knows
why the code looks the way it does, which is exactly what makes it bad at
spotting where the code is wrong — it reads intent into the diff instead of
reading the diff. `testing-documenter` runs _after_ a change and answers
"how does a human re-verify this", not "should this merge at all". Nothing
was answering the second question with fresh eyes.

## Decision

### 1. A dedicated `code-reviewer` subagent, in the golden-fur repo

Canonical file `golden-fur/.agent/agents/code-reviewer.md`, with the
repo's usual thin adapters (`.claude/agents/`, `.gemini/commands/`,
`.codex/prompts/`). It lives in the **code repo**, not this vault, because
it is a git-workflow tool like `commit` / `pr-to-dev` — even though, like
`testing-documenter`, its _output_ is written here.

The "unbiased" contract is written into the agent: derive what the change
does from the diff, not from the caller's description; treat any supplied
rationale as a claim to verify against the code; report findings even when
told they are intentional unless the code, a comment, or a test justifies
it; don't soften findings because rework is inconvenient.

### 2. Read-only

Tools: `Read, Grep, Glob, Bash, Write`.

- **No `Edit`** — it can never modify an existing file.
- `Bash` is restricted (by written instruction, the same mechanism the
  other read-mostly agents in this repo use) to read-only git inspection —
  `git diff` / `log` / `show` / `status` / `merge-base` / `branch`. No
  `add` / `commit` / `push` / `checkout` / `reset` / `stash`, no test /
  build / lint / format / install runs.
- `Write` produces exactly one file per run: its report, in this vault.
  Never into the golden-fur repo.

Per-subagent permission scoping isn't available in `settings.json` (deny
rules are global and would break the main session), so the guarantee rests
on the `tools` frontmatter (no `Edit`) plus the written scope — consistent
with how `auth-access-agent` and the other read-mostly agents are handled.

### 3. Output location: `Projects/golden-fur/testing/reviews/<branch>/`

`reviews/<branch>/<YYYY-MM-DD-HHmm>-<trigger>.md`, `trigger` ∈
{`pre-commit`, `pre-publish`, `pre-pr`}. Chosen over alternatives:

- **`golden-fur/testing/…` (in the code repo)** — rejected; the whole
  in-repo `testing/docs/` tree was removed in
  [[../testing/custom/53-remove-testing-docs/|custom #53]] precisely to
  keep working docs out of the code repo.
- **`golden-fur/temp/`** — rejected; gitignored scratch, not retained.
- **A new top-level vault folder** — rejected; review reports are
  per-change golden-fur working records, exactly what `testing/` already
  holds. Sitting beside `issues/` and `custom/` keeps them discoverable
  next to the matching verification doc.

One file per run (not one per branch) so a branch keeps the full history of
what each pass flagged.

### 4. Auto-run wiring

- **Primary — skill steps.** `commit`, `pr-to-dev`, and `pr-dev-to-main`
  each gained a mandatory step that spawns `code-reviewer` before the
  commit/PR proceeds, with an explicit "a pass already done this session
  still counts if nothing changed since" clause so it isn't re-run
  needlessly. `branch-naming` got a note that the initial empty-branch push
  needs no review.
- **Backstop — `PreToolUse` hook** in
  `golden-fur/.claude/settings.local.json` (same file as the existing
  `Stop` hook that nudges for a testing doc; user-local, gitignored). On a
  `git commit` / `git push` / `gh pr create` it exits 2 (blocking) when
  `client/src` / `server/src` / `supabase/` has changed and either no
  review exists for the branch, or the newest review is older than the
  newest changed source file. Same "skip only for a formatting/
  non-functional diff, and say so" escape hatch as the testing-doc hook.

## Non-goals

- Not running the test suites — that stays `testing-documenter`'s job; the
  reviewer only reads test files and notes coverage gaps.
- Not replacing human PR review or `/code-review` / `ultrareview` — this is
  a cheap always-on first pass, not the last word.
- Not scoping the agent's permissions via `settings.json` — see §2.
- Not a committed (team-wide) hook — the backstop matches the existing
  user-local hook setup; the shared enforcement is the skill steps and
  `AGENTS.md`.

## Files touched

**golden-fur:** `.agent/agents/code-reviewer.md`,
`.claude/agents/code-reviewer.md`, `.gemini/commands/code-reviewer.toml`,
`.codex/prompts/code-reviewer.md`, `.agent/skills/commit.md`,
`.agent/skills/pr-to-dev.md`, `.agent/skills/pr-dev-to-main.md`,
`.agent/skills/branch-naming.md`, `.claude/settings.local.json`,
`AGENTS.md`.

**golden-fur-vault:** this note,
`Projects/golden-fur/testing/reviews/README.md`,
`Projects/golden-fur/docs/changelog/2026-08-30-code-reviewer-agent.md`,
`AGENTS.md`.

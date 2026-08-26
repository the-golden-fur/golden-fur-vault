# Pre-commit checks

**Purpose:** run every `(check)`/`(fix)`-labeled VS Code task in
`.vscode/tasks.json` — currently just Prettier formatting — before code
gets committed, so formatting issues are caught and auto-corrected
locally instead of failing this repo's format-check CI job or needing
manual cleanup after the fact.

**Use whenever:**

- **Always, as the first step of the `commit` skill** — run this before
  staging/writing the commit message, every time a local commit is made in
  this repo.
- On request, standalone — "run the checks", "format this" — at any other
  point while working.

## Process

1. **Run the fix task first**: `npm run format` (repo root) — Prettier
   write; matches "🎨 Format: Fix (write)".
2. **Run the check task** to confirm a clean state: `npm run format:check`
   (repo root) — matches "🎨 Format: Check".
3. **If the check still fails after the fix task ran**, that's not a
   formatting issue Prettier can resolve on its own (rare, but possible
   with malformed frontmatter or similar) — surface the failing file(s)
   to the user before committing rather than committing broken content.
4. Only proceed to stage/commit once the check passes clean, or the user
   explicitly says to commit anyway with known issues outstanding.

## Scope — deliberately narrow

This repo has no lint task — Prettier only covers markdown/YAML/JSON, and
there's no code to lint here. If a lint or other quality task is ever
added to `.vscode/tasks.json`, extend this skill to run it too, following
the same fix-then-check pattern as `golden-fur`'s version of this skill.

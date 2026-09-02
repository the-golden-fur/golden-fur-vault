# Pre-commit checks

**Purpose:** run every `(check)`/`(fix)`-labeled VS Code task in
`.vscode/tasks.json` — currently just Prettier formatting — to catch and
auto-correct formatting issues locally instead of failing this repo's
format-check CI job.

**Use whenever:**

- **On request, standalone** — "run the checks", "format this" — at any
  point while working, or when you just want Prettier tidy.

**Not** a pipeline step any more. The `pr` skill's finish pipeline runs
`ci-verifier` first (reports format red) then `ci-fixer-agent` (fixes it) —
this skill is no longer wired between them. A plain `commit` has no format
gate.

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

## Windows CRLF false-diff

The repo's `.gitattributes` (`* text=auto eol=lf`) checks every text file
out as LF on every platform, so `npm run format` and `git status` no
longer disagree with CI over line endings. If a working tree that predates
`.gitattributes` still shows a big unrelated diff, `git add -A` then
`git restore --staged .` to normalize the comparison — only files still
modified after that are real.

## Scope — deliberately narrow

This repo has no lint task — Prettier only covers markdown/YAML/JSON, and
there's no code to lint here. If a lint or other quality task is ever
added to `.vscode/tasks.json`, extend this skill to run it too, following
the same fix-then-check pattern as `golden-fur`'s version of this skill.

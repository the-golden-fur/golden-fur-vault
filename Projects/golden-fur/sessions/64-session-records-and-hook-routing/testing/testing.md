# Session records + deterministic hook routing

Branch: `chore/session-docs-and-hook-routing` (golden-fur),
`chore/vault-sessions-restructure` (golden-fur-vault)

## The request, verbatim

See `../plan.md` ("What you asked
for"). Full running plan:
`C:\Users\Matthew\.claude\plans\just-plan-no-code-abundant-flame.md`.

## Root cause / Context

Sessions left their plan and context only in chat; the "run `ci-verifier` /
`code-reviewer` / `workflow-doc-sync` only at PR time" rule was enforced only
by prose in skill descriptions. This makes the session record a first-class
vault artifact and moves the _timing decision_ into deterministic hooks.

## What changed

No `golden-fur` application code (`client/`, `server/`, `supabase/`) was
touched — this is tooling + docs only.

### golden-fur

- `.claude/settings.json` — wired `UserPromptSubmit` (`session-router`),
  `PreToolUse`/`Bash` (`pr-guard`), and a second `Stop` hook
  (`gitkeep-sweep`) alongside `maintenance-reminders`.
- `.claude/hooks/{session-router,pr-guard,gitkeep-sweep}.sh` — new.
  `maintenance-reminders.sh` — added a session-doc nudge.
- `.agent/skills/{pr-to-dev,pr-dev-to-main}.md` — rewrote to the locked
  finish-pipeline order; `pre-commit-checks.md` demoted; `branch-naming.md`
  note. `.agent/agents/{ci-verifier,ci-fixer-agent,code-reviewer}.md` —
  marker write, auto-chain, output path → the session's `reviews/`.
- `.agent/skills/workflow-doc-sync.md` — scan path → `Reference/.../features/`.
- `AGENTS.md` — "Where things live" + "Auto-run wiring" rewrite.

### golden-fur-vault

- Folder moves: `Projects/golden-fur/` → `{shared/, sessions/}`; new
  `Reference/`; `Library/` + `Reference/` regrouped under
  `features/<feature>/`; `Archive/` + `Resources/` removed. (420 renames.)
- `testing-documentation`→`session-documentation`,
  `testing-documenter`→`session-documenter`; new `plan` skill; all
  Claude/Gemini/Codex adapters. `session-router` / `pr-guard` /
  `gitkeep-sweep` hooks + `.claude/settings.json` (new).
- `AGENTS.md`, `docs/{folder-guide,security,conventions}.md`, `note-filing`,
  `workflow-documentation`, `research-capture-agent`, decision records —
  repointed; `Credentials.docx` name references removed.

## Manual test — step by step

These check the two hook routes and the folder scheme. Run them in a
`golden-fur` Claude Code session **after this PR merges** (hooks load at
session start).

### A. Plan-only routing

1. Start a Claude Code session in the `golden-fur` folder.
2. Type: `just plan a change to the booking cancel button, no code yet` and
   send.
3. Expected: the reply says it's in **plan-only mode**, writes a file at
   `golden-fur-vault/Projects/golden-fur/sessions/65-<something>/plan.md`
   written in plain language, and does **not** edit anything under `client/`
   or `server/`. If it starts editing code, the `session-router` hook did
   not fire — check `.claude/settings.json` is present and `bash` is on PATH.

### B. Finish-pipeline routing + PR guard

4. In a session that has real staged changes on a feature branch, type:
   `open a PR for this`.
5. Expected: the reply lists the pipeline steps in order (branch → verify →
   ci-fixer → review → commit → push → PR).
6. If it tries `gh pr create` before `ci-verifier` has run, expected: the
   command is **blocked** with a message naming the missing step. After
   `ci-verifier` runs green (writes `.git/ci-verifier-pass`) and a
   `code-reviewer` report exists under
   that branch's `golden-fur-vault/Projects/golden-fur/sessions/<NN-slug>/reviews/`, the
   `gh pr create` is allowed.

### C. `.gitkeep` sweep

7. `mkdir golden-fur-vault/Inbox/scratch-test` (leave it empty). End the
   Claude turn.
8. Expected: `golden-fur-vault/Inbox/scratch-test/.gitkeep` now exists and is
   staged. Add any file to that folder, end another turn → the `.gitkeep` is
   removed. `rmdir` the folder to clean up.

### D. Folder scheme

9. `golden-fur-vault/Projects/golden-fur/` contains exactly `shared/` and
   `sessions/`. `Archive/` and `Resources/` are gone. `Reference/golden-fur/features/`
   and `Library/golden-fur/features/` have matching `<feature>/` subdirs.

## Test suites

Not run — no application code changed. Both repos' `npm run format:check`
pass clean (the only CI job touched by the `.md`/`.json` edits). Every new
hook script passes `bash -n`; `session-router`, `pr-guard`, and
`gitkeep-sweep` were smoke-tested by hand (plan/PR/neutral prompts; a
non-`gh-pr-create` command; an empty dir and a populated one).

## Open items

- `session-router` matches on prompt phrasing; deliberately tight regex, so
  an unusual way of asking for a PR ("wrap this up") won't trigger — say
  "open a PR" / "/pr".
- `pr-guard` resolves the review folder by branch-name substring; a branch
  whose leaf name is a substring of another branch's could match loosely.
- `golden-fur-vault/Projects/golden-fur/shared/context/` now has two files
  named `Architectural-Change-History.docx` (one at the root moved from
  `Inbox/`, one under `architecture/`) with different content — reconcile if
  one supersedes the other.

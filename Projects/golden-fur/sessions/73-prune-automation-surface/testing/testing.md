# Trimming the AI tooling to cut PR session cost

Branch: `chore/prune-automation-surface` (same name in both repos)

## The request, verbatim

> list down all the skills, agents and hooks in both repos / group them by
> essential, unnecessary and redundant / I noticed that we've been consuming
> too much session limits, especially when I request to open PRs

Scope note: the Supabase dev-database push and the `supabase/seeds/`
restructure discussed in the same thread are separate pieces of work, not
part of this branch.

## Context

The finish pipeline spawned 6–8 cold-start subagents per PR and ran both
repos' test suites 2–3 times; two `Stop` hooks did shell work on every turn
end. Full rationale and the file-by-file change list are in `plan.md`.

## What changed

This is a **tooling-only** change. No file under `client/`, `server/`, or
`supabase/` was touched — so no application behaviour changed, and the
session-documentation "click-by-click manual test" section does not apply.

### golden-fur (`chore/prune-automation-surface`, commit `961ffd4`)

- 55 files, −1215 / +156 lines.
- Deleted: `code-reviewer`, `domain-doc-sync-agent`,
  `report-generator-agent`, `notification-agent`,
  `discount-compliance-agent`, `qa-iso25010-agent` + the 4 dormant skills —
  all `.agent/` + `.claude/` + `.gemini/` + `.codex/` copies.
- Deleted hooks: `.claude/hooks/maintenance-reminders.sh`,
  `.claude/hooks/gitkeep-cleanup.sh`; removed the `Stop` block from
  `.claude/settings.json`.
- Rewrote: `.agent/skills/pr-to-dev.md`, `pr-dev-to-main.md`,
  `workflow-doc-sync.md`, `.claude/hooks/session-router.sh`,
  `.claude/hooks/pr-guard.sh` (wording only — logic unchanged), `AGENTS.md`.
- Scrubbed deleted-name references from `branch-naming.md`, `commit.md`,
  `capacity-based-scheduling.md`, `credit-balance-ledger.md`,
  `booking-capacity-agent.md`, `gitkeep-empty-dir.md`.

### golden-fur-vault (`chore/prune-automation-surface`, commits `22b2ab1`, `f98f1bc`, + this session folder)

- Deleted: `backlink-curator`, `weekly-reviewer`, `research-capture-agent`,
  `skill-agent-auditor` agents + `weekly-review-format` skill (all adapter
  copies); `.claude/hooks/gitkeep-sweep.sh` + the `Stop` block.
- Rewrote: `.agent/skills/pr.md`, `session-documentation.md`,
  `.claude/hooks/session-router.sh`, `pr-guard.sh`, `AGENTS.md`.
- Scrubbed references from `cross-linking.md`, `frontmatter-schema.md`,
  `note-filing.md`, `skill-security-audit.md`.
- Removed `shared/context/architecture/Architectural-Change-History.docx`
  (superseded by `Modules-Features.docx`).

## Verification performed (in-session, 2026-09-06)

| check                                            | scope                          | result                                                                                                          |
| ------------------------------------------------ | ------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `prettier --check` (`**/*.md` etc.)              | golden-fur                     | ✅ all files                                                                                                    |
| `prettier --check`                               | golden-fur-vault               | ✅ all files                                                                                                    |
| `eslint .`                                       | golden-fur `client/`           | ✅ 0 errors                                                                                                     |
| `eslint .`                                       | golden-fur `server/`           | ✅ 0 errors (31 pre-existing warnings)                                                                          |
| `tsc --noEmit`                                   | golden-fur `server/`           | ✅ clean                                                                                                        |
| `session-router.sh` "open a PR"                  | both repos                     | ✅ emits the new 6-step pipeline, no `code-reviewer` / `session-documenter` / `workflow-doc-sync` spawn wording |
| `session-router.sh` ordinary prompt              | golden-fur                     | ✅ no output (doesn't over-trigger)                                                                             |
| `pr-guard.sh` on `gh pr create` with no evidence | both repos                     | ✅ still `permissionDecision: deny`                                                                             |
| `python -m json.tool` on `.claude/settings.json` | both repos                     | ✅ valid, `Stop` key gone, `UserPromptSubmit` + `PreToolUse` intact                                             |
| dangling-reference grep for every deleted name   | both repos, active config only | ✅ only intentional "retired 2026-09-06" notes + the ADR + frozen session records remain                        |

## Test suites

Not run in-session. The diff touches zero files under `client/` / `server/`
/ `supabase/`, so the Vitest suites and the client build cannot be affected
by it. **GitHub Actions CI runs both full test suites, both lints, the
repo-wide Prettier check, and the client build on this PR** — that is the
authoritative full-suite pass for this change.

## Open items

None. Follow-on work tracked separately: `supabase/seeds/` restructure into
M-numbered dirs; trimming the per-module `seed:*` npm scripts / VS Code
tasks to `seed:all` only.

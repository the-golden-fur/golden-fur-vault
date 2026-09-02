# Pull request

**Use whenever** opening a PR in this vault. This repo has a single `main`
branch — target `main` for all work.

## Process — the locked finish pipeline (vault side)

Mirrors `golden-fur`'s finish pipeline. This whole sequence is the "session
is finished" flow; none of it runs on a plain `commit`. The
`session-router` hook injects this list on an "open a PR" prompt, and the
`pr-guard` hook blocks `gh pr create` until step 2 is green for `HEAD`.

1. **Branch.** If `HEAD` is `main`, run `.agent/skills/branch-naming.md` to
   create and push the branch first.
2. **Verify CI parity across both repos** — spawn the `ci-verifier` subagent
   (`.agent/agents/ci-verifier.md`, canonical in `../golden-fur`); the
   `✅ CI: Verify All` task must be green here and in `golden-fur`. It writes
   `.git/ci-verifier-pass` (the verified `HEAD` sha). A green pass from
   earlier this session with nothing changed counts.
3. **If red — spawn `ci-fixer-agent`** (canonical in `../golden-fur`) to fix
   format/prose it broke, then re-run `ci-verifier` until green. No separate
   `pre-commit-checks` step.
4. **Session record.** Confirm this session's `Projects/golden-fur/sessions/`
   material (`plans/`, `testing/`, `reviews/`) and any
   `Reference/golden-fur/` workflow refresh are written and current —
   normally already done at implementation-finish; `session-documenter` /
   `workflow-documenter` as a backstop.
5. **Commit** — run `.agent/skills/commit.md`.
6. **Push** the branch.
7. Fill in the PR body (sections below), determine title / label(s) /
   assignee, and open it in one call:
   `gh pr create --base main --head <branch> --title "..." --body "..."
--label <label>[,<label>...] --assignee @me`.
8. If anyone else has write access, add `--reviewer <user>`.

## Merge strategy: merge commit

Use a merge commit (not squash — not allowed by this repo's branch
protection) to merge into `main`. Don't run the merge as part of opening the
PR — when asked to merge, follow [merge-pr.md](merge-pr.md), which confirms
readiness, confirms with the user, and crafts the merge commit title/body.

## Rules

### PR Title

Mirrors the commit subject format: `<type>(<scope>): <subject>`, max 72
characters, imperative mood, no trailing period.

### Labels

Apply one via `--label` at creation time (create the label first with
`gh label create` if it doesn't exist yet in the repo): `filing` (new notes
filed), `fix` (correction to an existing note), `chore`
(reorganizing/housekeeping), `refactor` (restructuring, no content change).

### Assignee

Always set an assignee at creation time — default to `--assignee @me`
(the person opening the PR is responsible for seeing it through).

### Body sections

- **Summary** — one sentence covering both what and why.
- **What Changed** — brief bullet list of key files/folders touched and
  why; not exhaustive.
- **Why** — one sentence: what prompted this filing/change now.
- **Testing** — for anything under `Projects/golden-fur/sessions/`, note
  that it was copied/verified against the source change in
  `../golden-fur`; otherwise N/A for plain note filing.

## General rules

- PRs must be atomic — one concern per PR.
- Request at least one reviewer at creation time (step 5 above) if anyone
  else has write access; otherwise self-merge is fine (this is a private
  notes vault).
- Never merge without being explicitly asked to — see
  [merge-pr.md](merge-pr.md) for the merge process itself.

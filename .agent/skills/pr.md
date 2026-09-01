# Pull request

**Use whenever** opening a PR in this vault. This repo has a single `main`
branch — target `main` for all work.

## Process

1. **Run `.agent/skills/pre-commit-checks.md`** — Prettier format fix/check,
   so `ci-verifier` (read-only, won't fix) has nothing trivial to fail on.
   Commit any fixes it makes.
2. Make sure the compare branch is pushed and up to date with its remote.
3. **Verify CI parity across both repos** — spawn the `ci-verifier`
   subagent (`.agent/agents/ci-verifier.md`, canonical file in
   `../golden-fur`); the `✅ CI: Verify All` task must be green here and in
   `golden-fur` before the PR is opened. A green pass from earlier this
   session with nothing changed since counts.
4. Fill in the PR body using the sections below.
5. Determine the title, label(s), and assignee (see Rules below).
6. Open it directly with all of it set in one call — title, body, label(s),
   and assignee — not left for manual follow-up:
   `gh pr create --base main --head <branch> --title "..." --body "..."
--label <label>[,<label>...] --assignee @me`.
7. If anyone else has write access to the repo, also add
   `--reviewer <user>` per the reviewer rule below.

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
- **Testing** — for anything under `Projects/golden-fur/testing/`, note
  that it was copied/verified against the source change in
  `../golden-fur`; otherwise N/A for plain note filing.

## General rules

- PRs must be atomic — one concern per PR.
- Request at least one reviewer at creation time (step 5 above) if anyone
  else has write access; otherwise self-merge is fine (this is a private
  notes vault).
- Never merge without being explicitly asked to — see
  [merge-pr.md](merge-pr.md) for the merge process itself.

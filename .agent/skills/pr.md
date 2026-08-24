# Pull request

**Use whenever** opening a PR in this vault. This repo has a single `main`
branch — target `main` for all work.

## Process

1. Make sure the compare branch is pushed and up to date with its remote.
2. Fill in the PR body using the sections below.
3. Open it directly: `gh pr create --base main --head <branch> --title
"..." --body "..."`.
4. Recommend the appropriate label(s).

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

`filing` (new notes filed), `fix` (correction to an existing note),
`chore` (reorganizing/housekeeping), `refactor` (restructuring, no content
change).

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
- Request at least one reviewer before merging if anyone else has write
  access; otherwise self-merge is fine (this is a private notes vault).
- Never merge without being explicitly asked to — see
  [merge-pr.md](merge-pr.md) for the merge process itself.

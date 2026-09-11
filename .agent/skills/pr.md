# Pull request

**Use whenever** opening a PR in this vault. This repo has a single `main`
branch — target `main` for all work.

## Process — runs once, then done

This skill only gets the branch pushed and opens a **draft** PR with every
field filled in. It runs **no CI / format / verification check** — the user
runs those manually after the PR exists. Do not spawn any verifier/fixer
subagent, and do not loop.

1. **Branch.** If `HEAD` is `main`, run `.agent/skills/branch-naming.md` to
   create and push the branch first.
2. **Commit** any outstanding work — run `.agent/skills/commit.md`. Skip if
   the tree is already clean.
3. **Push** the branch.
4. Fill in the PR body (sections below), determine title / label(s) /
   assignee, and open it as a draft in one call:
   `gh pr create --draft --base main --head <branch> --title "..." --body-file <file> --label <label>[,<label>...] --assignee @me`.
   If a PR for this branch already exists, apply the same fields with
   `gh pr edit <n> ...`, then `gh pr ready <n> --undo` to set it back to
   draft, and confirm with `gh pr view <n> --json title,assignees,labels,isDraft`.
5. If anyone else has write access, add `--reviewer <user>`.

Then hand back the PR link. You're done.

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

# Merge PR

**Use whenever** asked to merge a PR in this vault — "merge PR #4", "merge
this", "merge it". Only run when explicitly asked to merge; opening a PR
(see [pr.md](pr.md)) does not by itself authorize merging it.

## Process

1. Check merge readiness: `gh pr view <PR> --json title,number,mergeable,
   mergeStateStatus,reviewDecision,statusCheckRollup,headRefName`. Surface
   anything that isn't clean — conflicts, pending required reviews, failing
   checks — before proceeding; don't merge through a red state without the
   user saying so explicitly.
2. Confirm with the user before merging: state the PR number/title and that
   this uses a merge commit, and wait for explicit go-ahead. This is a
   shared-state, hard-to-reverse action on `main` — a prior "open a PR" ask
   does not itself authorize the merge step.
3. Craft the merge commit:
   - **Title** — `<type>(<scope>): <subject> (#<PR number>)`, mirroring the
     PR title / [commit.md](commit.md) subject format.
   - **Description** — 1–3 sentence summary of what changed and why, drawn
     from the PR body's Summary/What Changed sections (or the branch's
     commit log if the PR body is thin). Omit if the title is already
     fully self-explanatory.
4. Merge directly: `gh pr merge <PR> --merge --subject "<title>" --body
   "<description>"`.
5. Confirm it landed: `gh pr view <PR> --json state,mergedAt` and report the
   resulting merge commit back to the user.

## Notes

- This repo's branch protection only allows `Merge` and `Rebase` — no
  squash — so merge commit is the required strategy; see
  [pr.md](pr.md#merge-strategy-merge-commit).
- Don't delete the source branch unless asked (`-d`/`--delete-branch` is
  opt-in, not default).

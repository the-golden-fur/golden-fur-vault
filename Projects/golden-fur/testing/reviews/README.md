---
title: golden-fur code review reports
date: 2026-08-30
tags: [code-review, golden-fur, index]
project: golden-fur
---

# Code review reports

Output of the `code-reviewer` subagent that lives in the **golden-fur code
repo** (`.agent/agents/code-reviewer.md`). It gives an unbiased, read-only
review of a branch's diff before that branch is committed, published, or
opened as a PR — it did not write the code and is given no rationale beyond
the diff itself.

This sits beside `testing/issues/` and `testing/custom/` because it is the
same kind of material — per-change working records for the golden-fur app —
and the code repo deliberately keeps none of it (see
`../custom/53-remove-testing-docs/`).

## Layout

```
reviews/<branch>/<YYYY-MM-DD-HHmm>-<trigger>.md
```

- `<branch>` — the branch name verbatim, keeping any `/` (so
  `feat/foo-bar/` is a nested folder).
- `<trigger>` — `pre-commit`, `pre-publish`, or `pre-pr`.
- One file per review run. A branch usually accumulates several as it moves
  from first commit to PR; keep them all — the history of what was flagged
  and when is the point.

## How it runs

- **Automatically**, as a mandatory step of the `commit`, `pr-to-dev`, and
  `pr-dev-to-main` skills in the golden-fur repo.
- **Backstop:** a `PreToolUse` hook in `golden-fur/.claude/settings.local.json`
  blocks a direct `git commit` / `git push` / `gh pr create` when
  `client/src`, `server/src`, or `supabase/` changed and there is no
  matching review here for the branch.
- **Manually:** spawn the `code-reviewer` agent, or `/code-reviewer` in
  Gemini / Codex.

## Relationship to `testing-documenter`

Different jobs, both land under `testing/`:

|             | `code-reviewer`                           | `testing-documenter`                   |
| ----------- | ----------------------------------------- | -------------------------------------- |
| When        | **before** commit / PR                    | **after** the change is implemented    |
| Question    | is this change correct and safe to merge? | how does a human re-verify it?         |
| Runs suites | no (reads test files only)                | yes (real pass/fail counts)            |
| Output      | `testing/reviews/<branch>/`               | `testing/issues/` or `testing/custom/` |

See the decision record:
[[2026-08-30-unbiased-code-reviewer-subagent]].

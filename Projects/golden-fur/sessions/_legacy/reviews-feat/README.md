---
title: golden-fur code review reports
date: 2026-09-02
tags: [code-review, golden-fur, index]
project: golden-fur
---

# Code review reports

Output of the `code-reviewer` subagent that lives in the **golden-fur code
repo** (`.agent/agents/code-reviewer.md`). It gives an unbiased, read-only
review of a branch's diff **before the PR is opened** — it did not write the
code and is given no rationale beyond the diff itself. The code repo
deliberately keeps none of this material (see
`../testing/custom/53-remove-testing-docs/`).

## Layout

```text
reviews/<branch>/<YYYY-MM-DD-HHmm>-<trigger>.md
```

- `<branch>` — the branch name verbatim, keeping any `/` (so `feat/foo-bar/`
  is a nested folder).
- `<trigger>` — normally `pre-pr`; `manual` for a hand-run review. Legacy
  reports may carry `pre-commit` / `pre-publish`.
- One file per review run — a branch accumulates several; keep them all.

## How it runs

- **Automatically**, as step 4 of the `pr-to-dev` / `pr-dev-to-main` finish
  pipeline (golden-fur) and the vault `pr` skill's pipeline. Not on a plain
  `commit` or branch push.
- **Enforced** by the checked-in `pr-guard` hook, which blocks `gh pr create`
  when no review report exists here for the branch.
- **Manually:** spawn the `code-reviewer` agent, or `/code-reviewer` in
  Gemini / Codex.

## Relationship to `session-documenter`

Different jobs:

|             | `code-reviewer`                           | `session-documenter`                           |
| ----------- | ----------------------------------------- | ---------------------------------------------- |
| When        | **before** the PR                         | **after** the change is implemented            |
| Question    | is this change correct and safe to merge? | what is it, and how does a human re-verify it? |
| Runs suites | no (reads test files only)                | yes (real pass/fail counts)                    |
| Output      | `sessions/reviews/<branch>/`              | `sessions/plans/` + `sessions/testing/`        |

See the decision record:
[[2026-08-30-unbiased-code-reviewer-subagent]].

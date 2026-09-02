---
title: Sessions — the golden-fur working changelog
date: 2026-09-02
tags: [golden-fur, sessions, meta]
project: golden-fur
---

# `Projects/golden-fur/sessions/`

One **self-contained folder per AI session** — a single Claude / Codex /
Gemini request thread that changed the `golden-fur` app. Together these are
the project's running changelog: what was asked, what changed, how to
re-verify it, and the context that informed it.

`Projects/golden-fur/` has exactly two subtrees — this one and `shared/`
(project-wide context, decisions, design, research that isn't tied to one
session).

## Layout

```text
sessions/
  NN-<slug>/
    plan.md                                the request explained for a near-beginner
    testing/
      testing.md                           verification record + click-by-click manual test
      <slug>.postman_collection.json        only if an API route's behaviour changed
      <slug>.sql                            reference copy of any migration added
    reviews/
      <YYYY-MM-DD-HHmm>-<trigger>.md         each code-reviewer pass
    context/
      <copied files>                        context the session used
      context-manifest.md                   provenance + referenced-not-copied list
  _legacy/
    custom/    01-… 63-…                    the pre-2026-09 testing/custom tree, frozen
    issues/    11-… 105-…                   the pre-2026-09 testing/issues tree, frozen
    reviews-feat/                            pre-2026-09 code-review reports
```

| Written by                                                | What                   |
| --------------------------------------------------------- | ---------------------- |
| `plan` skill (plan-only sessions) or `session-documenter` | `plan.md`              |
| `session-documenter`                                      | `testing/`, `context/` |
| `code-reviewer` agent (in `../golden-fur`)                | `reviews/`             |

## Numbering

**One monotonic `NN` counter.** It continues from the highest `NN-*` under
`sessions/` **and** the frozen `sessions/_legacy/{custom,issues}/`. The
current high-water mark is `63`
(`_legacy/custom/63-payment-transactions-rework`), so the next session is
`64`. **List the directories and take max + 1** — never guess. Issue-linked
sessions use the same running `NN`; record `closes: [#NN]` in `plan.md`'s
frontmatter, not in the folder name.

`code-reviewer` finds a session's folder by matching the current branch
against `sessions/*/plan.md`'s `branch:` frontmatter, then writes into that
folder's `reviews/`.

### Legacy

`sessions/_legacy/` is the old `Projects/golden-fur/testing/` tree, moved
verbatim as history — the `<slug>.md` + Postman + SQL trios and the
`reviews/feat/` reports from before the per-session-folder split. **Never
add to it.**

## Module code → feature

Workflow/module notes elsewhere in the vault are grouped by golden-fur
feature folder, with the capstone M-code kept as a filename prefix:

| M-code                  | feature      | M-code                           | feature         |
| ----------------------- | ------------ | -------------------------------- | --------------- |
| M01 staff / access      | `staff`      | M08 sales / billing              | `billing`       |
| M02 customers / pets    | `customers`  | M09 policy enforcement           | `booking`       |
| M03 appointment booking | `booking`    | M10 credit balance               | `credits`       |
| M04 grooming            | `grooming`   | M11 notification                 | `notifications` |
| M05 hotel / boarding    | `hotel`      | M12 discounts                    | `discounts`     |
| M06 daycare             | `daycare`    | M13 packages / services / promos | `maintenance`   |
| M07 health / veterinary | `veterinary` | M14 reports / analytics          | `reports`       |

---
title: Folder guide
date: 2026-08-24
tags: [docs, folders]
---

# Folder guide

Where things live, and who puts them there — you, or an AI agent.

| Folder                                               | Who writes here                                             | What goes in it                                                                                                 | Messy or clean?                                |
| ---------------------------------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `Inbox/`                                             | You, or an AI agent filing a raw capture                    | Pasted text, voice transcripts, quick notes not yet filed                                                       | Messy is fine                                  |
| `Projects/golden-fur/sessions/NN-<slug>/`            | `plan` skill + `session-documenter` + `code-reviewer`       | one self-contained folder per session: `plan.md`, `testing/` (testing.md + Postman/SQL), `reviews/`, `context/` | Working area                                   |
| `Projects/golden-fur/sessions/_legacy/`              | frozen                                                      | the pre-2026-09 `testing/{custom,issues}/` + `reviews/feat/` trees — never add                                  | Frozen                                         |
| `Projects/golden-fur/shared/context/`                | You (moved manually)                                        | Capstone proposal, architecture docs, roadmaps, report PDFs                                                     | **Sensitive** — see [security.md](security.md) |
| `Projects/golden-fur/shared/decisions/`              | AI agent (or you)                                           | ADRs — "why we did X", `YYYY-MM-DD-slug.md`                                                                     | Working area                                   |
| `Projects/golden-fur/shared/design/`                 | You (moved manually)                                        | Role-dashboard mockup images                                                                                    | Working area                                   |
| `Projects/golden-fur/shared/research/`               | `research-capture-agent` (or you)                           | Cited literature / interview sources with citation metadata                                                     | Working area                                   |
| `Areas/Reviews/`                                     | `weekly-reviewer` agent only                                | One file per weekly review, `<YYYY-MM-DD>.md`                                                                   | Generated                                      |
| `Library/golden-fur/features/<feature>/`             | `vault-librarian` promotion / `workflow-documenter`, or you | `modules/` + `workflows/` (human prose, Mermaid) — curated clean markdown                                       | **Clean only**                                 |
| `Reference/golden-fur/features/<feature>/workflows/` | `workflow-documenter` only                                  | Machine-readable workflow step-graphs (YAML frontmatter)                                                        | Generated                                      |

## The one hard rule

Nothing reaches `Library/` except through a deliberate rewrite (the
"promotion" step — see [workflows.md](workflows.md)). If you're filing
something raw, it goes to `Inbox/` or `Projects/<project>/`, never
straight into `Library/` — even if you're confident it's already clean.

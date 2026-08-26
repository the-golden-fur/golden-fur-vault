---
title: Folder guide
date: 2026-08-24
tags: [docs, folders]
---

# Folder guide

Where things live, and who puts them there — you, or an AI agent.

| Folder                          | Who writes here                                                                              | What goes in it                                                                                                                                     | Stay messy or clean?                                                        |
| ------------------------------- | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `Inbox/`                        | You (paste/drop) or an AI agent filing a raw capture                                         | Pasted text, voice transcripts, quick notes not yet filed                                                                                           | Messy is fine                                                               |
| `Projects/<project>/testing/`   | AI agent (or you)                                                                            | Verification docs, Postman collections, SQL fixtures — subfoldered as `testing/issues/NN-summary/` and `testing/custom/NN-summary/`                 | Working area                                                                |
| `Projects/<project>/docs/`      | AI agent (or you)                                                                            | Working docs, meeting notes, drafts, `docs/changelog/<date>-<slug>.md` entries                                                                      | Working area                                                                |
| `Projects/<project>/decisions/` | AI agent (or you)                                                                            | ADRs — "why we did X" notes                                                                                                                         | Working area                                                                |
| `Projects/golden-fur/context/`  | You (moved manually)                                                                         | Reference material moved from `golden-fur/temp/context/` — capstone proposal, architecture docs, roadmaps, report PDFs. Contains `Credentials.docx` | **Sensitive** — see [security.md](security.md)                              |
| `Projects/golden-fur/design/`   | You (moved manually)                                                                         | Role-dashboard mockup images moved from `golden-fur/temp/design/`                                                                                   | Working area                                                                |
| `Areas/`                        | You, mostly                                                                                  | Ongoing responsibilities not tied to one project                                                                                                    | Working area                                                                |
| `Areas/Reviews/`                | `weekly-reviewer` agent only                                                                 | One file per review, `<YYYY-MM-DD>.md`                                                                                                              | Generated — don't hand-edit, it'll just get overwritten in spirit next week |
| `Resources/`                    | You                                                                                          | Reference material, not project- or time-bound                                                                                                      | Working area                                                                |
| `Archive/`                      | You                                                                                          | Anything inactive, kept for history                                                                                                                 | Working area                                                                |
| `Library/`                      | **Only** the `vault-librarian` agent's promotion step, or you doing the same rewrite by hand | Curated, clean markdown meant to be opened and read directly — proper headings, short paragraphs, no raw dumps                                      | **Clean only**                                                              |

## The one hard rule

Nothing reaches `Library/` except through a deliberate rewrite (the
"promotion" step — see [workflows.md](workflows.md)). If you're filing
something raw, it goes to `Inbox/` or `Projects/<project>/`, never
straight into `Library/` — even if you're confident it's already clean.

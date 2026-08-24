---
title: Workflows
date: 2026-08-24
tags: [docs, workflows]
---

# Workflows

The actual "I put a file here, then what happens" pipelines.

## File a raw note

```
You paste text / a transcript / a capture
  → ask an AI tool to file it (note-filing skill / vault-librarian agent)
  → it adds frontmatter (title, date, tags, project)
  → it picks a destination:
      - Inbox/                         if no obvious project
      - Projects/<project>/testing/    test logs, QA notes
      - Projects/<project>/docs/       working docs, meeting notes, drafts
      - Projects/<project>/decisions/  ADRs / "why we did X"
  → it cross-links related notes it finds nearby
  → it never overwrites an existing dated file — appends instead
  → it cleans up any temp/scratch files it created along the way
```

Never lands in `Library/`. See [.agent/skills/note-filing.md](../.agent/skills/note-filing.md).

## Promote a note into Library/

```
Existing note in Inbox/ or Projects/golden-fur/
  → you ask the vault-librarian agent to promote it
  → it rewrites the note into clean prose/headings, strips raw dumps
  → frontmatter is kept (date bumped only if content changed substantially)
  → written to Library/golden-fur/
  → original is left in place unless you ask to remove it
```

This is the **only** path into `Library/`. See
[.agent/agents/vault-librarian.md](../.agent/agents/vault-librarian.md).

## Weekly review

```
(no input from you needed)
  → you ask for a weekly review / "what happened this week"
  → weekly-reviewer agent reads everything modified in the last 7 days
    across Inbox/, Projects/, Areas/, Library/ (excluding Areas/Reviews/ itself)
  → read-only over all of that — never edits/moves/deletes what it reads
  → writes one summary: Areas/Reviews/<YYYY-MM-DD>.md
```

See [.agent/agents/weekly-reviewer.md](../.agent/agents/weekly-reviewer.md).

## Git workflow (branch → commit → PR → merge)

```
You describe new work
  → branch-naming skill picks <type>/<short-description>, branches off main
      (this repo has no dev — main is the only base)
  → you make your changes (filing notes, editing docs, reorganizing)
  → commit skill stages + writes a conventional commit, only when asked
  → pr skill opens a PR targeting main (merge commit only, no squash)
  → merge-pr skill checks readiness, confirms with you, merges with a
      crafted merge-commit title/description — only when explicitly asked
```

See [.agent/skills/](../.agent/skills/) for each step's full rules.

## What AI agents never do

- Never write to `../golden-fur` (the code repo) from this vault, or vice
  versa — each repo's tools stay scoped to their own repo.
- Never write straight into `Library/` outside the promotion step.
- Never merge a PR without you explicitly asking, even if you asked it to
  open the PR.

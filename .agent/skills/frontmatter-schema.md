# Frontmatter schema

**Purpose:** the canonical YAML frontmatter fields used across this vault,
so filing, review, and linking agents can reliably query/filter notes
without guessing at field names.

**Use whenever** writing or checking a note's frontmatter —
`note-filing`, `vault-librarian`, `weekly-reviewer`, `research-capture-agent`,
and `backlink-curator` all depend on this staying consistent.

## Required fields (every note)

```yaml
---
title: <short title>
date: <YYYY-MM-DD>
tags: [...]
project: <project slug, e.g. golden-fur>
---
```

- `title` — short, human-readable, matches the note's main heading.
- `date` — creation date. Only update it if a note is substantially
  rewritten (e.g. promoted to `Library/`) — don't bump it for a small edit.
- `tags` — lowercase, kebab-case, free-form. No fixed vocabulary is
  enforced; keep tags short and reusable across notes rather than
  inventing a one-off tag per note.
- `project` — the project this note belongs to (`golden-fur` today). Omit
  only for genuinely project-agnostic notes.

## Optional fields (add when they apply)

- `type` — one of `capture` (a raw Inbox note; the default, can be
  omitted), `decision` (ADR-style), `review` (weekly rollup), `resource`
  (research-capture-agent output), or `library` (promoted, Library/-only
  content). Lets an agent filter notes by kind without parsing folder
  paths.
- `source` — citation for research material: a URL, DOI, book/paper title,
  or `interview: <name>, <date>`. Required on anything
  `research-capture-agent` files into `Resources/`.
- `status` — for `decisions` or anything with a lifecycle: `draft`,
  `active`, `superseded`, `resolved`.

Don't add fields beyond these without updating this file first — a field
only one note uses can't be relied on by any agent that reads frontmatter.

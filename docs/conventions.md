---
title: Conventions
date: 2026-08-24
tags: [docs, conventions]
---

# Conventions

## Frontmatter

Every note gets YAML frontmatter:

```yaml
---
title: <short title>
date: <YYYY-MM-DD>
tags: [...]
project: <project slug, e.g. golden-fur>
---
```

`project` is omitted for notes that aren't scoped to one project (e.g. a
general `Areas/` or `Projects/golden-fur/shared/` note). Weekly review notes additionally
use `tags: [review]`.

## Naming

- Dated notes: `YYYY-MM-DD-short-slug.md` (ADRs under
  `Projects/golden-fur/shared/decisions/`).
- Session records: one self-contained
  `Projects/golden-fur/sessions/NN-<slug>/` folder per session (`plan.md`,
  `testing/`, `reviews/`, `context/`) — one monotonic `NN` counter (see
  `sessions/README.md`). Legacy history is frozen under
  `sessions/_legacy/{custom,issues}/`.

## Never overwrite

If a matching dated file already exists, append a new section to it
instead of overwriting. Filing tools should also clean up any temp/scratch
files they create (anything `.gitignore` would match: `.tmp/`,
`_staging/`, `_extract/`, `*.tmp`, `*.part`) before finishing.

## The Inbox → Projects → Library lifecycle

1. **`Inbox/`** — raw capture, no cleanup expected.
2. **`Projects/<project>/`** — working material once you know which
   project it belongs to. Still allowed to be messy (raw logs, drafts).
3. **`Library/`** — only reached via the deliberate "promotion" rewrite
   (see [workflows.md](workflows.md#promote-a-note-into-library)). Clean
   prose and headings only, no raw dumps.

A note doesn't have to pass through every stage — most stay in `Inbox/` or
`Projects/` forever. Promotion to `Library/` is reserved for things worth
reading later without re-editing.

## Commit / PR message format

Both use `<type>(<scope>): <subject>` — imperative mood, no trailing
period. Types: `docs`, `fix`, `chore`, `refactor`. Scope is the folder or
project touched (e.g. `testing`, `inbox`, `reviews`, `golden-fur`). See
[.agent/skills/commit.md](../.agent/skills/commit.md) and
[.agent/skills/pr.md](../.agent/skills/pr.md) for the full rules.

# Weekly review format

**Purpose:** the structure `weekly-reviewer` writes into
`Areas/Reviews/<date>.md`. Keeping this in one place stops the format from
drifting week to week.

## Frontmatter

```yaml
---
title: Weekly review — <YYYY-MM-DD>
date: <YYYY-MM-DD>
tags: [review]
project: <project slug, if the review is scoped to one project>
type: review
---
```

## Body structure

```markdown
# Weekly review — <YYYY-MM-DD>

## <Project or Area name>

- What was filed / what changed (a few bullets, not a raw file listing).
- Decisions made or test results that landed.
- Anything left unresolved or worth following up on.

## <Next project or area, if any>

...

## Unsorted / Inbox

- Notes that landed in Inbox/ and haven't been filed further yet, if any.
```

- One `##` section per project/area touched that week, plus an
  `Unsorted / Inbox` section if anything's sitting there unfiled.
- A few sentences or a short bullet list per section — this is a rollup,
  not a changelog dump. Link to the specific notes it's summarizing with
  `[[wikilinks]]` (see `cross-linking.md`) rather than restating their
  content in full.
- Skip a section entirely if nothing happened there that week — don't pad
  it with "no activity."

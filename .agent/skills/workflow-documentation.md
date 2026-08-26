# Workflow documentation

**Purpose:** document golden-fur's business-process workflows (login flows,
approval flows, booking/checkout flows, etc.) as a **matched pair** of notes
per workflow — one for humans, one for machines — grouped by the module
numbering already established in `Library/golden-fur/modules/` (M01–M14).

**Use whenever** asked to document, diagram, or map out how a workflow/process
works, or to keep an existing workflow note in sync after the underlying code
changes.

## Why two files instead of one

A single note can't serve both audiences well: a person wants prose, a
diagram, and the "why"; a script or another LLM wants a flat, parseable step
list with no prose to strip out first. Rather than compromise on one file,
every workflow gets both:

- **Human-readable** — `Library/golden-fur/workflows/<Code>-<slug>.md`.
  Follows this vault's `Library/` rule: clean prose, headings, a rendered
  Mermaid diagram, short "why" notes. Meant to be opened in Obsidian and
  read.
- **Machine-readable** — `Projects/golden-fur/docs/workflows/<Code>-<slug>.md`.
  All substance lives in the YAML frontmatter as a structured step list — a
  parser (or another LLM) should be able to read _just_ the frontmatter and
  get the complete workflow, no prose-scraping required. The body is a
  one-line pointer back to the human version.

Both files share the same `<Code>-<slug>` so they're trivially pairable.

## Naming

`<ModuleCode>-<NN>-<slug>.md`, e.g. `M01-01-staff-account-creation.md`.

- `ModuleCode` matches an existing `Library/golden-fur/modules/M0X-*.md` file
  — a workflow always belongs to exactly one primary module, even if it
  touches others (cross-module effects go in `related_modules`, not a
  duplicate file).
- `NN` is a two-digit sequence, ordered by whenever each workflow was first
  documented for that module — not a canonical/authoritative ordering.
- `slug` is a short kebab-case name for the workflow itself, not the module.

## Grounding rule

Every step must trace back to actual code — a service function, a
controller, a DB trigger/migration, an RLS policy — not to prose assumptions
or the module note alone (module notes summarize; they sometimes omit a
branch or an edge case the code actually has, e.g. a compensating rollback or
a DB trigger that decides something the service function doesn't). Read the
relevant `server/src/features/<feature>/` service/controller and any
migration that defines a trigger or default before drafting steps. List every
file you actually read in the machine file's `source:` field.

If the module note and the code disagree, trust the code, and flag the
discrepancy to the user — the module note may be stale.

## Human file template

```markdown
---
title: "M0X · <Workflow Name>"
date: <YYYY-MM-DD>
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M0X
---

# M0X · <Workflow Name>

**Actors:** <roles involved>
**Code:** `<key source files/paths>`
**Part of:** [[M0X-<module-slug>|<Module Title>]]

<1-3 sentence plain-language summary of what triggers this workflow and
what it accomplishes.>

\`\`\`mermaid
flowchart TD
...
\`\`\`

## Notes

<Bullet points for anything the diagram can't carry on its own: non-obvious
business rules, "why", edge cases, best-effort/failure semantics. Skip this
section if the diagram is fully self-explanatory.>

## Relationship to other modules

<Only if this workflow crosses into other modules beyond its home M0X — link
them, e.g. "Notifies via [[M11-notification|M11]]".>
```

### Mermaid conventions

Match the house style already used for these diagrams:

- `flowchart TD` (top-down) unless the process is naturally left-right.
- Rounded `(["..."])` nodes for START and every END/terminal outcome — label
  each END with what actually happened (`END: Blocked — ...`,
  `END: <status> — ...`), not just "End".
- Curly `{"..."}` nodes for decisions/conditions; label the edges leaving a
  decision with the condition value (`-- "Yes" -->`, `-- "No" -->`), not
  generic arrows.
- Square `["..."]` nodes for actions/system steps.
- Wrap long labels with `\n` inside the quoted string rather than letting
  one node grow very wide.
- A validation-error path should loop back to the input step it corrects,
  the same way the sample account-creation diagram loops `F --> B`.

## Machine file template

All substance is in frontmatter. The step graph uses one vocabulary:

```yaml
---
id: <same as filename, no extension>
module: M0X
title: <Workflow Name>
actors: [Role, Role]
trigger: <one-line: what starts this workflow>
outcome_success: <one-line: end state when it completes>
outcome_failure: [short_reason_slug, short_reason_slug]
related_modules: [M0Y]
source:
  - path/to/service.ts
  - path/to/migration.sql
steps:
  - id: start
    type: start
    label: <text>
    next: <id>
  - id: <id>
    type: input | action | decision | end
    actor: [Role]              # omit if not actor-specific
    label: <text>
    next: <id>                 # input/action/start nodes: single next
    branches:                  # decision nodes only, instead of next
      - condition: "Yes"
        next: <id>
      - condition: "No"
        next: <id>
    result: success | blocked | error   # end nodes only
---

# M0X · <Workflow Name>

Machine-readable companion to
[[<Code>-<slug>|the human-readable version]] in `Library/golden-fur/workflows/`.
```

Keep the body to that one line — no restating the diagram in prose here.

## Cross-linking

- The workflow's home module note (`Library/golden-fur/modules/M0X-*.md`)
  should link to every workflow filed under it — add or update a short
  `## Workflows` section there listing `[[M0X-NN-slug|Workflow Name]]`.
- The human workflow note links back to its module via `**Part of:**`.
- Follow `.agent/skills/cross-linking.md` for any other related-note links
  (e.g. a workflow that feeds into another workflow).

## Multi-file agent-side note

This convention is deliberately readable by hand (Mermaid renders in
Obsidian) and by a script (frontmatter-only parse of the machine file) at the
same time — don't let either file's authoring shortcut the other: don't
paste raw YAML into the human file, and don't leave prose explanations in the
machine file's body that duplicate what's already in `steps`.

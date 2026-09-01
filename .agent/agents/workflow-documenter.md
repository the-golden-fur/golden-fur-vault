# workflow-documenter

**Role:** drafts or updates the paired human-readable + machine-readable
workflow docs described in `.agent/skills/workflow-documentation.md`, by
reading the actual golden-fur implementation (not just the existing module
notes) and turning it into a Mermaid diagram plus a structured step list.

**Scope — the one deliberate exception in this vault's agent set:** every
other vault agent reads/writes only within this repo. This one is different
on purpose, because a workflow doc that isn't grounded in real code drifts
from the app the moment someone changes a branch condition:

- **Reads** `../golden-fur` (the code repo) freely — services, controllers,
  routes, `supabase/migrations/` (especially triggers and column defaults,
  which decide things the service-layer code doesn't show), and RLS
  policies.
- **Never writes** to `../golden-fur`. All output — both doc variants — is
  written only within this vault, under `Library/golden-fur/workflows/` and
  `Projects/golden-fur/docs/workflows/`.

**Use whenever** asked to document a workflow, or add workflow diagrams for
a module. For a **refresh after code changed**, this is triggered once when
a golden-fur PR is opened (via that repo's `workflow-doc-sync` skill over
the whole branch diff) — not after every task or commit, which would spawn
this agent repeatedly and burn session budget. Running it by hand any time
is still fine.

Follow `.agent/skills/workflow-documentation.md` for the full template,
naming convention, Mermaid house style, and the machine-file step schema.
Follow `.agent/skills/cross-linking.md` for linking the workflow note back
to its module note.

## Process

1. **Identify the workflow's home module.** Match it to one of
   `Library/golden-fur/modules/M0X-*.md`. If it doesn't fit cleanly into one,
   ask rather than guessing — a workflow note only ever lives under one
   module.
2. **Read the module note first** for context (actors, terminology, what it
   already claims about this workflow) — then verify every claim against the
   actual code. Read the relevant service(s), controller, route guards, and
   any migration that defines a trigger, default, or RLS policy touching the
   tables involved. Do not draft steps from the module note alone.
3. **Draft the step graph** using the machine-file vocabulary
   (start/input/action/decision/end) before writing prose — the human
   diagram is a rendering of this same graph, not a separately-invented one.
   Both files must describe the identical set of steps and branches.
4. **Write the machine file** (`Projects/golden-fur/docs/workflows/`):
   frontmatter carries the full step graph plus `source:` listing every file
   actually read. Body is one line pointing at the human file.
5. **Write the human file** (`Library/golden-fur/workflows/`): the same graph
   rendered as a Mermaid `flowchart TD`, with a short prose intro and a
   `## Notes` section for anything the diagram can't carry (best-effort
   semantics, non-obvious business rules, why a branch exists).
6. **Cross-link**: add the new workflow to the module note's `## Workflows`
   section (create that section if it doesn't exist yet); set `**Part of:**`
   in the human file back to the module.
7. **When updating an existing workflow doc** (code changed): re-verify every
   step against current code rather than patching only the part you were
   told changed — a step upstream may have shifted too. Keep the same
   `<Code>-<slug>` filenames so existing links don't break.
8. **Flag, don't silently resolve, any conflict** between what a module note
   claims and what the code does — the module note may need a follow-up
   correction, but that's a separate edit for the user to confirm, not
   something to fix unasked as a side effect of documenting a workflow.

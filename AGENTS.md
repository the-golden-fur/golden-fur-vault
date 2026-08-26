# golden-fur-vault

Private Obsidian-compatible second brain for the [golden-fur](../golden-fur)
capstone project (and any future projects). Notes, meeting transcripts,
working docs, test logs, and planning material live here — not in the code
repo.

## Folders

- **`Inbox/`** — raw capture: pasted text, voice transcripts, quick notes not
  yet filed. Messy is fine here.
- **`Projects/<project>/`** — active working material for a specific project.
  For golden-fur:
  - `testing/` — verification docs, Postman collections, and SQL fixtures
    for each GitHub issue or ad-hoc request, subfoldered as
    `testing/issues/NN-summary/` and `testing/custom/NN-summary/`.
  - `docs/` — working docs, meeting notes, drafts, and
    `docs/changelog/<date>-<slug>.md` entries.
  - `decisions/` — ADRs / "why we did X" notes.
  - `context/` — reference material moved from `golden-fur/temp/context/`
    (capstone proposal, architecture docs, sprint/epic roadmaps, academic
    report PDFs, etc.). Contains a `Credentials.docx` — handle this folder
    as sensitive.
  - `design/` — role-dashboard mockup images moved from
    `golden-fur/temp/design/`.
- **`Areas/`** — ongoing responsibilities not tied to one project
  (e.g. weekly review summaries land in `Areas/Reviews/`).
- **`Resources/`** — reference material, not project- or time-bound.
- **`Archive/`** — anything inactive, kept for history.
- **`Library/`** — curated, human-readable notes only. **Nothing goes in here
  except clean, well-formatted markdown meant to be opened and read directly
  in Obsidian**: proper headings, short paragraphs, no raw JSON/HTML/log
  dumps, no walls of unformatted extracted text. `Inbox/` and `Projects/` can
  be messy working areas; `Library/` cannot. A note is only promoted into
  `Library/` as a separate, deliberate cleanup step — rewritten into clean
  prose/headings — never copied as-is from a raw extraction or tool output.

## Filing convention

New notes get YAML frontmatter:

```yaml
---
title: <short title>
date: <YYYY-MM-DD>
tags: [...]
project: <project slug, e.g. golden-fur>
---
```

Anything under `*/golden-fur/` relates to the golden-fur capstone app
(the two-branch pet care management system — grooming, hotel, daycare,
veterinary — see `../golden-fur/README.md` and `../golden-fur/docs/`).

## Reusable skills/agents (multi-tool)

`.agent/skills/` and `.agent/agents/` hold the canonical, tool-agnostic
instructions for this vault's reusable AI workflows:

**Agents** (spawnable subagents with restricted tools):

- `vault-librarian` — files raw input and promotes notes into `Library/`.
- `weekly-reviewer` — summarizes the last 7 days into `Areas/Reviews/`.
- `backlink-curator` — inserts `[[wikilinks]]` between related notes and
  flags orphaned ones (read-mostly: `Read`, `Grep`, `Glob`, `Edit`).
- `research-capture-agent` — files literature/interview sources into
  `Resources/` with citation metadata, distinct from `note-filing`'s
  default handling of raw working notes.
- `skill-agent-auditor` — read-only review of a third-party skill/agent
  file for prompt-injection/scope-creep risk before it's adopted.
- `workflow-documenter` — the one deliberate exception to "vault-only":
  reads the sibling `../golden-fur` code repo to ground workflow docs in
  real behavior, but only ever writes within this vault.

**Skills** (auto-invoked reference material):

- `note-filing` — file a raw capture: destination folder, frontmatter,
  never overwrite.
- `frontmatter-schema` — canonical YAML fields (`title`, `date`, `tags`,
  `project`, plus optional `type`/`source`/`status`).
- `cross-linking` — when/how to add wikilinks; powers `backlink-curator`.
- `weekly-review-format` — the structure `weekly-reviewer` writes.
- `agents-md-maintenance` — keeps this file canonical and every tool's
  root context file (e.g. `.claude/CLAUDE.md`) a thin pointer to it.
- `skill-security-audit` — the checklist `skill-agent-auditor` runs.
- `workflow-documentation` — the paired human-readable
  (`Library/golden-fur/workflows/`) + machine-readable
  (`Projects/golden-fur/docs/workflows/`) format `workflow-documenter`
  writes to, grouped by module (M01–M14).

Plus this repo's git workflow: `branch-naming` (name and create a branch),
`commit` (write and create a conventional commit — performs the commit
itself, not just a drafted message), `pr` (open a PR targeting `main`,
merge commit only — this repo has a single `main` branch, no `dev`),
`merge-pr` (confirm readiness and get explicit go-ahead, then merge a PR
with a crafted merge-commit title/description), and `pre-commit-checks`
(run the `(check)`/`(fix)`-labeled VS Code task — Prettier format — auto-
fixing what it can; always runs as `commit`'s first step, also invocable
standalone). Any AI coding tool working in this repo should read the
relevant file under `.agent/` before doing that kind of task. They
operate only within this repo — never on `../golden-fur`.

Tool-specific directories are thin adapters over that same content, wired up
per tool's own discovery mechanism:

- **Claude Code** — `.claude/skills/<name>/SKILL.md` (auto-invoked skill)
  and `.claude/agents/<name>.md` (spawnable subagent with restricted
  tools), each just pointing at the matching `.agent/` file.
- **Gemini CLI** — `.gemini/commands/<name>.toml` (manually invoked as
  `/<name>`).
- **Codex CLI** — `.codex/prompts/<name>.md` (manually invoked as
  `/<name>`; verify your Codex version picks up project-scoped prompts).
- **Other tools** (e.g. Antigravity) without a documented per-repo
  skill/command convention — they should still pick this up by reading
  `.agent/` directly, or via this file if they support an `AGENTS.md`-style
  root context file.

When updating one of these workflows, edit the canonical file under
`.agent/` — the adapters shouldn't need to change unless the tool's own
discovery metadata (name/description/tools) changes.

## Privacy

This vault is private. It accumulates personal notes, meeting transcripts,
and possibly sensitive client info from the Golden Fur business — do not make
this repo public. `Projects/golden-fur/context/` in particular contains a
`Credentials.docx` — treat it as sensitive and don't surface its contents
outside this vault.

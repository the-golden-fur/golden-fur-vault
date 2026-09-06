# golden-fur-vault

Private Obsidian-compatible second brain for the [golden-fur](../golden-fur)
capstone project (and any future projects). Notes, meeting transcripts,
working docs, test logs, and planning material live here — not in the code
repo.

## Folders

- **`Inbox/`** — raw capture: pasted text, voice transcripts, quick notes not
  yet filed. Messy is fine here.
- **`Projects/<project>/`** — record of work on a specific project. For
  golden-fur it has **exactly two** subtrees:
  - **`sessions/`** — one folder-set per AI session (a request thread that
    changed the app), the project's running changelog. a self-contained `NN-<slug>/` folder per session — `plan.md`, `testing/` (verification record + click-by-click manual test, plus Postman/SQL), `reviews/` (`code-review` pass summaries), `context/` (copied context files). One monotonic `NN` counter continuing from `sessions/_legacy/` (the pre-2026-09 `testing/` tree). See
    `Projects/golden-fur/sessions/README.md`.
  - **`shared/`** — project-wide material not tied to one session:
    `shared/context/` (capstone proposal, architecture docs, roadmaps,
    report PDFs — **sensitive**: treat anything credential-like here as
    such), `shared/decisions/` (ADRs / "why we did X", `YYYY-MM-DD-slug.md`),
    `shared/design/` (role-dashboard mockups), `shared/research/` (cited
    literature/interview sources — filed via `vault-librarian` with
    `frontmatter-schema` citation fields).
- **`Areas/`** — ongoing responsibilities not tied to one project
  (e.g. weekly review summaries land in `Areas/Reviews/`).
- **`Library/`** — curated, **human-readable** notes only, grouped by
  golden-fur feature: `Library/golden-fur/features/<feature>/{modules,workflows}/`.
  **Nothing goes in here except clean, well-formatted markdown** meant to be
  opened and read in Obsidian — proper headings, short paragraphs, a rendered
  Mermaid diagram for workflows; no raw JSON/HTML/log dumps. `Inbox/` and
  `Projects/` can be messy; `Library/` cannot. Promotion into `Library/` is a
  separate, deliberate cleanup step — never a raw copy.
- **`Reference/`** — the **machine-readable** counterpart to `Library/`, same
  feature grouping: `Reference/golden-fur/features/<feature>/workflows/`. Each
  file is a workflow step-graph that lives entirely in YAML frontmatter so a
  parser or another LLM can read it without prose-scraping. Written only by
  `workflow-documenter`.
- **`docs/`** — this vault repo's own meta-docs (setup, conventions,
  folder-guide, security) — for a person working _on the vault_, not project
  content.

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
  Also covers filing a cited research source into
  `Projects/golden-fur/shared/research/` (with `frontmatter-schema`).
- `workflow-documenter` — the one deliberate exception to "vault-only":
  reads the sibling `../golden-fur` code repo to ground workflow docs in
  real behavior, but only ever writes within this vault
  (`Library/golden-fur/features/<feature>/workflows/` +
  `Reference/golden-fur/features/<feature>/workflows/`). Code-change
  refreshes are an **explicit-request-only** drift check now (that repo's
  `workflow-doc-sync` skill) — no longer a per-PR step.
- `session-documenter` — another deliberate "vault-only" exception: reads
  `../golden-fur`'s diff/log to write the session record (near-beginner
  `plan.md`, click-by-click `testing/testing.md`, copied context,
  Postman/SQL) for a change just implemented — but only ever writes within
  this vault. Runs at implementation-finish. It takes test pass/fail counts
  from that session's `ci-verifier` run rather than re-running the suites.

One more agent is defined in `../golden-fur` but also acts here — read-only,
wired into this repo's `pr` skill's finish pipeline:

- `ci-verifier` (canonical in `../golden-fur`; `.agent/agents/ci-verifier.md`
  here is a pointer) — runs the `✅ CI: Verify All` VS Code task across
  **both** repos (this vault's `format:check`, golden-fur's
  tests/lint/format/build) and reports one pass/fail. Runs checks only —
  never fixes; on a green pass it writes `.git/ci-verifier-pass` (the
  verified `HEAD` sha) for the `pr-guard` hook. Its write-side counterpart
  `ci-fixer-agent` is auto-invoked when it reports red.

Code review at `pr-to-dev` time is the built-in `code-review` skill run
**in-session** on the golden-fur side (not a subagent); it drops a summary
file into that branch's `Projects/golden-fur/sessions/<NN-slug>/reviews/`,
which is the evidence this repo's `pr-guard` also checks for. See
`Projects/golden-fur/shared/decisions/2026-08-30-unbiased-code-reviewer-subagent.md`
(the bespoke `code-reviewer` subagent was retired 2026-09-06).

**Skills** (auto-invoked reference material):

- `note-filing` — file a raw capture: destination folder, frontmatter,
  never overwrite. Covers cited research sources too.
- `frontmatter-schema` — canonical YAML fields (`title`, `date`, `tags`,
  `project`, plus optional `type`/`source`/`status`).
- `cross-linking` — when/how to add `[[wikilinks]]`; applied inline during
  filing and review.
- `agents-md-maintenance` — keeps this file canonical and every tool's
  root context file (e.g. `.claude/CLAUDE.md`) a thin pointer to it.
- `skill-security-audit` — checklist for vetting a third-party skill/agent
  for prompt-injection / scope-creep risk before adopting it.
- `workflow-documentation` — the paired human-readable
  (`Library/golden-fur/features/<feature>/workflows/`) + machine-readable
  (`Reference/golden-fur/features/<feature>/workflows/`) format
  `workflow-documenter` writes to, grouped by **feature** with the M-code
  (M01–M14) kept as the filename prefix.
- `session-documentation` — the `Projects/golden-fur/sessions/` format
  (`NN-<slug>/{plan.md,testing/,reviews/,context/}`)
  `session-documenter` writes for every golden-fur change. One monotonic
  `NN` counter continuing from the frozen legacy
  `sessions/_legacy/` (currently `63`).
- `plan` — plan-only mode: design a change and write it up for a
  near-beginner in `sessions/<NN-slug>/plan.md` **without touching any
  code**. Invoked when the user asks to "just plan" / "don't touch code" —
  golden-fur's `session-router` hook routes that phrasing here.

Plus this repo's git workflow: `branch-naming` (name and create a branch),
`commit` (write and create a conventional commit — performs the commit
itself, not just a drafted message), `pr` (open a PR targeting `main`,
merge commit only — this repo has a single `main` branch, no `dev`),
`merge-pr` (confirm readiness and get explicit go-ahead, then merge a PR
with a crafted merge-commit title/description), and `pre-commit-checks`
(run the `(check)`/`(fix)`-labeled VS Code task — Prettier format —
standalone-on-request only; **no longer a pipeline step**). Any AI coding
tool working here should read the relevant `.agent/` file first.

**`pr` is a finish pipeline**, in this order: `branch-naming` (if on
`main`) → `ci-verifier` (both repos) → `ci-fixer-agent` if red, then
re-verify → confirm the session's `sessions/` + `Reference/` material is
written → `commit` → push → `gh pr create`. `commit` on its own runs **no
gates**. Line endings are handled by `.gitattributes` (`* text=auto
eol=lf`).

## Auto-run wiring

`.claude/settings.json` wires two Claude Code hooks (Claude-specific — no
`.agent/` twin; other tools replicate the intent via their own mechanisms):

- **`session-router`** (`UserPromptSubmit`) — pattern-matches the prompt and
  injects guidance: "just plan / don't touch code" → the `plan` skill,
  edit-nothing; "open a PR / ship it / /pr" → the finish pipeline above.
  Deterministic _decision_; the skills/agents still do the work.
- **`pr-guard`** (`PreToolUse` on `Bash`) — blocks `gh pr create` until
  `ci-verifier` has left `.git/ci-verifier-pass` for the current `HEAD`.

(The `gitkeep-sweep` `Stop` hook was removed 2026-09-06 — it ran a
whole-tree `find` on every turn end for a near-never need.)

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
this repo public. Treat `Projects/golden-fur/shared/context/` as the place
credential-like or otherwise sensitive material would land — don't surface
its contents outside this vault, and never copy a secrets file into a
session's `context/` folder.

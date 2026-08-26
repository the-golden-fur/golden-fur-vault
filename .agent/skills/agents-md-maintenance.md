# AGENTS.md maintenance

**Purpose:** `AGENTS.md` at the repo root is the canonical, tool-agnostic
description of this vault's structure and workflows. Every other tool's
root context file should be a thin pointer to it, not a second copy — so
one edit updates every tool at once instead of drifting out of sync.

**Use whenever** `AGENTS.md` changes in a way that affects what an
agent/tool needs to know (new folder, new skill/agent, changed convention),
or when setting up a new AI tool's config in this repo.

## The pattern

- **`AGENTS.md`** (repo root) — canonical content. Edit this one.
- **`.claude/CLAUDE.md`** — one line: `See ../AGENTS.md`. Claude Code loads
  this automatically as project memory; keep it a pointer, never a copy.
  This mirrors the convention already used in the sibling `golden-fur`
  repo's `.claude/CLAUDE.md`.
- Other tools' root context files (e.g. a `GEMINI.md` at the repo root, if
  Gemini CLI starts reading one there — distinct from the per-command
  `.gemini/commands/*.toml` files that already exist) should follow the
  same one-line-pointer pattern if/when they're actually needed — don't
  pre-create a pointer file for a convention a tool doesn't use yet.

## Checklist when AGENTS.md changes

1. Confirm `.claude/CLAUDE.md` still exists and still just says
   `See ../AGENTS.md` (not stale content copied in).
2. If a new skill or agent was added, confirm `AGENTS.md`'s "Reusable
   skills/agents" section lists it, in the same one-line rationale style
   as the existing entries.
3. Don't duplicate `AGENTS.md`'s content into any other root file — link to
   it instead.

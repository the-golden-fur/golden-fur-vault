---
title: AI tools
date: 2026-08-24
tags: [docs, ai-tools]
---

# AI tools

This repo supports several AI coding tools. They all read the same
instructions — just wired up differently per tool.

## Canonical source: `.agent/`

`.agent/skills/` and `.agent/agents/` hold the real, tool-agnostic
instructions:

- **Skills** (`.agent/skills/`): `note-filing`, `branch-naming`, `commit`,
  `pr`, `merge-pr`.
- **Agents** (`.agent/agents/`): `vault-librarian`, `weekly-reviewer`.

When a workflow needs to change, edit the file under `.agent/` — the
per-tool adapters below shouldn't need touching unless the tool's own
discovery metadata (name/description/tool permissions) changes.

## Per-tool adapters

| Tool | Where it reads from | How it's invoked |
| --- | --- | --- |
| Claude Code | `.claude/skills/<name>/SKILL.md` (skills), `.claude/agents/<name>.md` (subagents, restricted tools) | Skills auto-invoke when relevant; agents are spawned |
| Gemini CLI | `.gemini/commands/<name>.toml` | Manual: `/<name>` |
| Codex CLI | `.codex/prompts/<name>.md` | Manual: `/<name>` (verify your Codex version reads project-scoped prompts) |
| Other tools (e.g. Antigravity) | `AGENTS.md` (root context) or `.agent/` directly | Depends on the tool |

Every adapter file is thin — it just points back at the matching `.agent/`
file rather than duplicating the instructions.

## Why four near-duplicate directories exist

Each tool has its own discovery convention (file layout, frontmatter
format) and none of them read each other's format. Rather than pick one
tool, this repo keeps one canonical instruction set (`.agent/`) and a thin
adapter per tool, so switching tools — or using more than one — doesn't
mean rewriting the workflow rules.

## Agent scope

Every agent/skill here operates only within `golden-fur-vault`. None of
them read or write `../golden-fur` (the code repo) — that's a separate
project with its own AI tooling.

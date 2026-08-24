---
name: weekly-reviewer
description: Reads notes in this vault modified in the last 7 days and writes a short summary into Areas/Reviews/<date>.md. Use for a weekly review, "what happened this week", or a recap of recent vault activity.
tools: Read, Grep, Glob, Write
model: sonnet
---

This is the Claude Code adapter for a tool-agnostic subagent. Read and
follow the full role/process at
[.agent/agents/weekly-reviewer.md](../../.agent/agents/weekly-reviewer.md)
before proceeding — that file is the canonical, maintained version (also
usable by other AI coding tools working in this repo); this file exists only
so Claude Code can discover and spawn it with the right tool restrictions.

This is read-only over the vault except for the one summary file you write.

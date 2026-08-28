---
name: testing-documenter
description: Writes the verification record (manual steps, Postman collection, SQL reference) for a change just made to the golden-fur repo, by reading the actual diff and running the real test suites (see testing-documentation skill). Use whenever a bug fix, feature, migration, or architecture change is implemented in golden-fur in response to a specific request — run this as the closing step of that work.
tools: Read, Write, Edit, Grep, Glob, Bash
model: sonnet
---

This is the Claude Code adapter for a tool-agnostic subagent. Read and
follow the full role/process at
[.agent/agents/testing-documenter.md](../../.agent/agents/testing-documenter.md)
before proceeding — that file is the canonical, maintained version (also
usable by other AI coding tools working in this repo); this file exists only
so Claude Code can discover and spawn it with the right tool restrictions.

Unlike every other agent in this vault, you _are_ expected to read the
sibling `../golden-fur` code repo (git diff/log, migrations) and run its
test suites, to ground the doc in what actually changed and actually passes.
You still never _write_ there — every file you create or edit stays within
this vault, under `Projects/golden-fur/testing/issues/` or
`Projects/golden-fur/testing/custom/`.

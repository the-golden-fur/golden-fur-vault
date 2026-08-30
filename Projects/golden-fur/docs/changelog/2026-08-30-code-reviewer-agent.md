---
title: Unbiased code-reviewer subagent added to golden-fur
date: 2026-08-30
tags: [changelog, tooling, code-review]
project: golden-fur
---

A read-only `code-reviewer` subagent was added to the `golden-fur` repo
(`.agent/agents/code-reviewer.md` + Claude/Gemini/Codex adapters). It
reviews a branch's diff with fresh eyes — no authorship, no rationale
beyond the diff — and runs automatically as a step of the `commit`,
`pr-to-dev`, and `pr-dev-to-main` skills, backed by a `PreToolUse` hook in
`golden-fur/.claude/settings.local.json`.

Its reports are filed in this vault under a new folder,
`Projects/golden-fur/testing/reviews/<branch>/`, beside `testing/issues/`
and `testing/custom/`.

Full rationale and file list:
[[../../decisions/2026-08-30-unbiased-code-reviewer-subagent]]. Folder
conventions: [[../../testing/reviews/README]].

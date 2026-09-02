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

Its reports are filed in this vault under
`Projects/golden-fur/sessions/reviews/<branch>/` (was
`Projects/golden-fur/testing/reviews/` before the 2026-09-02 `sessions/`
restructure). The `settings.local.json` backstop is now the checked-in
`pr-guard` hook.

Full rationale and file list:
[[2026-08-30-unbiased-code-reviewer-subagent]]. Folder
conventions: [[../../testing/reviews/README]].

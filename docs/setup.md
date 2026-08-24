---
title: Setup
date: 2026-08-24
tags: [docs, setup]
---

# Setup

How to get this vault open and working on a new machine.

## 1. Clone the repo

```
git clone git@github.com:the-golden-fur/golden-fur-vault.git
```

Clone it as a sibling of `golden-fur` (the code repo) — several notes and
skills reference paths like `../golden-fur` relative to this repo.

```
source/repos/
├── golden-fur/         (code)
└── golden-fur-vault/    (this repo)
```

## 2. Open it in Obsidian (optional but recommended)

This vault is Obsidian-compatible markdown — no Obsidian-specific syntax is
required to read/write notes, but Obsidian gives you backlinks, graph view,
and search across the vault.

- Open Obsidian → "Open folder as vault" → select the `golden-fur-vault`
  checkout.
- `.obsidian/workspace.json`, `workspace-mobile.json`, and `.obsidian/cache/`
  are gitignored (per-device UI state) — your window layout won't sync
  between machines, and that's intentional.

## 3. Install Prettier tooling (optional)

The only Node dependency in this repo is Prettier, used to keep markdown/
YAML/JSON formatting consistent:

```
npm install
npm run format         # write formatting fixes
npm run format:check   # check only, no writes
```

Not required to file notes by hand, but AI tools and any pre-commit checks
may expect it.

## 4. AI tool wiring

If you're using an AI coding tool in this repo, it should already pick up
its instructions automatically — no extra setup per tool:

- **Claude Code** reads `.claude/skills/*/SKILL.md` and `.claude/agents/*.md`.
- **Gemini CLI** reads `.gemini/commands/*.toml`.
- **Codex CLI** reads `.codex/prompts/*.md` (confirm your Codex version
  picks up project-scoped prompts).
- Any other tool should be pointed at `AGENTS.md` (root context file) or
  `.agent/` directly.

See [ai-tools.md](ai-tools.md) for how these all relate to each other.

## 5. Git basics for this repo

- Single `main` branch — there is no `dev`. New work branches off `main`
  and PRs merge back into `main`.
- Branch protection only allows merge commits or rebase — no squash.
- See [../.agent/skills/branch-naming.md](../.agent/skills/branch-naming.md),
  [commit.md](../.agent/skills/commit.md), and [pr.md](../.agent/skills/pr.md)
  for the conventions AI tools (and you) should follow.

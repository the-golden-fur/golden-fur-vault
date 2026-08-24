---
title: Security
date: 2026-08-24
tags: [docs, security]
---

# Security

## This vault is private

`golden-fur-vault` accumulates personal notes, meeting transcripts, and
potentially sensitive client info from the Golden Fur business. Do not make
this repo public, and don't paste its contents into public issues, public
gists, or third-party tools that might index or cache them.

## `Projects/golden-fur/context/` is sensitive

This folder contains `Credentials.docx`, moved here from
`golden-fur/temp/context/`. Treat the whole folder as sensitive:

- Don't surface its contents outside this vault (e.g. don't quote it into
  a GitHub issue, PR description, Slack message, or an external tool).
- Any AI tool reading it should keep that in mind before summarizing or
  cross-linking from it — a link is fine, quoting `Credentials.docx`
  itself is not.

## What not to paste into notes

- Live credentials, API keys, tokens — even in a "private" repo, git
  history is forever. If a secret was pasted by mistake, it needs to be
  rotated, not just deleted from the latest commit.
- Anything you wouldn't want in `git log` permanently, since removing a
  file doesn't remove it from history without a rewrite (which this repo
  doesn't do routinely).

## AI agent scope as a safety boundary

Every skill/agent in this repo (`.agent/`) is scoped to read/write only
within `golden-fur-vault` — never `../golden-fur`. That scoping is also a
safety boundary: it keeps notes (which may reference sensitive project
context) from leaking into the code repo's history, issues, or PRs.

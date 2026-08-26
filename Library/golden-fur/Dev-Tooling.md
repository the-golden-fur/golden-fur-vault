---
title: "Golden Fur — Claude Code Dev Tooling"
date: 2026-08-26
tags: [architecture, golden-fur, reference, dev-tooling]
project: golden-fur
type: library
---

# Golden Fur — Claude Code Dev Tooling

An inventory of the AI coding agents and skills set up across the two
repos in this project — the capstone app ([[Architecture|golden-fur]]) and
this vault (`AGENTS.md` at the vault root). Originated from a
suggestions document (now filed at
`Projects/golden-fur/context/Suggested_Agents_Skills.pdf`), grounded
against the actual current implementation rather than taken as-is.

**Important:** everything here is developer tooling. It runs only inside
Claude Code (or another AI coding tool) on a developer's machine, while
writing code — never deployed, never reachable by end users or Mike
Ocsan's staff. Output is ordinary source code that gets reviewed and
committed like any other change.

## Shared pattern (both repos)

Every agent/skill has one canonical, tool-agnostic file plus thin adapters
per tool, so editing the canonical file updates every tool at once:

- **Canonical** — `.agent/agents/<name>.md` or `.agent/skills/<name>.md`.
- **Claude Code** — `.claude/agents/<name>.md` (agent, with `tools:`/
  `model:` frontmatter) or `.claude/skills/<name>/SKILL.md` (skill).
- **Gemini CLI** — `.gemini/commands/<name>.toml`.
- **Codex CLI** — `.codex/prompts/<name>.md`.

Root context files (`AGENTS.md` canonical, `.claude/CLAUDE.md` a one-line
pointer to it) follow the same principle — see `agents-md-maintenance`
below.

## `golden-fur` (capstone app)

Dev-time subagents and reference docs for the app's own business logic —
scaffolding/reviewing/debugging domain code, and specs Claude loads
instead of re-deriving a business rule each session.

**Agents:**

| Agent                       | Covers                                                                                    | Tools                       |
| --------------------------- | ----------------------------------------------------------------------------------------- | --------------------------- |
| `booking-capacity-agent`    | Cage/session/groomer/staff capacity & overbooking prevention (Grooming/Hotel/Daycare/Vet) | full                        |
| `payment-billing-agent`     | PayMongo webhooks, Credit Balance ledger — sandbox only                                   | full                        |
| `auth-access-agent`         | RBAC, TOTP MFA, OAuth account-merge                                                       | read-mostly (no Write/Bash) |
| `report-generator-agent`    | Daily Sales Report & analytics generation                                                 | full                        |
| `notification-agent`        | Transactional notification triggers/templates                                             | full                        |
| `discount-compliance-agent` | Discount Module, incl. Senior/PWD statutory handling                                      | full                        |
| `qa-iso25010-agent`         | Test cases + ISO/IEC 25010 evaluation questionnaire                                       | full                        |
| `db-schema-agent`           | Supabase migrations, multi-branch data isolation                                          | full                        |

**Skills:** `paymongo-webhook-handling`, `capacity-based-scheduling`,
`rbac-totp-setup`, `credit-balance-ledger`, `daily-sales-report-format`,
`email-notification-templates`, `discount-senior-pwd-compliance`,
`iso25010-evaluation-instrument`.

### Where these diverge from the original suggestions doc

The suggestions PDF was written from a proposal-revision read-through, not
the shipped codebase, so a few things were corrected against the real
system (per the [[M01-staff-authentication-access-control|module notes]] in
this Library) rather than copied as-is:

- **8 staff roles**, not 6: Superadmin, Admin, Supervisor, Receptionist,
  Groomer, Veterinarian, Cashier, Pet Assistant.
- **Cage capacity (S/M/L/XL) is a check-in concern, not a pricing
  input** — the four cage-size-tiered services were soft-disabled in favor
  of one flat-rate "Overnight Stay" service; `capacity-based-scheduling`
  documents this explicitly so it doesn't get reintroduced by accident.
- Real, current gaps are called out directly in the skills rather than
  glossed over: checkout-side credit redemption is a stub
  ([[M10-credit-balance-management|M10]]), and the Discount Module is
  inactive by default ([[M12-discount-management|M12]]).

## `golden-fur-vault` (this vault)

Agents/skills for the vault's own job: turning unstructured input into
filed, linked, well-formed notes.

**Agents:** `vault-librarian` (file + promote to Library), `weekly-reviewer`
(7-day rollup), `backlink-curator` (wikilinks + orphan detection,
read-mostly), `research-capture-agent` (cited sources into `Resources/`),
`skill-agent-auditor` (read-only prompt-injection review before adopting a
third-party skill/agent).

**Skills:** `note-filing`, `frontmatter-schema`, `cross-linking`,
`weekly-review-format`, `agents-md-maintenance`, `skill-security-audit`.

## See also

- [[Architecture|Golden Fur — System Architecture]] for the app itself.
- `../../AGENTS.md` (this vault's root) and
  `../../../golden-fur/AGENTS.md` for the full, authoritative listing —
  this note is a curated summary, not the source of truth for either
  repo's actual configuration.

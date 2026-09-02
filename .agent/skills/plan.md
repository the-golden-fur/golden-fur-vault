# Plan (plan-only mode)

**Use when** the user asks to plan without touching code — "just plan", "plan
only", "don't touch code", "no code yet", "plan first", `/plan`. In `golden-fur`
the `session-router` hook detects this phrasing and points here.

**Hard rule: do not edit, create, or delete any code file.** No changes under
`client/`, `server/`, `supabase/`, or anywhere in `golden-fur`. The only file
this skill writes is the plan itself, in the vault. If the user later says to
build it, that's a new, normal request — the plan you wrote becomes that
session's `sessions/NN-<slug>/plan.md`.

## Process

1. **Understand the request against the real code** — read the relevant
   `golden-fur` files, existing `Library/golden-fur/features/<feature>/`
   notes, and any `Reference/golden-fur/` workflow. Reuse what exists; don't
   propose new code where a helper already does the job. The built-in `Plan`
   agent is the right tool for the exploration + design pass.
2. **Reserve the session number.** List
   `../golden-fur-vault/Projects/golden-fur/sessions/` and `sessions/_legacy/{custom,issues}/`, take the highest `NN` + 1
   (currently `63` → `64`). Pick a short kebab-case `slug`.
3. **Write `Projects/golden-fur/sessions/NN-<slug>/plan.md`** using the
   near-beginner template in `.agent/skills/session-documentation.md` —
   audience is a first/second-year CS student who has never seen this
   codebase. Define every term. Name the actual screens and roles. Each
   planned change gets plain words + which files + why.
4. **Stop there.** Tell the user the plan is at
   `Projects/golden-fur/sessions/NN-<slug>/plan.md` and that `NN` is
   reserved for this work. Do not start implementing.

## When implementation later begins

The `session-documenter` agent picks up the existing `sessions/NN-<slug>/plan.md`, fills in `testing/` and `context/`, and extends (does not
rewrite) the plan's "How you'll know it worked" pointer.

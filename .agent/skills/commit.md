# Commit

**Explicit request only.** Run this skill **only when the user directly
asks for a commit** — "commit this", "make a commit for X", `/commit`.
Never invoke it on your own: not as a task wrap-up step, not because a
note looks finished. This skill performs the actual commit; it does not
just print a message to paste.

## Process

1. Look at `git status --short` and `git diff` (staged and unstaged) to
   see what changed, and `git log --oneline -10` to match this repo's
   style.
2. Stage the relevant files. Review what a broad `git add` would pick up
   rather than blindly using `git add -A` — this vault holds a
   sensitive/credential material that may live under
   `Projects/golden-fur/shared/context/`, so double-check nothing sensitive is
   swept in unintentionally.
3. Write the commit message following the format below.
4. Create the commit directly (pass multi-line messages via a heredoc so
   formatting survives), then run `git status` to confirm it succeeded.

> **No verification gates run at commit time** — not `pre-commit-checks`
> (Prettier), not `ci-verifier`. Both are steps of the `pr` skill only,
> run when a PR is actually being opened. Line endings are handled by
> `.gitattributes`, so local formatting no longer churns.

## Message format

- Subject: `<type>(<scope>): <subject>` — imperative mood ("file" not
  "filed"), max 50 characters, no trailing period. Scope is the folder or
  project touched (e.g. `testing`, `inbox`, `reviews`, `golden-fur`).
- Types: `docs`, `fix`, `chore`, `refactor`.
- Body — skip for trivial/self-explanatory changes. Add one when the
  reason isn't obvious from the subject, the note being filed has
  meaningful context worth surfacing, or a correction needs to describe
  what was wrong. WHAT + WHY only; one blank line after the subject; wrap
  at 72 chars; prose, not bullets.
- Footer — one blank line after the body: related-request refs
  (`Relates-to golden-fur#42`).

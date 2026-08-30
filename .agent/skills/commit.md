# Commit

**Use whenever** asked to commit changes in this vault — "commit this",
"make a commit for X". This skill performs the actual commit; it does not
just print a message to paste. Only commit when explicitly asked.

## Process

1. **Run `.agent/skills/pre-commit-checks.md` first** — Prettier format,
   fix then check. Resolve or surface anything it flags before moving on;
   don't skip straight to staging.
2. **Verify CI parity across both repos** — spawn the `ci-verifier`
   subagent (`.agent/agents/ci-verifier.md`, canonical file in
   `../golden-fur`). It runs the `✅ CI: Verify All` task here (Prettier
   `format:check`) and in `golden-fur` (tests, lint, format, build) and
   reports one pass/fail; everything must be green before committing. It
   skips a repo that is clean and already pushed, so vault-only work
   won't drag golden-fur's full suite along. A green pass from earlier
   this session with nothing changed since counts.
3. Look at `git status --short` and `git diff` (staged and unstaged) to
   see what changed, and `git log --oneline -10` to match this repo's
   style.
4. Stage the relevant files. Review what a broad `git add` would pick up
   rather than blindly using `git add -A` — this vault holds a
   `Credentials.docx` and other sensitive material under
   `Projects/golden-fur/context/`, so double-check nothing sensitive is
   swept in unintentionally.
5. Write the commit message following the format below.
6. Create the commit directly (pass multi-line messages via a heredoc so
   formatting survives), then run `git status` to confirm it succeeded.

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

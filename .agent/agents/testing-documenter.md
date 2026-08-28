# testing-documenter

**Role:** writes the verification record described in
`.agent/skills/testing-documentation.md` for a change just made to the
`golden-fur` code repo — by reading what actually changed (git diff/log,
migration files, the tests that were actually run), not by summarizing from
memory or from a request description alone.

**Scope — like `workflow-documenter`, a deliberate exception in this vault's
agent set:** every other vault agent reads/writes only within this repo.
This one is different on purpose, because a testing doc that isn't grounded
in the real diff is just a restatement of the request, not a verification
record:

- **Reads** `../golden-fur` (the code repo) freely — `git diff`/`git log`
  against the base branch, changed source files, new/changed
  `supabase/migrations/*.sql`, and actually runs the test suites
  (`npm run test`, `npx tsc --noEmit` / `npx tsc -b`) to get real pass/fail
  counts rather than assuming green.
- **Never writes** to `../golden-fur`. All output is written only within
  this vault, under `Projects/golden-fur/testing/<issues|custom>/NN-<slug>/`.

**Use whenever** a change to the `golden-fur` repo — bug fix, feature,
migration, architecture change — was just implemented in response to a
specific request, and needs its testing doc written or an existing one
updated. This is expected to run as the closing step of that implementation
work, not as a separately-requested follow-up.

Follow `.agent/skills/testing-documentation.md` for the full template, file
set (`.md` always, `.postman_collection.json` if API behavior changed,
`.sql` if a migration was added), and numbering rules.

## Process

1. **Establish what actually changed.** `git status`/`git diff` (and
   `git log` if commits already exist) in `golden-fur` — do not rely on the
   conversation's own summary of the change alone; verify against the real
   diff, the same grounding discipline `workflow-documenter` applies to
   workflow docs.
2. **Classify custom vs. issue.** Does this close a numbered GitHub issue?
   Use `testing/issues/NN-slug/` with that issue's number. Otherwise
   `testing/custom/NN-slug/`, `NN` = next integer after the current highest
   in that directory (list it — never guess).
3. **Run the actual test suites** (`server`: `npm run test`,
   `npx tsc --noEmit`; `client`: `npm run test`, `npx tsc -b`) if they
   weren't already run and confirmed green earlier in the same session — the
   doc's "Test suites" section must report real numbers you just observed,
   not an assumption.
4. **Write `<slug>.md`** per the template — title, branch, the request
   verbatim (or as close as available), root cause/context, what changed
   (grouped by database/server/client, only the sections that apply),
   numbered manual verification steps, test suite results, and any open
   items deliberately deferred.
5. **Write `<slug>.postman_collection.json`** if any API route's behavior
   (new endpoint, changed validation, changed response shape) is part of
   this change — numbered requests run top-to-bottom, a login request that
   captures a token, `test` scripts asserting the specific behavior this
   change is about.
6. **Write `<slug>.sql`** if a new migration file was added — a reference
   copy of the migration(s), headed by a comment naming the real
   `golden-fur/supabase/migrations/...` path(s) as source of truth.
7. **When updating an existing testing doc** (a follow-up change to
   something already documented): add to or correct the existing folder
   rather than creating a duplicate NN for the same underlying change,
   unless the follow-up is itself a distinct, separately-requested piece of
   work (in which case it gets its own NN, cross-referenced in prose).

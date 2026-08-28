# Testing documentation

**Purpose:** capture a verification record — for a human to manually retest,
and for Postman/SQL artifacts to exist — for every code change made to the
`golden-fur` app repo, whether it came from a numbered GitHub issue or an
ad-hoc/custom request. This replaces the old in-repo `golden-fur/testing/docs/`
convention (removed by `Projects/golden-fur/testing/custom/53-remove-testing-docs/`)
— the docs now live only in this vault.

**Use whenever** you (or another AI coding tool) finish implementing a change
in the `golden-fur` repo — a bug fix, a feature, a schema migration, an
architecture change — in response to a specific request (chat message, issue,
backlog item). Write the doc as part of finishing that piece of work, not as
a separate follow-up someone has to remember to ask for.

**Skip it** for pure documentation/vault-only changes (nothing changed in
`golden-fur`), and for trivial non-functional edits (typo fixes, comment
wording, formatting-only diffs) that have nothing a human would ever need to
manually re-verify.

## Where it goes

`Projects/golden-fur/testing/<issues|custom>/NN-<slug>/`

- **`issues/`** — the change closes or implements one or more numbered
  GitHub issues (e.g. `#88`). `NN` is the issue number itself (or the first
  issue number, for a batch — see `25-policy-fees-and-credit-balances`
  covering `#88`-`#95`).
- **`custom/`** — everything else: a chat-message bug report, an ad-hoc
  feature request, an advisor/client note, anything without a GitHub issue
  number. `NN` is the **next sequential integer** across the whole `custom/`
  folder (check the highest existing `NN-*` directory first — do not reuse
  or guess; list the directory).
- `slug` is a short kebab-case summary of the change, e.g.
  `downpayment-per-transaction-policy`.

One folder per cohesive change/PR — matches this repo's "one PR per cohesive
feature" convention (see `41-fix-service-downpayment-toggle`'s "Scope note"
for how to split a bundled request into separate docs/passes instead of
cramming unrelated work into one).

## Files inside the folder

- **`<slug>.md`** — always required. See template below.
- **`<slug>.postman_collection.json`** — only if the change touches an API
  route (new endpoint, changed request/response shape, new validation
  branch). Skip for pure UI/client-only or schema-only changes with no new
  observable API behavior.
- **`<slug>.sql`** — only if the change adds/alters a database migration.
  This is a **reference copy** of the actual migration file(s) already
  committed under `golden-fur/supabase/migrations/`, prefixed with a header
  comment naming the source-of-truth path(s) — not a separate seed/fixture
  script. See `34-downpayment-and-transaction-history.sql`'s header for the
  exact convention.

## `<slug>.md` template

```markdown
# <Short title, plain language — what changed or what was fixed>

Branch: `<branch-name>` (or "not yet created — staged directly on `dev`" if
none exists yet)

## The request, verbatim

> <the original ask, quoted as closely to verbatim as you have it — a chat
> message, an issue body, an advisor note. If it was bundled with unrelated
> asks, add a "Scope note" explaining what was split out and why, mirroring
> `41-fix-service-downpayment-toggle`.>

## Root cause / Context

<For a bug fix: what was actually wrong and why. For a feature/architecture
change: what existed before, why it's changing, and any history worth
recording — a prior design this supersedes, a prior decision now reversed.>

## What changed

### Database (only if migrations were added)

<List the new migration file(s), one line each with a short parenthetical of
what it does.>

### Server

<File-by-file, what changed and why — not a full diff, the reasoning a
reviewer would want.>

### Client

<Same, for client-side files.>

## Verification

<Numbered manual steps a human can actually follow: which page/role, what to
click, what to expect. Reference the Postman collection (if one exists) for
API-level checks instead of restating every request in prose.>

## Test suites

<Exact pass/fail counts from actually running them — server and client
separately, e.g. "`server`: `npm run test` — 887/887 passing (85 files),
`npx tsc --noEmit` clean." Never state a count you did not personally just
run.>

## Open items (only if any)

<Anything deliberately deferred or flagged, same convention as
`25-policy-fees-and-credit-balances`'s "Open Items".>
```

Trim sections that don't apply (e.g. no "Database" subsection if there's no
migration) rather than leaving them empty.

## `.postman_collection.json` conventions

Follow `41-fix-service-downpayment-toggle`'s collection as the template:

- Postman Collection v2.1.0 schema, `info.name` includes the issue/change
  number in parentheses if one exists.
- `variable[]` at the collection level for `base_url` plus every credential/
  id the requests need (left blank for the user to fill in, except
  `base_url` which defaults to `http://localhost:3000`).
- Numbered request names (`"1. Login as Admin"`, `"2. ..."`) meant to be run
  top-to-bottom in order.
- A `test` script on each request asserting status code and the specific
  field(s) this change is actually about — not a generic "200 OK" check.
- A login request that captures the access token into a collection variable
  for reuse by subsequent requests.
- Where relevant, include both the "before the fix" failing payload (to
  prove the bug existed / is now handled) and the "after the fix" succeeding
  payload — see request 3 vs. request 4 in the `#41` example.

## Numbering discipline

Before writing anything, actually list the target directory
(`Projects/golden-fur/testing/custom/` or `.../issues/`) to find the true
highest `NN` — don't assume a number from memory or from what a planning doc
says (see `25-policy-fees-and-credit-balances`'s "Migration numbering had
drifted a second time" note for what happens when this isn't re-checked).

## Cross-linking

No wikilinks are required into/out of these folders by default — they're
working/testing material, not `Library/` notes. If a testing doc is directly
relevant to a `Library/golden-fur/workflows/` or `modules/` note you're also
updating in the same pass, a one-line pointer is fine but optional.

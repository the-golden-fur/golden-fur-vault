# Update README to match grading rubric, add docs/setup.md and docs/architecture.md

Custom request (not tied to an epic/issue). No dedicated branch — a
documentation-only change made directly per request, verified from
`temp/context/`.

## What changed

### 1. `README.md` rewritten

The previous file was a single line (`# golden-fur`). Rebuilt it against the
"Requirements ZIP File" section of `temp/context/Rubrics.docx` (extracted to
text since it's a binary `.docx` — see verification below), which requires
the README to contain: **Project title, Description, System requirements,
Installation steps, How to run the program, Team members**. All six are
present, plus a Tech Stack summary and a Documentation section linking out to
the two new docs files and the existing `docs/privacy-policy.html`.

Team members were pulled from `git shortlog -sne --all` and deduplicated by
email (some contributors have two GitHub handles on record under the same
address):

- `cH0NKIIs34L` / `ChonkySeal` → listed once as `cH0NKIIs34L` (current
  handle, per this session's git config)
- `akazuuu` / `James Terel Saluta` → listed as `akazuuuu` (actual GitHub
  login, per the `users.noreply.github.com` commit address)
- `rie755`
- `alarieblobs`

### 2. `docs/setup.md` added (new)

Guided, numbered walkthrough for someone with no prior Node/Supabase
experience: installing prerequisites, cloning, `npm run install:all`,
creating a Supabase project from scratch and locating the API keys, filling
in both `.env` files, pushing migrations, seeding sample data, running the
dev servers, running tests, and a troubleshooting section for the errors
most likely to come up (bad env values, CORS, `supabase link` failures,
out-of-sync migration history).

### 3. `docs/architecture.md` added (new)

Describes the three-workspace layout (`client/` / `server/` / `supabase/`),
the client/server feature-folder pattern (mirrored `features/<name>/` on
both sides), the Supabase folder layout, the branch/role/service domain
model, and a module map (M01–M14) marking which modules already have a
feature folder (implemented) versus not yet built (planned). Module→feature
mapping was verified against actual folder contents, not assumed:

| Module | Feature folder  | Confirmed via                                                                                                         |
| ------ | --------------- | --------------------------------------------------------------------------------------------------------------------- |
| M01    | `auth`, `staff` | folder contents                                                                                                       |
| M02    | `customers`     | folder contents                                                                                                       |
| M03    | `booking`       | folder contents + commit `2703e26` (`feat(booking): add booking core backend (M03 Epic B)`)                           |
| M12    | `discounts`     | `AdminDiscountManagementPage` under `client/src/features/discounts/pages/`                                            |
| M13    | `maintenance`   | `AdminServicesPage`, `AdminPackageBuilderPage`, `AdminPromoConfigPage` under `client/src/features/maintenance/pages/` |

An earlier draft of `docs/architecture.md` pointed to
`temp/context/source.txt` as the source of the full module spec — removed
before finalizing, since `temp/` is git-ignored (`.gitignore:1`) and that
path would 404 for anyone else who clones the repo.

## Verification performed

- Extracted `temp/context/Rubrics.docx` (a zipped Office XML file — the
  `Read` tool can't open binary `.docx` directly) via `unzip` +
  `word/document.xml`, then stripped XML tags with a small Node script to
  confirm the exact required README sections before writing anything.
- Cross-checked every factual claim in the new docs against the repo itself
  rather than assumption: `package.json` scripts (root/client/server),
  `client/.env.example` / `server/.env.example` for env var names,
  `supabase/config.toml` for ports and Postgres version,
  `.github/workflows/ci.yml` for the exact CI commands, and
  `client/src/features/*` / `server/src/features/*` folder listings for the
  module map.
- `git shortlog -sne --all` to source the Team Members list, cross-checked
  against `git log --format='%an|%ae'` to catch same-person/different-handle
  cases before deduplicating.
- `npx prettier --write README.md docs/setup.md docs/architecture.md` — all
  three pass `npm run format:check` (fixed one markdown table alignment
  warning in the README's Tech Stack table).
- Confirmed no other `docs/*.md` files existed yet to link to or conflict
  with (`docs/` previously only had `privacy-policy.html`).

## How to verify yourself

1. Open `README.md` at the repo root (in GitHub's file view or a Markdown
   preview) and confirm it renders cleanly with these sections, in this
   order: Golden Fur (title) → Description → Tech Stack table → System
   Requirements → Installation → How to Run the Program → Documentation →
   Team Members → License.
2. Click each link under **Documentation** in the rendered README —
   `docs/setup.md`, `docs/architecture.md`, `docs/privacy-policy.html` —
   and confirm each resolves (no 404s) and each doc's internal links back
   (e.g. `architecture.md`'s CI section link to
   `setup.md#8-run-the-tests`) land on the right heading.
3. Run `npm run format:check` from the repo root — should pass with no
   warnings for `README.md`, `docs/setup.md`, or `docs/architecture.md`.
4. Skim `docs/setup.md` end-to-end as if you'd never touched this repo
   before: does it tell you what to click/type at every step, with no
   assumed knowledge of Supabase's dashboard or the Supabase CLI? (Optional:
   actually follow it start to finish against a scratch Supabase project to
   confirm every command in it is correct.)
5. Compare the **Module map** table in `docs/architecture.md` against
   `client/src/features/` and `server/src/features/` — every folder listed
   there should be marked "Implemented," and no folder that exists should be
   missing from the table.
6. Re-open `temp/context/Rubrics.docx` yourself (Word/Google Docs) and check
   the "Requirements ZIP File" section — confirm the six bullet points
   listed there (Project title, Description, System requirements,
   Installation steps, How to run the program, Team members) are all
   present in `README.md`.

No testable API routes or DB objects were touched by this change, so no
Postman/SQL files accompany this doc.

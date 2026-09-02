# research-capture-agent

**Role:** files literature, interview, and other cited research material
(e.g. GoldenFur capstone related-literature excerpts, adviser feedback,
interview transcripts) into `Projects/golden-fur/shared/research/` with
proper citation metadata — distinct from `note-filing`'s default handling of
raw working notes into `Inbox/`/`Projects/`.

**Scope:** only reads/writes paths within this repo (the vault). Never edit
files in the sibling `../golden-fur` code repo.

**Use whenever** asked to save a source, paper, article, dataset, or
interview for research/citation purposes — anything that will need to be
cited later, not just a working note.

## Process

1. **Frontmatter** — the standard fields from `.agent/skills/frontmatter-schema.md`
   (`title`, `date`, `tags`, `project`) plus:
   - `type: resource`
   - `source` — a URL, DOI, book/paper title, or `interview: <name>, <date>`.
     Required; this is the field that makes the note citable later.
2. **Destination** — `Projects/golden-fur/shared/research/<topic-subfolder>/`,
   e.g. `.../research/related-literature/`, `.../research/interviews/`. Use
   the closest existing topic subfolder; only create a new one if nothing
   fits.
3. **Content** — keep the source's substantive claims/quotes, clearly
   attributed (quote vs. paraphrase), with a short "why this matters to
   GoldenFur" summary at the top so it's useful without re-reading the
   original.
4. **Cross-link** to any capstone chapter, decision, or proposal note this
   source supports, per `.agent/skills/cross-linking.md`.
5. **Never overwrite** an existing resource note — append or create a new
   dated file instead. **Never write directly into `Library/`** — promotion
   there is `vault-librarian`'s separate, deliberate job.

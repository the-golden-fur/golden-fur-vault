# Note filing

**Purpose:** file raw, unstructured input (pasted text, voice transcripts,
quick captures) into this vault with proper frontmatter and the right
destination folder.

**Use this whenever** asked to save, file, or log a note, transcript, or
capture — as opposed to acting on it as a code change.

## Process

1. **Add YAML frontmatter** to the note:

   ```yaml
   ---
   title: <short title>
   date: <YYYY-MM-DD>
   tags: [...]
   project: golden-fur
   ---
   ```

2. **Pick the destination folder**:
   - Default to `Inbox/` if the right place isn't obvious.
   - Otherwise file under `Projects/golden-fur/`, which has exactly two
     subtrees:
     - `shared/` — project-wide material not tied to one session:
       `shared/context/` (briefs, roadmaps, architecture docs),
       `shared/decisions/` (ADRs / "why we did X", `YYYY-MM-DD-slug.md`),
       `shared/design/` (mockups), `shared/research/` (cited sources — but
       prefer `research-capture-agent` for those).
     - `sessions/` — the per-AI-session record. Don't hand-file here; the
       `session-documenter` agent owns each `sessions/NN-<slug>/` folder.
   - **Never write directly into `Library/golden-fur/`** (curated prose,
     feature-grouped) **or `Reference/golden-fur/`** (machine-readable
     workflow files — `workflow-documenter`'s output only). Raw/unstructured
     input only goes to `Inbox/` or `Projects/golden-fur/shared/`. Promotion
     to `Library/` is a separate, deliberate cleanup step (see
     `.agent/agents/vault-librarian.md`) — never automatic.

3. **Cross-link related notes.** Skim filenames/topics in the destination
   folder for anything obviously related and add a short "See also" link —
   see `.agent/skills/cross-linking.md` for the full when/how rules.

4. **Never overwrite an existing note.** If a matching dated file already
   exists, append a new section to it instead. Otherwise create a new file
   named `YYYY-MM-DD-short-slug.md`.

5. **Clean up after yourself.** Remove any temp/scratch files created while
   processing the note (anything the vault's `.gitignore` would match —
   `.tmp/`, `_staging/`, `_extract/`, `*.tmp`, `*.part`) before finishing.

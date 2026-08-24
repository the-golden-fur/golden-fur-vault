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
   - Otherwise file under `Projects/golden-fur/`:
     - `testing/` — test logs, QA notes, verification results not already
       covered by the `implement-issue`/`implement-custom` workflow output.
     - `docs/` — working docs, meeting notes, drafts.
     - `decisions/` — ADRs / "why we did X" notes.
   - **Never write directly into `Library/golden-fur/`.** Raw/unstructured
     input only goes to `Inbox/` or `Projects/`. Promotion to `Library/` is a
     separate, deliberate cleanup step (see `.agent/agents/vault-librarian.md`)
     — never automatic.

3. **Cross-link related notes.** Skim filenames/topics in the destination
   folder for anything obviously related and add a short "See also" link.

4. **Never overwrite an existing note.** If a matching dated file already
   exists, append a new section to it instead. Otherwise create a new file
   named `YYYY-MM-DD-short-slug.md`.

5. **Clean up after yourself.** Remove any temp/scratch files created while
   processing the note (anything the vault's `.gitignore` would match —
   `.tmp/`, `_staging/`, `_extract/`, `*.tmp`, `*.part`) before finishing.

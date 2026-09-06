# Cross-linking

**Purpose:** rules for when and how to add `[[wikilinks]]` between related
notes — applied inline during filing (`note-filing`, `vault-librarian`) and
whenever linking up or reviewing existing notes.

## When to link

- Link when a note mentions a concept, decision, module, or person that has
  its own note elsewhere in the vault — not for every incidental word
  match.
- Prefer linking to the most specific existing note over a broader one (a
  named decision note over a general project-docs note, say).
- A short "See also" list at the end of a note is fine when a natural
  inline link doesn't fit the prose; don't force an inline link into an
  awkward sentence just to have one.

## How to link

- Use the target note's `title` frontmatter field (or filename) as the
  link text: `[[exact-title-or-filename]]`, or
  `[[filename|display text]]` if the display text should read differently
  from the title.
- Only link to notes that actually exist — never link to a note you
  haven't verified is there. An unverified link produces an Obsidian
  "unresolved link," which defeats the purpose.
- Links only need to be added in one direction — Obsidian back-resolves
  them automatically. Don't hand-maintain a reverse link list on the
  target note.

## Orphan notes

A note with zero outgoing links and zero notes linking to it is an orphan.
When filing a single note (`note-filing`), a quick skim of the destination
folder for one obviously related note is enough — don't turn every filing
action into an exhaustive vault-wide orphan hunt. Run a broader sweep only
when explicitly asked to link up or review a batch of notes.

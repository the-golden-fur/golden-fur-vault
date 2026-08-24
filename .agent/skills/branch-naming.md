# Branch naming & creation

**Use whenever** starting new work in this vault: filing/reorganizing notes
that warrant their own branch, or "start a branch for X". This repo has a
single `main` branch — no `dev`.

## Process

1. Determine the branch type from the change description (table below).
2. Generate a name: `<type>/<short-description>` — lowercase, hyphens only,
   no spaces/underscores/extra slashes, 2–5 words, specific enough to
   identify the work at a glance.
3. Run the branch creation directly:
   ```
   git checkout main
   git pull origin main
   git checkout -b <type>/<short-description>
   git push -u origin <type>/<short-description>
   ```

## Types

| Type        | When to use                                        |
| ----------- | -------------------------------------------------- |
| `docs/`     | Filing, writing, or editing notes/docs             |
| `fix/`      | Correcting a mistake in an existing note           |
| `chore/`    | Reorganizing folders, cleaning up, housekeeping    |
| `refactor/` | Restructuring notes without changing their content |

## Examples

- `docs/sprint7-retro-notes`
- `chore/reorganize-inbox`
- `fix/wrong-date-reset-seed-doc`
- `refactor/split-weekly-review`

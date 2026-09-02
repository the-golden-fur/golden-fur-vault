# Add git add commands to commit-pr prompt

Custom request (not tied to an epic/issue). No dedicated branch — edited
directly on `dev` since this only touches a prompt template file, not
application code.

## What changed

`prompts/workflow/commit-pr.md` previously only asked Claude to produce
commit messages and a per-commit directory structure, leaving staging
(`git add`) as a manual step. Added one line to `process:` and updated the
`output:` bullet so that, for every commit it proposes, Claude now also
outputs the `git add` command(s) for that commit's files, placed directly
under that commit's directory-structure block — so the listed files can be
staged by copy-pasting the command instead of adding them by hand one at a
time.

No application code, API routes, or DB objects are involved, so no
Postman/SQL files accompany this doc.

## How to verify yourself

1. Open [prompts/workflow/commit-pr.md](../../../prompts/workflow/commit-pr.md)
   and confirm it now reads:
   - Under `process:` — a bullet saying to add `git add` commands for each
     commit's files directly under its directory structure block.
   - Under `output:` — the commit-messages bullet now mentions `git add`
     commands alongside the directory structure.
2. Functional check — run the updated prompt against a real set of staged
   changes:
   1. Make a couple of unrelated edits in a scratch file or two (or use any
      changes you already have pending).
   2. Feed `prompts/workflow/commit-pr.md` to Claude along with those
      changes, the same way you normally invoke this workflow.
   3. Confirm the response includes, for each proposed commit: the commit
      message, the directory structure block, and immediately under it a
      `git add <path> <path> ...` (or multiple `git add` lines) command
      listing exactly the files shown as added/modified in that commit's
      directory structure.
   4. Copy-paste the `git add` command(s) into your terminal and run
      `git status` — the files listed should now show as staged, with no
      manual `git add` needed.

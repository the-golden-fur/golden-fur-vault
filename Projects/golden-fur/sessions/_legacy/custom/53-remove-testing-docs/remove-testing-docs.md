# Remove testing/docs from golden-fur

Custom request (not tied to an epic/issue). No dedicated branch yet at the
time of writing — staged directly on `dev`; this only removes files, no
application code is involved.

## What changed

`golden-fur/testing/docs/` (the `custom/` and `issues/` subfolders — 288
files, ~55.5k lines) is deleted from the `golden-fur` repo. Every file was
already copied into this vault beforehand, under
[`Projects/golden-fur/testing/custom/`](../../testing/custom/) and
[`Projects/golden-fur/testing/issues/`](../../testing/issues/), preserving
the original `NN-summary/` folder structure. `golden-fur`'s
`prompts/workflow/implement-issue.md`, `implement-custom.md`, and
`implement-multiple.md` were updated (and later removed entirely — see
[52-discount-builder-settings-modal](../52-discount-builder-settings-modal/)
for the last entry written by the old prompts, and this vault's own
`prompts/workflow/document-changes.md` for the prompt that replaced them)
to stop writing to the old in-repo path.

No API routes or DB objects are involved, so no Postman/SQL files
accompany this doc.

## How to verify yourself

1. In `golden-fur`, confirm `testing/docs/` no longer exists:
   ```powershell
   Test-Path testing\docs
   ```
   Should print `False`.
2. In this vault, confirm the content landed intact:
   ```powershell
   (Get-ChildItem Projects\golden-fur\testing\custom -Directory).Count
   (Get-ChildItem Projects\golden-fur\testing\issues -Directory).Count
   ```
   Should show 52 custom-request folders and 90 issue folders.
3. Spot-check a couple of files against the deleted originals (e.g. via
   `git show HEAD:testing/docs/custom/01-fix-mfa/fix-mfa.md` in `golden-fur`
   before this commit lands) to confirm content wasn't altered in transit.

# Context — 70-server-build-step-and-dist-clean

## Copied into ./context/

None. This session didn't use any pasted briefs, docs, or transcripts.

## Referenced only (not copied)

- Four screenshots pasted inline in the chat (Render "Build" settings page,
  Vercel "Build and Development Settings" and "Framework Settings" pages) —
  images attached directly to a chat message, not files on disk, so there
  was nothing to copy. They showed: Render `golden-fur-server` Root
  Directory `server` / Build Command `npm install`; Vercel `golden-fur-client`
  Root Directory `client`; Vercel Framework Settings showing Vite defaults
  (Build Command / Output Directory `dist` left un-overridden). Used to
  confirm the live dashboard state matched `render.yaml` and
  `client/vercel.json` before proposing any change.
- `golden-fur/server/.env` — used locally to boot the compiled server for
  the `/health` check in `testing/testing.md`; a secrets file, never copied.

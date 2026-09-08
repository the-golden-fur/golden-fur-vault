# Context — 77-resend-to-brevo-email

## Copied into ./context/

- `Golden-Fur-Brevo-Setup-Guide.md` — the step-by-step brief for this session
  (Brevo dashboard setup + repo wiring). Plain-text transcription of
  `Inbox/Golden-Fur-Brevo-Setup-Guide.docx`, which was deleted from `Inbox/`
  as part of the request. Note: its Part B "Step 3" client snippet targets the
  **old** `@getbrevo/brevo` API (`TransactionalEmailsApi` /
  `SendSmtpEmail`); the installed SDK is v6 with a different shape, so
  `brevo.client.ts` was written against v6 instead.

## Referenced only (not copied)

- `Projects/golden-fur/shared/context/Architectural-Change-History.docx` —
  the canonical architectural-change backlog. "Change Resend to Brevo in
  code" is the High-Priority item this session actioned. An identical copy
  had been dropped at `Inbox/Architectural-Change-History.docx`; both the
  Inbox copy and (separately) this canonical one existed — only the Inbox
  copy was removed by this task.
- `golden-fur/server/.env` — holds the real dev `BREVO_API_KEY` and
  `BREVO_FROM_EMAIL`. Git-ignored, a secrets file — never copied. The staff
  test-login values in `testing/testing.md` (`makati.admin1@goldenfur.com` /
  `password123`) come from `supabase/seeds/m01-staff-auth/`.
- `Inbox/brevo-api-keys.txt` — one-line dev API key drop; consumed into
  `server/.env`, then deleted. A secret, never copied.
- `golden-fur/supabase/migrations/20260908181…`, `…20260908182…` — the two
  migrations added this session; reference copies are in
  `../testing/77-resend-to-brevo-email.sql`.

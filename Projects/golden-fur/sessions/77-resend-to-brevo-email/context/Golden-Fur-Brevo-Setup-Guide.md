> **Provenance:** transcribed from `Inbox/Golden-Fur-Brevo-Setup-Guide.docx`
> (plain-text extraction), which was the step-by-step brief for this session.
> The original .docx was removed from `Inbox/` as part of this task; this
> markdown is the retained copy. Formatting is approximate.

Golden Fur
Setting Up Brevo for Transactional Email
A beginner-friendly, step-by-step walkthrough — Brevo dashboard + the golden-fur repo 0. Overview — what we're doing and why
Brevo (formerly Sendinblue) is the email service that will send the Golden Fur system's transactional emails: staff account credentials, password resets, appointment confirmations, payment confirmations, and appointment reminders.
This guide has two parts:
Part A — Brevo website: verify a sender, generate an API key, and check your sending limits.
Part B — Local repo: install the Brevo SDK, add environment variables, create the email client, and wire it into the existing email code.
Heads up — the repo currently uses Resend, not Brevo.
Right now, server/src/shared/email/resend.client.ts is what actually sends email (via the Resend API). Nothing in the codebase talks to Brevo yet. This guide adds a Brevo client and swaps it in, so read Part B carefully even if you're comfortable with the website part.

Part A — Configure Brevo on the website
You're already logged into app.brevo.com under the "The Golden Fur" organization, on the Home page. Everything below happens inside this same dashboard — you don't need to create a new account.
Step 1: Open Settings
In the top-right corner of the page, find the small gear/cog icon (it sits between the bell/notification icon and the "The Golden Fur" organization name). Click it.
This opens your account and organization settings — this is where API keys and sender identities live.
Step 2: Verify a sender email (do this first)
Before Brevo will let you send real email, you must prove you own the address you're sending "from" (e.g. noreply@goldenfur.com, or a Gmail address if you're just testing).
In Settings, look in the left-hand settings menu for "Senders, Domains & Dedicated IPs" (sometimes shown simply as "Senders & IP"). Click it, then open the "Senders" tab.
Click "Add a sender", fill in:
Sender name — e.g. "Golden Fur" (this is the display name recipients see)
From email — the address you'll send from, e.g. noreply@goldenfur.com
Brevo emails that address a verification link — open that inbox and click the link. The sender now shows a green "verified" badge in the Senders list.
Recommended for production
If Golden Fur owns a real domain (e.g. goldenfur.com), verify the whole domain instead of a single address ("Domains" tab → "Add a domain" → add the DNS records Brevo gives you at your domain registrar). This improves deliverability (fewer emails land in spam) and lets you send from any address @that domain. For local development/testing, a single verified sender address is enough.
Step 3: Generate an API key
Still inside Settings, find "SMTP & API" in the left-hand menu and click it.
Open the "API Keys" tab (this is separate from the "SMTP" tab — we want the API key, not SMTP credentials, since the code in this repo talks to Brevo's HTTP API).
Click "Generate a new API key", give it a name such as goldenfur-server-dev, and click Generate.
Brevo shows the key exactly once. Copy it immediately and paste it somewhere safe (e.g. a password manager) — you'll paste it into the repo's .env file in Part B.
Step 4: Check your sending limits
Back on the Home page, scroll to the "Your plan usage" card. It shows something like "300 left out of 300 until 25/08/2026" — this is your daily email quota on the free plan.
300 emails/day is plenty for development and a small pilot, but keep an eye on this once the system goes live with real customers across two branches. If you outgrow it, "Upgrade now" (top-right) unlocks higher limits.

That's everything needed on the Brevo website: a verified sender and an API key. Keep this browser tab open — you'll want the API key value in the next part.
Part B — Configure the golden-fur repo locally
Now switch to your code editor / terminal, with the golden-fur repo open.
Step 1: Install the official Brevo SDK
In a terminal, from the server/ folder, run:
cd server
npm install @getbrevo/brevo
This adds Brevo's Node.js client library, the same way "resend" is currently installed for the Resend integration.
Step 2: Add the Brevo environment variables
Open server/.env.example and add a new section, mirroring the existing "Resend" section:

# --- Brevo (transactional email) ---

# Found in Brevo Dashboard -> Settings (gear icon) -> SMTP & API -> API Keys.

BREVO_API_KEY=your_brevo_api_key

# Must be a verified sender in Brevo (Settings -> Senders, Domains &

# Dedicated IPs -> Senders). Format: "Display Name <address@domain.com>".

BREVO_FROM_EMAIL=Golden Fur <noreply@goldenfur.com>
Then copy the same two lines into your real server/.env file, replacing the placeholder with the actual API key you copied from Brevo, and a sender address you've verified.
Never commit real keys
server/.env is already git-ignored — only server/.env.example (with placeholder values) should ever be committed. Double-check server/.gitignore includes .env before pushing.
Step 3: Create the Brevo client wrapper
Create a new file, server/src/shared/email/brevo.client.ts. This mirrors resend.client.ts's structure exactly (same cached-singleton pattern, same exported sendEmail(to, subject, html) shape), so the rest of the codebase barely needs to change:
import * as brevo from '@getbrevo/brevo';

let cachedClient: brevo.TransactionalEmailsApi | null = null;

/**

- Lazily-constructed singleton over the Brevo SDK — mirrors
- resend.client.ts's pattern of reading process.env inside the
- function, not at module-load time.
  */
  function getClient(): brevo.TransactionalEmailsApi {
  if (cachedClient) {
  return cachedClient;
  }

const apiKey = process.env.BREVO_API_KEY;

if (!apiKey) {
throw new Error('BREVO_API_KEY is not configured');
}

const client = new brevo.TransactionalEmailsApi();
client.setApiKey(brevo.TransactionalEmailsApiApiKeys.apiKey, apiKey);

cachedClient = client;
return cachedClient;
}

export interface SendEmailParams {
to: string;
subject: string;
html: string;
}

/**

- Golden Fur's transactional-email provider (Brevo, brevo.com).
- Replaces resend.client.ts as the one send path shared by every
- caller: account_created, password reset, appointment
- confirmation, payment confirmation, and appointment reminders.
  _/
  export async function sendEmail({
  to,
  subject,
  html,
  }: SendEmailParams): Promise<void> {
  const fromHeader =
  process.env.BREVO_FROM_EMAIL ?? 'Golden Fur <noreply@goldenfur.com>';
  const match = fromHeader.match(/^(._)<(.+)>$/);
  const senderName = match ? match[1].trim() : undefined;
  const senderEmail = match ? match[2].trim() : fromHeader.trim();

const email = new brevo.SendSmtpEmail();
email.sender = { name: senderName, email: senderEmail };
email.to = [{ email: to }];
email.subject = subject;
email.htmlContent = html;

try {
await getClient().sendTransacEmail(email);
} catch (error) {
const message = error instanceof Error ? error.message : 'Unknown error';
throw new Error(`Failed to send email via Brevo: ${message}`);
}
}
Step 4: Point the email templates at the new client
Every file that currently does the following:
import { sendEmail } from './resend.client.ts';
needs to import from the new file instead:
import { sendEmail } from './brevo.client.ts';
As of this repo's current state, that's server/src/shared/email/accountCreatedEmail.ts. Search the codebase for any other importers before you finish (the proposal calls for five email types in total — password reset, appointment confirmation, payment confirmation, and appointment reminders may live in files added after this guide was written):
grep -rl "resend.client" server/src
Update every match the same way. Because brevo.client.ts exports the same sendEmail({ to, subject, html }) shape as resend.client.ts, you only need to change the import line — no other code in those files should need to change.
Step 5: Retire the Resend configuration (optional but recommended)
Once every caller has moved to Brevo, keep things tidy:
Remove the "Resend" section from server/.env.example and server/.env.
Run npm uninstall resend from server/ if nothing else references it.
Delete server/src/shared/email/resend.client.ts once you've confirmed nothing imports it (repeat the grep from Step 4 — it should return nothing).
If you'd rather keep Resend around as a fallback for now, that's fine too — just make sure BREVO_API_KEY and BREVO_FROM_EMAIL are the ones actually referenced by whichever client file is imported.
Step 6: Test the integration locally
With the server running (npm run dev from server/), trigger any flow that sends email — the simplest is creating a new staff account, which calls sendAccountCreatedEmail() on success.
Check two places:
The terminal running your server — a thrown "Failed to send email via Brevo: ..." error means the API key, sender, or payload needs a fix.
Brevo's dashboard: left sidebar → Transactional (or Statistics, depending on your plan's menu) → Email Activity / Logs. A successful send shows up there within a few seconds, with its delivery status.
If the send succeeds, the recipient inbox (the one you used as "to") receives the email within a minute or so — check spam/junk the first few times, especially if you verified only a single sender address rather than a full domain.

Quick checklist
Sender verified in Brevo (green badge under Settings → Senders, Domains & Dedicated IPs).
API key generated under Settings → SMTP & API → API Keys, saved somewhere safe.
@getbrevo/brevo installed in server/.
BREVO_API_KEY and BREVO_FROM_EMAIL added to server/.env (real values) and server/.env.example (placeholders).
server/src/shared/email/brevo.client.ts created.
Every importer of resend.client.ts switched to brevo.client.ts.
Test email sent and confirmed in Brevo's Email Activity log.

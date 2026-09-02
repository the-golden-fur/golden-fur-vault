# Customer credit-expiry visibility + branch fixed-date expiry config

Branch: `feat/credit-expiry-visibility-and-config` (off `dev`)

## The request, verbatim

> Allow customers to see when will their credits expire (perhaps on hover or a
> dedicated credits page). Also allow them to see on what branch their credits are
> tied to (since credits are branch limited). Perhaps just show the sum of all
> their credits across branches in the navbar. Then clicking on it will open a
> dedicated page that shows the credit distribution across other branches and
> their expiry (date and days left). Improve credits expiry config in admin
> settings — 2 options: entire branch credits expire at X date, or credits from
> specific transaction from specific booking expire at X date. Only one or the
> other.

Follow-up during the work: also show **how much** credit expires on the soonest
date, and let the customer expand that to see every expiry date for all their
credit.

Scope notes / decisions (see `plan.md`): "option B" is the existing rolling
N-days behaviour, just named; the navbar hover popover was built in addition to
click-through; mode changes are retroactive; a third `none` mode is kept because
non-expiring credit is existing behaviour we must not drop.

## Root cause / Context

Before this change, account credit (issued when a customer cancels a booking in
time) had a single expiry knob: `policy_configurations.credit_expiry_enabled`
(on/off) + `credit_expiry_days` (default 30), meaning only "N days after each
credit is issued". Customers had no way to see the expiry date, the amount, or
which branch a balance belonged to — only a summed peso figure in the navbar
pill, and a "< 7 days" warning badge on the `/portal` home.

## What changed

### Database

`supabase/migrations/20260902159_m10_policy_credit_expiry_mode.sql`:

- New enum `credit_expiry_mode` (`none` / `rolling` / `fixed_date`) + column
  `credit_expiry_fixed_date date` on `policy_configurations`; the old
  `credit_expiry_enabled` boolean is backfilled (`true`→`rolling`,
  `false`→`none`) then dropped. CHECK: `fixed_date` mode requires a date.
- New `reapply_branch_credit_expiry(p_branch_ids uuid[], p_mode, p_days,
p_fixed_date)` — `SECURITY DEFINER`, service-role only. Re-stamps `expires_at`
  on every not-yet-swept `issuance` row for the given branches per the new mode.
- `expire_credits()` re-created: it now re-reads the balance (`FOR UPDATE`) each
  loop iteration instead of once. The old version could drive a balance below 0
  (tripping the `balance >= 0` CHECK and aborting the whole sweep) when several
  same-dated lots — common under `fixed_date` — exceeded the balance.

`supabase/migrations/20260902160_m10_credit_expiry_manila_end_of_day.sql`
(follow-up after a live review — see Open items):

- Every not-yet-swept `issuance` lot's `expires_at` is snapped to the **end of
  its Asia/Manila calendar day** (the one non-DST timezone every branch uses),
  and both branches of `reapply_branch_credit_expiry()` do the same. Rolling was
  stamping `created_at + N days` (an exact time of day), so two lots issued
  hours apart on the same day got expiry timestamps hours apart and the credits
  page rendered them as two separate "Oct 1" rows with different "days left"; a
  UTC end-of-day for "Dec 31" also read as "Jan 1" in Manila.

### Server

- `booking.types.ts` — `CreditExpiryMode` type; `credit_expiry_mode` +
  `credit_expiry_fixed_date` on `PolicyConfiguration` and `EffectivePolicy`
  (removed `credit_expiry_enabled`).
- `modules/validators/booking.validator.ts` — `updatePolicyValidator` gains
  `credit_expiry_mode` (enum) + `credit_expiry_fixed_date` (YYYY-MM-DD); a
  `superRefine` enforces "date present iff mode is `fixed_date`" (the "only one
  or the other" rule).
- `services/staffPicker.service.ts` — `DOCUMENTED_DEFAULTS` / `baseline` updated;
  `updatePolicyConfiguration()` calls the new `reapplyCreditExpiryAfterPolicyChange`
  helper — a no-op unless the effective mode/days/date for the branch actually
  changed (the Policies page PATCHes all fields on every save), otherwise it runs
  `reapply_branch_credit_expiry`. For a branch-override row it re-applies to that
  branch; for the system-default row, every branch with no override of its own.
  Best-effort (logged, never fails the save — mirrors the #117 precedent). Also
  nulls `credit_expiry_fixed_date` whenever the mode is set to something other
  than `fixed_date`, so a stale date can't linger on the row.
- `services/cancellation.service.ts` — issuance-time `expires_at` is now a switch
  on `credit_expiry_mode` (`none`→null, `rolling`→now+N days,
  `fixed_date`→end-of-day of the configured date).
- `credits/services/creditBalance.service.ts` — `GET /credits/balances` now
  returns `next_expires_at` + `next_expires_amount` per branch row (soonest
  Manila day's lot total, FIFO-capped at the balance), so the navbar pill's
  popover needs no history round-trip. `credits.types.ts` `CreditBalance`
  extended. The enrichment lot query is best-effort — a failure returns the bare
  balances with `next_expires_* = null` rather than 400-ing the whole list.

### Client

- **New** `credits/utils/expiry.ts` — pure helpers: `computeExpirySchedule`
  (replays `expire_credits()`'s FIFO / "only down to the balance" walk to a
  `{expiresAt, amount, daysLeft}[]`, **bucketed by Manila calendar day** so
  same-day lots are one entry), `soonestExpiry`, `describeDaysLeft`,
  `formatExpiryDate` (pinned to Asia/Manila), `activeExpiringLots`, `daysUntil`
  (whole Manila calendar days, independent of time of day).
- **New** `server/src/features/credits/modules/creditExpiry.util.ts` —
  `manilaDayKey` / `manilaEndOfDayIso`, used by `cancellation.service.ts` (new
  lots) and `creditBalance.service.ts` (`next_expires_*` grouped per Manila day).
- `credits/components/CreditHistoryTable/CreditHistoryTable.tsx` — the "Expires"
  column date is pinned to Asia/Manila too.
- **New** `credits/pages/CustomerCreditsPage/` — `/portal/credits`: per-branch
  section (name, balance, "₱X expires <date> · N days left" / "Does not
  expire"), an expand toggle revealing the full expiry schedule + the raw
  `CreditHistoryTable`. Balances from the shared `CreditBalanceProvider`;
  per-branch history fetched here.
- `credits/credits.routes.tsx` — `/portal/credits` registered under
  `CustomerAuthGuard` alongside the staff `/staff/credits`.
- `credits/components/CreditBalanceIndicator/` — the navbar pill now links to
  `/portal/credits`; hovering / focusing it opens a popover listing each funded
  branch (name, balance, soonest expiry) + a "View credit details" link.
- `credits/components/CreditBalanceCard/` — shows the real soonest-expiry date +
  amount (warning colour under 7 days) instead of only the badge; "Does not
  expire" when history is loaded and no lot expires.
- `customers/config/customerPortal.config.ts` — sidebar "Credits" entry.
- `customers/pages/CustomerPortalPage/` — the per-branch card block is replaced
  by a one-line "You have ₱X … — view credit details" link to `/portal/credits`.
- `booking/booking.types.ts` + `PolicyConfigurationPage.tsx` — the "Credit
  expiry" section is now a mode `<select>` with a days input (rolling) or a date
  input (`fixed_date`), a retroactive-change warning line, and matching
  cross-field validation in `handleSubmit`.
- `.agent/skills/credit-balance-ledger.md` — updated for the new mode, the
  retroactive re-apply, the sweep re-read, and the customer-facing surfaces.

## Manual test — step by step

You'll need: both dev servers running (`npm run dev` from the repo root — client
on `http://localhost:5173`, server on `http://localhost:3000`); a Supabase
project with migration `20260902159` applied (`supabase db push`); a customer
account that has at least one **settled** (paid) Hotel booking far enough in the
future to cancel within the notice period.

### A. Admin configures rolling expiry, customer sees it

1. Open `http://localhost:5173`, click **Staff Login** (top-right), sign in as an
   Admin or Superadmin. You land on **Dashboard**.
2. Click the gear icon in the top bar → the **Settings** panel opens → click the
   **Config** tab → click the **Policies** tile. You're on
   `/staff/admin/maintenance/policies`.
3. At the top, in the **Branch** dropdown pick a specific branch (e.g. _Makati_)
   — not "System default".
4. Scroll to **Credit expiry**. In **How credit expires** choose _Expire a set
   number of days after each credit is issued_. Set **Expires after (days)** to
   `30`. Click **Save policy configuration**. You should see a green
   "Policy configuration updated." message. If you see a red banner, stop.
5. Sign out. **Customer Login**, sign in as your test customer.
6. In the top bar, find the wallet pill (shows a peso amount). **Hover** it — a
   small panel drops down listing each branch you have credit at, with the
   balance and "expires <date> · N days left" (or "No expiry"). Move the mouse
   onto the panel — it stays open. Move away — it closes after a moment.
7. **Click** the wallet pill. You land on `/portal/credits` ("Account Credit").
   For the branch you configured you should see the balance and
   "₱<amount> expires <~30 days out> · 30 days left". (If you have no credit yet,
   cancel a qualifying booking first — see step B — then come back.)
8. Click **Show expiry schedule & history** under that branch. You should see an
   **Expiry schedule** list (one row: amount + date + days left) and below it a
   **History** table with the issuance row and its Expires date.

### B. Cancellation mints credit at the configured expiry

1. As the customer, go to **My Bookings** (sidebar) → open a future Hotel booking
   that you've paid for → **Cancel booking** → confirm the dialog.
2. Return to `/portal/credits` (wallet pill). A new/blank branch section should
   now show a balance and an expiry ~30 days out.
   - API check: `GET /credits/balances` (as the customer) — each row has
     `next_expires_at` set ~30 days ahead and `next_expires_amount` equal to the
     issued amount. See the Postman collection.

### C. Switch the branch to a fixed date — retroactive

1. Back in **Settings → Config → Policies**, same branch → **Credit expiry** →
   _All of this branch's credit expires on one date_ → pick **tomorrow's date**.
   A warning line appears ("Saving this re-applies to credit customers already
   hold at this branch…"). **Save**.
2. As the customer, reload `/portal/credits`. The branch's credit now shows
   expiry = **tomorrow**, "1 day left" — the credit issued in step B changed,
   proving the retroactive re-apply.

### D. Force the sweep

1. Admin → **Settings → Config → Policies** → same branch → fixed date =
   **yesterday** → **Save**.
2. Trigger the expiry job: as an Admin, `POST http://localhost:3000/credits/expire`
   with a bearer token (see the Postman collection), **or** run
   `select public.expire_credits();` against the DB.
3. As the customer, reload `/portal/credits`. That branch's balance is now **₱0**
   and its **History** shows an "Expired" row. The wallet pill total dropped.

### E. "Never expires"

1. Admin → same branch → **Credit expiry** → _Credit never expires_ → **Save**.
2. As the customer, reload `/portal/credits` for a branch that still has credit —
   it now reads **"Does not expire"**; the expiry schedule says "None of this
   credit expires."
3. A fresh cancellation at that branch also mints a lot with no expiry.

### F. Validation

1. Admin → **Credit expiry** → _All of this branch's credit expires on one date_
   but leave the date blank → **Save**. You get an inline error
   ("Pick the date all of this branch's credit should expire on.").
2. API: `PATCH /bookings/policy` with
   `{"credit_expiry_mode":"fixed_date"}` (no date) → **400**. With
   `{"credit_expiry_mode":"rolling","credit_expiry_days":30,"credit_expiry_fixed_date":"2026-12-31"}`
   → **400** ("only one or the other"). See the Postman collection.

## Test suites

Run from the repo root packages:

- `server`: `npx vitest run` — **947/947 passing** (88 files); `npx tsc --noEmit`
  clean. (New/updated: credit-expiry-mode + Manila-EOD cases in
  `cancellation.service.spec`, `staffPicker.service.spec` reapply cases,
  `booking.validator.spec` mode/date rules, `creditBalance.service.spec`
  `next_expires_*` cases.)
- `client`: `npx vitest run` — **759/759 passing** (148 files); `npx tsc -b`
  clean; `npx vite build` succeeds. (New: `credits/utils/expiry.spec.ts` incl.
  Manila-day bucketing + calendar `daysUntil`, `CustomerCreditsPage.spec.ts`;
  rewritten: `CustomerPortalPage.spec.ts`, `CreditBalanceIndicator.spec.ts`.)
- Root `npm run format:check` — clean. `eslint` — 0 errors both packages.
- Migrations `20260902159` + `20260902160` applied to the linked **dev**
  project (`gtqncxqsofqtzrlgxdfm`); the two same-day test lots re-queried and
  confirmed sharing one `expires_at` afterward.

All counts run personally on this branch.

## Behaviour worth knowing (not a bug)

Redemptions don't attribute to a specific lot — `redeem_credit()` just
decrements the balance number. `expire_credits()` then expires **oldest-expiry
first**, up to whatever balance remains. So a redemption effectively "comes out
of" the customer's **latest-expiring** credit. Example seen in the live review:
3 issuances of ₱693 (expiring Oct 1, Oct 1, Oct 2) minus a ₱693 redemption →
balance ₱1,386. The expiry schedule shows **₱1,386 on Oct 1** and nothing on
Oct 2, because on Oct 1 the sweep will take both Oct-1 lots (capped at the
balance) and leave ₱0 for the Oct-2 lot. The schedule reflects what
`expire_credits()` will actually do, which is the honest view. Changing
redemption to consume soonest-expiring credit first would be a separate,
larger change to the ledger and is out of scope here.

## Code review

`code-reviewer` (pre-pr) — **APPROVE WITH NITS**, 0 blocking. Report:
`reviews/2026-09-02-1429-pre-pr.md`. It verified the client/server
`next_expires_*` ↔ `schedule[0]` agreement, the Manila timezone maths, the
retroactive branch-set logic, the validator superRefine, and the RPC's
`SECURITY DEFINER` / `service_role`-only grants.

Addressed here: N1 (re-stamp now a no-op unless mode/days/date changed),
N3 (balance list degrades instead of 400 on enrichment failure), N8 (service
nulls `credit_expiry_fixed_date` on a non-fixed mode change), N9 (Policies page
intro + config-tile copy refreshed).

Deferred (noted in the report, follow-ups): N2 (surface a reapply-RPC failure
to the admin, not just log it), N5/N6 (direct pgTAP/integration tests for
`expire_credits()` + `reapply_branch_credit_expiry()` and a client/server
`next_expires_*` parity fixture), N7 (a past-due-but-unswept lot reads
"expires \<past\> · Expired" on the pill until the sweep runs), N10 (pre-existing:
`expire_credits()` is `execute`-able by `authenticated`).

## Open items

- A `fixed_date` set on the **system-default** policy row re-applies to every
  branch that has no override of its own (not forward-only). This is the chosen
  reading of "entire branch credits expire at X"; revisit if a per-branch-only
  fixed date is ever wanted on the default row.
- No "credit expiring soon" notification — out of scope; would need a scheduled
  job, not a page-view trigger.

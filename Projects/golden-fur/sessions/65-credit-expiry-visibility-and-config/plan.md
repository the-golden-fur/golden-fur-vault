---
title: Let customers see when their store credit expires, and give branch owners a fixed expiry date
date: 2026-09-02
tags: [session-plan, golden-fur]
project: golden-fur
session: 65-credit-expiry-visibility-and-config
branch: feat/credit-expiry-visibility-and-config
---

# 65 — Let customers see when their store credit expires, and give branch owners a fixed expiry date

## What you asked for

Customers should be able to see when their account credit expires and which branch it belongs to, and admins should get a better way to configure that expiry.

> Allow customers to see when will their credits expire (perhaps on hover or a dedicated credits page). Also allow them to see on what branch their credits are tied to (since credits are branch limited). Perhaps just show the sum of all their credits across branches in the navbar. Then clicking on it will open a dedicated page that shows the credit distribution across other branches and their expiry (date and days left). Improve credits expiry config in admin settings — 2 options: entire branch credits expire at X date, or credits from specific transaction from specific booking expire at X date. Only one or the other.

Follow-up asked during planning: also show **how much** credit expires on the soonest date, and let the customer expand that to see every expiry date for all their credit.

## Background — the words and the pieces

**Account credit (a.k.a. store credit).** When a customer cancels a booking in time, the money they already paid is not refunded to their card — it is turned into _credit_ they can spend on a future booking. Think of it like a gift card balance.

**Branch.** Golden Fur has more than one physical shop location ("Makati", "Southwoods", …). Each is a _branch_.

**Credit is branch-locked.** A customer's credit is tracked _per branch_. Credit earned from a Makati cancellation can only be spent at Makati. In the database there is one row per (customer, branch) pair in a table called `credit_balances`, and it holds a single number — that branch's balance for that customer.

**The ledger.** Every change to a balance is also written as a row in `credit_transactions`: a positive row when credit is _issued_, a negative row when it is _redeemed_ (spent) or _expired_. Adding up all the rows for a balance always equals the balance. Each _issuance_ row also stores an `expires_at` date. `expires_at` being empty (`NULL`) means "this credit never expires".

**The expiry sweep.** A scheduled database job called `expire_credits()` runs once a day. It looks for issuance rows whose `expires_at` is in the past, writes a matching negative "expiry" row, and lowers the balance. It processes oldest-expiring credit first (this is called **FIFO** — first in, first out). It only ever expires credit _down to the current balance_ — so if the customer has already spent some of it, there is less left to expire.

**`policy_configurations` table.** A single wide table that holds all the tweakable business rules — notice periods, fees, and (relevant here) two columns: `credit_expiry_enabled` (a yes/no switch) and `credit_expiry_days` (a number, default 30). There is one "system default" row plus optional one-per-branch override rows. When the app needs a rule for a branch it calls `resolveEffectivePolicy(branchId)`, which returns the branch's own row if it has one, otherwise the default row.

**Where expiry is decided today.** In `server/src/features/booking/services/cancellation.service.ts`, at the moment a cancellation issues credit: if `credit_expiry_enabled` is on, it sets `expires_at = today + credit_expiry_days`. Otherwise `expires_at` is empty. Changing the policy later does **not** touch credit that was already issued.

## What this part of the app looks like today

**For the customer:**

- Every customer page has a top bar (the **navbar**). On it is a small wallet-icon "pill" showing one peso amount — the **sum of the customer's credit across all branches**. This already exists. Clicking it currently goes to the portal home page.
- The **portal home** page (`/portal`, headed "Welcome back…") shows one card per branch where the customer has a positive balance. Each card shows the branch name, the balance, and — only if some credit expires within the next 7 days — a small "Expires in N days" badge. It never shows the actual date.
- There is **no page** dedicated to credit, and no way to see the expiry _date_ or _which branches_ the credit is spread across unless it happens to be within that 7-day window.

**For the admin:**

- Admins open **Settings → Config → Policies** (the page component is `PolicyConfigurationPage`). It has a "Credit expiry" section with a checkbox ("Unused credit expires") and a number box ("Expires after (days)"). That is the whole configuration surface. It only ever means "N days after each credit is issued".

## What's wrong / what's missing

1. A customer with credit at two branches sees a single lumped-together number and cannot tell where it lives or when any of it disappears.
2. The only expiry hint is a 7-day badge — no date, no amount, no "here is everything".
3. The admin cannot express "all credit at this branch is void after 31 December" — only a rolling "30 days from issuance".
4. The request says the two admin options must be **mutually exclusive** — the current single checkbox cannot represent that.

## What we're going to change

### 1. Replace the expiry checkbox with a three-way "mode"

- **Which files:**
  `supabase/migrations/<new>_m10_policy_credit_expiry_mode.sql` (new),
  `server/src/features/booking/booking.types.ts`,
  `server/src/features/booking/modules/validators/booking.validator.ts`,
  `server/src/features/booking/services/staffPicker.service.ts`,
  `client/src/features/booking/booking.types.ts`,
  `client/src/features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`
- **What:** add a new **enum** column `credit_expiry_mode` with three values:
  - `none` — credit never expires.
  - `rolling` — each piece of credit expires `credit_expiry_days` after it was issued. This is exactly today's behaviour, just named.
  - `fixed_date` — every piece of that branch's credit expires on one calendar date, stored in a new `credit_expiry_fixed_date` column.
    The old `credit_expiry_enabled` checkbox is removed; existing rows are converted (`enabled` → `rolling`, not enabled → `none`). A database **CHECK** makes it impossible to save `fixed_date` without a date.
- **Why:** an enum is the natural way to say "one of these, never two". The migration's `NOT NULL DEFAULT 'rolling'` means every existing branch keeps behaving exactly as before with zero data cleanup.

### 2. Make a mode change apply to credit customers _already_ hold

- **Which files:** the same new migration (adds a database function `reapply_branch_credit_expiry`), and `staffPicker.service.ts`.
- **What:** whenever an admin changes the expiry mode (or its date/days), the server calls a new function that re-stamps `expires_at` on every not-yet-expired credit for the affected branch(es): `none` → cleared, `rolling` → "issued date + N days", `fixed_date` → the chosen date. If the admin edits a _specific branch's_ row, only that branch is touched; if they edit the shared _default_ row, every branch that has no row of its own is touched. This write is best-effort — if it fails it is logged but the policy still saves (same rule the codebase already uses for credit issuance).
- **Why:** "entire branch credits expire at X date" naturally means _all_ of them, not just future ones — and the same should hold when the admin relaxes the rule. The daily sweep (`expire_credits()`) needs no change — it still just looks at `expires_at`.

### 3. Teach the issuance code the new mode

- **Which files:** `server/src/features/booking/services/cancellation.service.ts` (around line 157).
- **What:** where it currently does `enabled ? today+days : null`, switch on the mode: `none` → empty, `rolling` → today + N days (unchanged), `fixed_date` → the configured date (end of that day).
- **Why:** this is the one spot where a brand-new credit gets its expiry stamped.

### 4. Add expiry info to the credit-balance API

- **Which files:**
  `server/src/features/credits/services/creditBalance.service.ts`,
  `server/src/features/credits/credits.types.ts`,
  `client/src/features/credits/api/credits.api.ts`
- **What:** the endpoint that lists a customer's per-branch balances (`GET /credits/balances`) gains two extra fields per branch: `next_expires_at` (the soonest upcoming expiry date) and `next_expires_amount` (how much pesos actually expires on that date, computed with the same FIFO/"only down to the balance" logic the sweep uses).
- **Why:** the navbar pill refreshes every 20 seconds; putting these two small numbers on the balance row means the pill's hover popup needs no extra network calls.

### 5. New dedicated customer page: `/portal/credits`

- **Which files:**
  `client/src/features/credits/pages/CustomerCreditsPage/CustomerCreditsPage.tsx` (new) + its `.module.css`,
  `client/src/features/credits/utils/expiry.ts` (new),
  `client/src/features/credits/credits.routes.tsx`,
  `client/src/features/customers/config/customerPortal.config.ts`
- **What:** a page listing the customer's total credit and one section per branch. Collapsed, each section shows "₱X expires on `<date>` · N days left" (or "Does not expire"). Expanded, it shows the **full expiry schedule** — every future date and the amount expiring then — followed by the raw transaction history table (which already exists). A new sidebar link "Credits" points here, and the route is registered next to the existing staff `/staff/credits` route (the reports feature already does this staff-plus-customer pattern).
- **Why:** this is the "dedicated page" the request asks for; the schedule + amounts answer the follow-up.

### 6. Point the navbar pill at the new page and give it a hover popup

- **Which files:**
  `client/src/features/credits/components/CreditBalanceIndicator/CreditBalanceIndicator.tsx`,
  `client/src/features/credits/components/CreditBalanceCard/CreditBalanceCard.tsx`,
  `client/src/shared/components/InfoPopover/InfoPopover.tsx` (maybe — add an "open on hover" option)
- **What:** clicking the pill now goes to `/portal/credits`. Hovering it (or focusing it with the keyboard) opens a small popup listing each branch: name, balance, and "₱X expires `<date>` · N days left". The existing per-branch card is updated to show the real date and amount instead of the vague 7-day badge.
- **Why:** the request explicitly offers "on hover **or** a dedicated credits page" — this does both.

### 7. Trim the portal home

- **Which files:** `client/src/features/customers/pages/CustomerPortalPage/CustomerPortalPage.tsx` and its `.spec.ts`.
- **What:** replace the per-branch card block with a single line — "You have ₱X in account credit across N branches — View credit details" — linking to the new page.
- **Why:** one home for this information, not two.

## Words you might not know

- **migration** — a numbered SQL script that changes the database's shape (adds a column, a table, a function). They run in order; each one runs exactly once.
- **enum** — a column type that only allows a fixed set of named values (here: `none`, `rolling`, `fixed_date`).
- **CHECK constraint** — a rule the database enforces on every write; a row that breaks it is rejected.
- **RLS (row-level security)** — Postgres rules deciding which rows a given user may read/write. The credit tables let a customer read only their own rows; only the server's privileged connection writes.
- **FIFO** — "first in, first out"; the oldest-expiring credit is used up / expired first.
- **issuance / redemption / expiry** — the three kinds of ledger row: credit added, credit spent, credit lost to time.
- **policy row / effective policy** — a row of business-rule settings; the "effective" one for a branch is its own row if it has one, else the shared default row.
- **navbar pill** — the small rounded wallet-icon control in the top bar showing the credit total.
- **popover** — a small floating panel that appears next to the thing you clicked or hovered.
- **enum backfill** — when a new `NOT NULL` column with a default is added, every existing row automatically gets that default, so no separate data-fix step is needed.

## Decisions locked in

From the requester:

- Option B ("credits from a specific transaction expire at X") means the **rolling N-days** behaviour we already have, just formally named — not a per-transaction manual date picker.
- Mode changes are **retroactive** — they change credit customers already hold.
- Build the **new page** and move the cards off the portal home.
- **Do** build the navbar hover popup, in addition to click-through.

Delegated to the implementer, kept faithful to "entire branch credits expire at X date":

- **One rule for every mode change:** switching a branch's mode re-stamps the expiry on _all_ credit currently outstanding at that branch — `none` clears it, `rolling` sets "issued + N days", `fixed_date` sets date X.
- **Editing the shared default policy row** fans the same re-stamp out to every branch that has no row of its own (not just future credit).
- **We keep a third mode, `none` ("never expires").** The request names two _expiry_ options; `none` is the existing on/off switch, which we must not drop — non-expiring credit is current, documented behaviour.
- **"Credit expiring soon" email/notification is out of scope** — no such notification exists today and it would need its own scheduled job.

## How you'll know it worked

Implemented on `feat/credit-expiry-visibility-and-config`. See
`testing/testing.md` for the click-by-click checks and
`testing/credit-expiry-visibility-and-config.postman_collection.json` for the
API-level ones; `testing/credit-expiry-visibility-and-config.sql` is a reference
copy of both migrations. In short: set each mode in Settings → Config →
Policies, cancel a booking to mint credit, then confirm the navbar pill, its
hover popover, and `/portal/credits` all show the right date, amount, and
days-left — including after switching a branch to a fixed date (existing
credit's date must change too). Server `npx vitest run` 947/947; client
759/759; both typecheck + lint + format clean; `vite build` succeeds.
Migrations `20260902159` + `20260902160` (the latter a live-review follow-up
snapping every lot's expiry to the end of its Asia/Manila day, so same-day
lots show as one entry and the shown date matches the days-left) applied to
the dev project.

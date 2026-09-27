---
title: Give cashiers their own Misc Sales page, and stop actually processing online payments
date: 2026-09-27
tags: [session-plan, golden-fur]
project: golden-fur
session: 115-misc-sales-cashier-and-payment-removal
branch: not yet created — staged on dev
---

# 115 — Give cashiers their own Misc Sales page, and stop actually processing online payments

## What you asked for

Move the "misc sales" feature out of Admin Settings and give the Cashier role a proper page for it with full search/sort/filter tools, and delete the app's real online-payment pipeline (GCash/Maya stay as payment _labels_ only):

> As a developer, I want misc sales to be moved out of admin settings, to cashier's sidebar as a page
>
> - As a cashier, I want CRUD access to misc sales (I can create new sales via a button that opens a form, and view a history of such sales in my transactions page)
> - As an admin/superadmin, I want CRUD access to both misc sales and misc items, where I can create new misc items cashiers can choose from
>
> Always include the shared search, sort, filter, group by and view options
>
> Also remove all traces of online payment
>
> - We're switching to just having gcash and paymaya as payment methods, not actual online payment processes

## What this part of the app does today

A few terms first: **CRUD** means Create, Read, Update, Delete — the four things you can do to a record. A **misc sale** ("miscellaneous sale") is a sale of something that isn't a booking — e.g. selling a bag of dog food at the counter, with no grooming/hotel/vet appointment attached. **RBAC** (role-based access control) means different staff roles get different permissions in the same app.

Golden Fur's staff app has role-based dashboards. Each staff member (Cashier, Receptionist, Admin, Superadmin, etc.) logs in and sees a **sidebar** of pages for their role, defined in one file: `client/src/features/staff/config/staffDashboard.config.ts`. Today the Cashier's sidebar has: Days Off, My Schedule, Checkout & Billing (a placeholder, not yet linked to anything), Transactions, Credit Management, and Credit Review Queue. There is no Misc Sales entry for Cashier at all.

Right now, "misc sales" live in two disconnected places:

1. **A creation page cashiers can't reach.** `client/src/features/billing/pages/MiscellaneousSalePage/MiscellaneousSalePage.tsx` (web address `/staff/billing/misc-sale`) has the actual "record a new misc sale" form — pick a customer, pick an item (or type a description + price), pick a payment method. But nothing in the app links to it. A cashier would have to type the address by hand.
2. **An admin-only list page under Settings.** In Admin Settings → Config, there's a "Miscellaneous Sales" tile that opens `client/src/features/billing/pages/MiscSaleManagementPage/MiscSaleManagementPage.tsx` (web address `/staff/admin/misc-sales`). It only lets Admin/Superadmin in — the page itself checks the logged-in user's role and redirects anyone else away. It shows every past misc sale as a plain bulleted list, with basic inline edit/delete. It has none of the search/filter/sort tools the rest of the app uses.

There's no separate database table for "misc sales" — a misc sale is stored as a row in the shared `transactions` table (the same table booking payments use), just tagged `transaction_type = 'miscellaneous_sale'` with no booking attached. The item a customer bought is a row in `transaction_line_items`.

There's also no separate "misc items" table. The list of purchasable items cashiers choose from when recording a misc sale is the shared **Product Catalog** (`product_catalog` database table). Admin/Superadmin already have a full CRUD page for it today: `client/src/features/catalog/pages/ProductCatalogPage/ProductCatalogPage.tsx`, reached from Settings → Config → "Product Catalog" tile. This already satisfies the "admin CRUD for misc items" half of the request — nothing needs to be built for that part, just a small copy tweak so it's clear this is where a cashier's item choices come from.

The Cashier's existing **Transactions** page (`client/src/features/reports/components/TransactionHistoryTable/TransactionHistoryTable.tsx`, address `/staff/reports/transaction-history`) already lists misc sales mixed in with booking payments, and already has a filter for "Miscellaneous sale" as a transaction type. This page already has the shared search/sort/filter/group-by/table-or-board-view toolbar the rest of the app uses (the `FilterSortBar` + `ViewSwitcher` components, `client/src/shared/components/FilterSortBar/` and `client/src/shared/components/ViewSwitcher/`). So the "view history in my transactions page" part of the ask is basically already true today.

Separately: three payment methods — **GCash**, **Maya** (also called PayMaya), and everything else (Cash, Card, Bank Transfer, Grabmart, Pickaroo) — are stored in the same `payment_method` column. But GCash and Maya are currently wired to a real payment processor called **PayMongo**. When a customer or cashier picks GCash/Maya through the "customer portal" channel, the app calls PayMongo's API, gets back a checkout web address, and redirects the browser there to actually take the payment. PayMongo then calls our server back (a **webhook** — an HTTP request PayMongo sends us when the payment finishes) to confirm it. This whole pipeline exists in `server/src/features/billing/services/paymongo.service.ts` and several files that call it.

## What's wrong / what's missing

- A cashier who wants to record a walk-in sale (dog food, a leash, etc.) has no way to get there from their own sidebar — the create page is orphaned, and the only list view is locked to Admin/Superadmin.
- The one list view that does exist (`MiscSaleManagementPage`) doesn't have the search/sort/filter/group-by/view-switcher toolbar every other list page in the app has — it's a bare bullet list.
- The company has decided it will **not** actually process GCash/Maya payments through PayMongo (no merchant account is even set up yet — this was already flagged as "dormant" in the code). GCash and Maya should work exactly like Cash does today: the cashier picks it from a dropdown, types a reference number if there is one, and marks the sale as paid themselves. But the code still has: a "Customer portal vs. Scan QR at counter" choice on the cashier's payment form, a PayMongo webhook endpoint, checkout-redirect logic in three places, a customer-facing "pay via GCash/Maya online" button, an admin on/off toggle for "online payments," and fee-notice banners referencing PayMongo's processing fee. All of this needs to come out.

## What we're going to change

We'll do this as two ordered stages in the same branch. Stage A (remove online payments) goes first because it simplifies files that Stage B also needs to touch (the misc-sale creation form, for one) — better to simplify once than rework the same lines twice.

### Stage A — remove the online-payment pipeline

1. **Make GCash/Maya settle immediately, like Cash.** _Which file:_ `server/src/features/billing/services/paymentMethod.service.ts` — _Why:_ this file's `resolvePaymentConfirmation()` function is the one place that currently decides "GCash/Maya via the customer portal stays Pending until PayMongo's webhook confirms it; everything else is confirmed right away." Delete that special case so GCash/Maya always confirm immediately, same as Cash/Card.
2. **Delete the PayMongo checkout-redirect calls.** _Which files:_ `server/src/features/billing/services/miscSale.service.ts`, `server/src/features/billing/services/checkoutAggregation.service.ts` — _Why:_ these are the two places (recording a misc sale, and the cashier's normal checkout) that currently call PayMongo to get a checkout web address and hand it back to the browser. Since GCash/Maya no longer need an external processor, this call and the "hand back a checkout URL" response field both go away.
3. **Delete the PayMongo service and webhook entirely.** _Which files:_ delete `server/src/features/billing/services/paymongo.service.ts`, `server/src/features/billing/routes/paymongoWebhook.routes.ts`, `server/src/features/billing/services/webhookConfirmation.service.ts`; remove their registration in `server/src/shared/app.routes.ts`; remove the raw-request-body capture in `server/src/app.ts` (it existed only so the webhook could verify PayMongo's signature) — _Why:_ nothing calls a real payment processor anymore, so there's nothing for a webhook to confirm.
4. **Remove the customer's "pay online" button.** _Which file:_ `client/src/features/reports/pages/CustomerTransactionHistoryPage/CustomerTransactionHistoryPage.tsx`, plus deleting `payForBooking` from `client/src/features/booking/api/booking.api.ts` and its server route in `server/src/features/booking/booking.controller.ts` / `booking.routes.ts` — _Why:_ this was the customer-portal "pay this booking via GCash/Maya online" flow, which only existed to hand the customer a PayMongo checkout link. A remote customer has no cashier to confirm payment manually, so this option is removed outright — the customer's other self-service option, paying with **account credit** (`payTransactionWithCredit`), is untouched and remains their way to pay from the portal. Otherwise, customers pay at the counter like a walk-in.
5. **Remove the "Customer portal vs. Scan QR at counter" choice from the cashier's payment form.** _Which file:_ `client/src/features/billing/components/PaymentMethodForm/PaymentMethodForm.tsx` — _Why:_ this radio-button choice only existed to pick which PayMongo flow to use. With no PayMongo, GCash/Maya just need the same "type a reference number" field Card/Bank Transfer already show.
6. **Remove the fee-notice banners and the fee-rate endpoint.** _Which files:_ delete `client/src/features/billing/components/PayMongoServiceFeeNotice/`, `client/src/features/booking/components/PayMongoFeeNotice/`, `getPaymongoFeeRate()` in `client/src/features/billing/api/billing.api.ts`, and the `GET /billing/paymongo/fee-rate` route/controller — _Why:_ these warned customers/cashiers about "an online processing fee," which no longer applies since nothing is processed online.
7. **Remove the admin "online payments" on/off switch.** _Which file:_ `client/src/features/booking/pages/PolicyConfigurationPage/PolicyConfigurationPage.tsx`, plus the `online_payments_enabled` setting wherever it's read on the server (`server/src/features/booking/services/staffPicker.service.ts`) — _Why:_ this toggle only made sense when online payments were a real, sometimes-off feature. There's nothing left to toggle.
8. **Drop the now-unused database columns.** _New file:_ `supabase/migrations/<next-number>_custom_remove_online_payment_columns.sql`, dropping `transactions.webhook_confirmed_at`, `transactions.initiated_by`, and `policy_configurations.online_payments_enabled` — _Why:_ these columns only ever recorded facts about the PayMongo webhook flow (when it confirmed a payment, who "initiated" a payment). Checked: no seed file and no other database function reads or writes them, so dropping them is safe. **Note:** the similar-sounding `payment_choice` column is _not_ touched — it's used by every booking payment regardless of method and has nothing to do with PayMongo specifically.
9. **Retire the PayMongo skill/agent docs.** _Which files:_ delete `.agent/skills/paymongo-webhook-handling.md`, `.agent/agents/payment-billing-agent.md`, and their generated copies under `.claude/`, `.codex/`, `.gemini/`; remove their entries from `AGENTS.md`'s index — _Why:_ these are AI-assistant instruction files describing how to work with the PayMongo webhook. Once that code is gone, the instructions would be actively misleading if left behind.
10. **Clean up deployment config that still mentions PayMongo.** _Which files:_ `render.yaml` (drop the 5 `PAYMONGO_*` environment variable declarations) and `docs/deployment.md` (drop the matching documentation rows) — _Why:_ these were missed by an earlier cleanup that only touched `server/.env.example`; they're the actual settings Render (the hosting service) would apply on deploy, so leaving stale PayMongo secrets declared there is confusing and pointless.

### Stage B — build the Cashier's Misc Sales page

11. **Turn the existing admin-only list page into the shared Cashier+Admin page.** _Which file:_ `client/src/features/billing/pages/MiscSaleManagementPage/MiscSaleManagementPage.tsx` (same file, same web address `/staff/admin/misc-sales` — we're upgrading it in place, not creating a second page) — _Why:_ one list is simpler than two, and it already has the right data-fetching logic. Concretely:
    - Widen who's allowed to view it from "Admin/Superadmin only" to every staff role that can already create a misc sale (Cashier included — this matches what the server already allows).
    - Replace the bare bullet list with the same reusable table/board/filter/sort/group-by toolbar used elsewhere in the app (`FilterSortBar`, `ViewSwitcher`, `useGroupBy`, `DataTable`, `DataBoard` — all under `client/src/shared/components/`), following the pattern already used by the Product Catalog admin page (`client/src/features/catalog/components/CatalogAdminPage/CatalogAdminPage.tsx`) as the template to copy.
    - Add a new small file, `client/src/features/billing/pages/MiscSaleManagementPage/miscSaleBrowserFields.ts`, that defines what you can filter by (payment method, status, date, customer), sort by, and group by — following the same pattern as `transactionFilterFields.ts` (used by the Transactions page).
    - Show a **"New Misc Sale"** button that opens the existing creation form (`MiscellaneousSaleForm`) inside a **popup window** (a "modal," using the app's shared `Modal` component, `client/src/shared/components/Modal/Modal.tsx`) instead of navigating to a separate page — this matches the literal ask: "a button that opens a form."
    - Show Edit/Delete buttons on each row **only** for Admin/Superadmin — Cashiers see their sales listed (read-only) plus the "New Misc Sale" button, matching the CRUD split the server already enforces (Cashier can create/view; only Admin/Superadmin can edit/delete).
12. **Delete the now-redundant standalone creation page.** _Which files:_ delete `client/src/features/billing/pages/MiscellaneousSalePage/` (the whole folder) and its route entry in `client/src/features/billing/billing.routes.tsx` — _Why:_ once "New Misc Sale" opens as a popup on the list page (step 11), this separate, currently-unlinked page has no more reason to exist.
13. **Add "Miscellaneous Sales" to the Cashier's sidebar.** _Which file:_ `client/src/features/staff/config/staffDashboard.config.ts` — _Why:_ this is the one file that controls every role's sidebar. Add a new tile pointing at `/staff/admin/misc-sales` in two spots in this file: the Cashier role's own tile list, and the matching "Cashier" section shown inside the Admin/Superadmin dashboard (the file currently lists these twice by hand rather than sharing one list, so both copies need the new tile).
14. **Remove "Miscellaneous Sales" from Admin Settings.** _Which file:_ `client/src/pages/SettingsPage/configTiles.config.ts` — _Why:_ this is the literal ask — it no longer belongs in Settings once it's a sidebar page in its own right. The "Product Catalog" tile (misc _items_) stays in Settings exactly as it is today.
15. **Add a cross-reference link back to Transactions.** _Which file:_ `client/src/features/billing/pages/MiscSaleManagementPage/MiscSaleManagementPage.tsx` — _Why:_ each row gets a small "View in Transactions" menu option linking to `/staff/reports/transaction-history`, so a cashier bouncing between the two pages doesn't have to re-search by hand.

## Words you might not know

- **Migration** — a small, numbered file under `supabase/migrations/` that changes the shape of the database (adds/removes a table or column). Migrations run in order and are never edited after the fact — a change is always a _new_ migration file.
- **RLS (row-level security)** — a database-level rule (separate from anything the app's own code checks) that limits which rows a given logged-in user is even allowed to see or change. Golden Fur uses this as a second layer of protection behind the app's own role checks.
- **Enum** — a fixed list of allowed values for a column (e.g. `payment_method` can only ever be `'Cash'`, `'GCash'`, `'Maya'`, `'Card'`, `'Bank Transfer'`, `'Grabmart'`, or `'Pickaroo'` — nothing else).
- **Webhook** — an HTTP request one system sends to another, automatically, when something happens on its end — here, PayMongo notifying our server "this payment went through."
- **RBAC (role-based access control)** — restricting what a feature does based on which staff role (Cashier, Admin, Superadmin, etc.) is logged in.
- **Modal** — a popup window that appears on top of the current page (like a form for adding something) without navigating away.

## How you'll know it worked

See `testing/testing.md` (to be filled in once this plan is implemented) for the click-by-click checks. In short: a Cashier should be able to open a new "Miscellaneous Sales" tile from their own sidebar, record a sale (including picking GCash/Maya with no "online" option shown), and see it appear both there and on their existing Transactions page — while an Admin/Superadmin sees the same page with added Edit/Delete controls, and Settings no longer lists Misc Sales at all. Separately, the Policy Configuration page's "online payments" toggle should be gone, and there should be no working `/billing/paymongo/*` endpoints left.

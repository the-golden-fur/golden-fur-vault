---
title: Billing — Code Guide
date: 2026-09-17
tags: [architecture, golden-fur, code-guide, billing]
project: golden-fur
---

The checkout/aggregation point of the app: turning a completed booking (or a walk-in counter sale) into a `transactions` row with line items, applying discounts/promos/credit, resolving the payment method (including PayMongo GCash/Maya), and settling later partial or balance payments. Covers the cashier checkout screen, the Miscellaneous Sale form and its admin management screen, and the PayMongo webhook.

**Part of:** [[M08-sales-billing]]

## Client-side (`client/src/features/billing/`)

### api/

- **`billing.api.ts`** — every fetch call this feature makes: PayMongo fee rate, checkout preview/confirm, misc-sale create/list/get/update/delete, per-booking payment history, recording a counter payment, adding a balance charge, and paying a transaction from credit.

### components/

- **`BookingPaymentsPanel/BookingPaymentsPanel.tsx`** — self-fetching "Payments for this booking" list (`GET /billing/booking/:id/transactions`), showing each payment's amount, whether it was a down payment/balance/full payment, method, status, and reference.
- **`CreditApplicationPanel/CreditApplicationPanel.tsx`** — the "apply customer credit" input on checkout/misc-sale, clamping the entered amount to `MIN(availableBalance, transactionTotal)` client-side. Its own doc comment still calls this a stub pending Epic B; in practice both call sites (`CashierCheckoutPage`, `MiscellaneousSaleForm`) pass a hardcoded `availableBalance={0}`, even though the server-side credit balance is real now (see [[M10-credit-balance-management]]) — the panel never actually offers credit to apply as currently wired.
- **`MiscellaneousSaleForm/MiscellaneousSaleForm.tsx`** — the counter-sale form: a customer picker, a catalog-item-or-freetext item picker (`CatalogComboBox`), and the reused `CreditApplicationPanel`/`PaymentMethodForm`/`PayMongoServiceFeeNotice`. Submits to `POST /billing/misc-sale`; redirects to PayMongo's checkout URL when the response includes one.
- **`PaymentMethodForm/PaymentMethodForm.tsx`** — renders the right minimal fields per selected payment method: Cash gets a tendered-amount input and computed change, Bank Transfer adds a BPI/BDO selector, Card/Grabmart/Pickaroo get a reference-number field, GCash/Maya get a portal-vs-walk-in-QR channel choice. Also supports a `methods` override (the Transactions page adds a `'Credit'` option) and a `hideCashTendered` flag for that same page's simpler "mark as paid" modal.
- **`PayMongoServiceFeeNotice/PayMongoServiceFeeNotice.tsx`** — non-blocking notice shown only for GCash/Maya, fetching the configured fee percentage from `GET /billing/paymongo/fee-rate` rather than hardcoding it.

### pages/

- **`CashierCheckoutPage/CashierCheckoutPage.tsx`** — the main checkout screen at `/staff/billing/checkout(/:bookingId)`. Loads a live preview (`GET /billing/checkout/:bookingId/preview`) that re-fetches whenever the Senior Citizen/PWD checkboxes change, shows every line item plus a running total, then submits `POST /billing/checkout` with the chosen payment method and credit amount.
- **`MiscellaneousSalePage/MiscellaneousSalePage.tsx`** — thin wrapper mounting `MiscellaneousSaleForm`, reachable independently of any booking.
- **`MiscSaleManagementPage/MiscSaleManagementPage.tsx`** — Admin/Superadmin-only (client-side gated, mirrored by RLS) list of recorded misc sales with inline edit (description/amount) and delete, backed by `PATCH`/`DELETE /billing/misc-sale/:id`.

### Other files

- **`billing.routes.tsx`** — wires the three pages above under `/staff/billing/*`, behind `StaffAuthGuard`; role enforcement itself is server-side.
- **`billing.types.ts`** — client-side shapes: `PAYMENT_METHODS`/`BANK_NAMES`/`PAYMENT_CHOICES` consts, `Transaction`/`TransactionLineItem`, and the checkout/misc-sale request/response types — mirrors the server's own `billing.types.ts`.

The `.module.css` files paired with each component/page are pure styling and are skipped here as boilerplate.

## Server-side (`server/src/features/billing/`)

### Controller & routes

- **`billing.controller.ts`** — one exported function per endpoint: PayMongo fee rate, checkout preview/confirm (single booking and booking-group variants), misc-sale CRUD, per-booking/group transaction history, recording a counter payment, adding a balance charge, and paying with credit. Each validates its body with a Zod schema and turns a thrown `statusCode`-carrying error into the right HTTP response.
- **`billing.routes.ts`** — maps each controller to a path under `/billing/*`. Most routes require `BILLING_STAFF_ROLES` (Superadmin/Admin/Supervisor/Receptionist/Cashier) plus `requireBranch` on writes; misc-sale update/delete are `BILLING_ADMIN_ROLES`-only; `pay-with-credit` is `jwtMiddleware`-only since a customer can pay their own transaction (ownership is checked in the service).
- **`routes/paymongoWebhook.routes.ts`** — `POST /billing/paymongo/webhook`, PayMongo's own callback. No staff session; authenticated only by the `paymongo-signature` HMAC verified against the raw request body. Always responds 200 once the signature checks out, even for a `failed` event, so PayMongo doesn't retry redelivery forever.

### Services

- **`checkoutAggregation.service.ts`** — the file most worth reading; the core of checkout. `buildCheckoutPreview` assembles a booking's service lines (via `lineItemSources.service.ts`), discount/promo lines (either the booking-time-locked-in selection, or auto-evaluated via `discountPromoEvaluation.service.ts` as a fallback), and totals them into a `preCreditTotal`. `checkoutBooking` calls that preview, applies credit, resolves the payment method, and persists one `transactions` row plus its `transaction_line_items` — deleting any stale `Pending` estimate charge from booking creation first. `buildGroupCheckoutPreview`/`checkoutBookingGroup` are the multi-booking (`booking_groups`) counterparts, combining every member booking's lines into one shared transaction.
- **`lineItemSources.service.ts`** — `getBookingForBilling` loads a booking (must be `Completed`) with its items, discount/promo selections, and downpayment info. `getServiceLineItems` dispatches by `service_category` to a per-category builder: Grooming/Assessment list each selected item; Hotel bills one aggregate "Hotel stay" line netted against its already-collected downpayment (plus any late-checkout extension fee and free-package lines); Daycare bills the session's computed charge; Veterinary bills each `consultation_line_items` row.
- **`discountPromoEvaluation.service.ts`** — `evaluateDiscounts` auto-applies every active discount whose scope (service/package/category) and branch match, gated to Cash payments only and, for the mandated Senior Citizen/PWD discounts, an explicit eligibility flag. `evaluatePromos` auto-applies every active, in-window, scope-matching promo, capped by `promo_cap_configuration` (a branch-specific row or the system-wide default) — a percentage/flat cap trims the last promo that would cross it, a count cap keeps only the largest-value promos up to that count. Coupons are deliberately excluded from auto-evaluation; they're only applied by explicit choice at booking time.
- **`paymentMethod.service.ts`** — `resolvePaymentConfirmation`: every manual method and GCash/Maya's walk-in-QR channel confirm immediately (`Fully Paid`, with Cash also returning computed change via `computeCashChange`); only GCash/Maya's `'portal'` channel stays `Pending` until the PayMongo webhook confirms it.
- **`paymongo.service.ts`** — `initiatePaymongoPayment` creates a PayMongo e-wallet Source for the portal channel and returns its checkout URL. `verifyPaymongoWebhookSignature` checks PayMongo's `paymongo-signature` header (HMAC-SHA256 of `timestamp.rawBody`) with `timingSafeEqual`. `parsePaymongoWebhookEvent` extracts the event id, source id, and paid/failed status from the raw webhook body. `getPaymongoServiceFeeRate` reads a configured `PAYMONGO_SERVICE_FEE_PERCENT` env var (default 2.5), since PayMongo has no public "current rate" API.
- **`webhookConfirmation.service.ts`** — `confirmPaymongoWebhookEvent` flips a `Pending` transaction matching the event's source id to `Fully Paid`, idempotently (a second delivery finds no still-`Pending` row and is a no-op). For a customer-initiated payment it also rolls the booking's (or booking group's) `payment_status` up, best-effort.
- **`transactionPayment.service.ts`** — `recordTransactionPayment` is a cashier's counter-payment action on a `Pending` transaction, wrapping the `settle_transaction` RPC; a partial `amountApplied` settles this row and spawns a new `Pending` `'balance'` transaction for the rest. `addBookingPayment` adds a fresh balance charge via the `add_booking_payment` RPC. `payTransactionWithCredit` redeems the customer's credit against a `Pending` transaction in one atomic RPC (`pay_transaction_with_credit`) — see [[M10-credit-balance-management]] for the redemption mechanics it calls into.
- **`customerBookingPayment.service.ts`** — the customer-self-service counterpart of checkout (not exposed by `billing.routes.ts`'s controller list read for this guide, but consumed by the booking feature's customer-facing payment flow). `payForBooking` finds the booking's existing `Pending` charge (down payment or balance) and attaches a PayMongo Source to it rather than inserting a duplicate; `addCustomerBalancePayment` lets a customer split their own remaining balance into instalments via the same `add_booking_payment` RPC.
- **`miscSale.service.ts`** — `createMiscSale` resolves either a catalog item (server-snapshotted price, never trusted from the client) or a freetext description+amount, applies credit, resolves the payment method, and inserts a `transaction` with `transaction_type = 'miscellaneous_sale'` plus its single line item. `updateMiscSale`/`deleteMiscSale` back the Admin-only management page, always recomputing totals server-side.
- **`bookingTransactions.service.ts`** — `listBookingTransactions`/`listBookingGroupTransactions`: every payment recorded against one booking (or group), oldest first — the read behind `BookingPaymentsPanel`.
- **`creditStub.service.ts`** — despite its name (kept for import-path stability), this is the real credit lookup/redemption code checkout and misc-sale call into. Documented under Credits' own Code Guide ([[M10-credit-balance-management]]) rather than here, since it's genuinely part of the credit ledger, just colocated in this folder.

### Types & validators

- **`billing.types.ts`** — server-side shapes: `Transaction` (including `booking_group_id`, `initiated_by`, `payment_choice`), `TransactionLineItem`, `DraftLineItem` (the pre-persisted shape every line-item source produces), plus the feature's role lists (`BILLING_STAFF_ROLES`, `BILLING_ADMIN_ROLES`) and `COUNTER_PAYMENT_METHODS`.
- **`modules/validators/billing.validator.ts`** — Zod schemas for checkout (single and group), misc-sale create/update, recording a counter payment, paying with credit, and adding a balance payment. `validatePaymentShape` is the shared refinement enforcing bank_name only for Bank Transfer, cash_tendered only for Cash, and online_channel only (and required) for GCash/Maya.

## How it connects

A completed booking already carries a `Pending` `booking_payment` transaction from [[M03-appointment-booking|booking creation]]; `CashierCheckoutPage` loads a preview of what checkout would actually charge (recomputed from the booking's real line items, categories via [[M04-grooming-management|M04]]–[[M07-health-veterinary-management|M07]]), replaces that estimate with the real transaction on submit, and rolls the booking's `payment_status` back up. Discounts/promos come from [[M12-discount-management|M12]]/[[M13-maintenance-packages-services-promos|M13]]; credit redemption is delegated to [[M10-credit-balance-management|M10]]'s ledger via `creditStub.service.ts`. A `Pending` GCash/Maya `'portal'` charge is only ever confirmed by the PayMongo webhook, never a cashier click. Every settled transaction feeds [[M14-report-management|M14]]'s daily sales reports.

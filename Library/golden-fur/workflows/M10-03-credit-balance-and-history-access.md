---
title: "M10 · Credit Balance & History Access"
date: 2026-08-26
tags: [architecture, golden-fur, workflow]
project: golden-fur
module: M10
---

# M10 · Credit Balance & History Access

**Actors:** Customer (self-service), Cashier, Admin, Superadmin
**Code:** `server/src/features/credits/services/creditBalance.service.ts`,
`server/src/features/credits/credits.controller.ts`,
`server/src/features/credits/modules/validators/credits.validator.ts`
**Part of:** [[M10-credit-balance-management|M10 · Credit Balance Management]]

`GET /credits/balances` and `GET /credits/history` are a single
role-branching endpoint pair, open to both customers and staff behind plain
`jwtMiddleware` — who is actually allowed to see whose balance is resolved
inside the service layer, not by separate route surfaces.

```mermaid
flowchart TD
    A(["START: GET /credits/balances\nor GET /credits/history"]) --> B{"Request authenticated?\n(jwtMiddleware)"}
    B -- "No" --> C(["END: Blocked — unauthorized (401)"])
    B -- "Yes" --> D{"Query params valid?\n(customer_id optional;\nbranch_id required for /history)"}
    D -- "No" --> E(["END: Blocked — invalid query (400)"])
    D -- "Yes" --> F{"Does the requester\nhave a staff role?"}
    F -- "No (customer)" --> G{"customer_id provided\nAND differs from requester?"}
    G -- "Yes" --> H(["END: Blocked — forbidden (403)\ncustomer cannot view another customer's credit"])
    G -- "No" --> I["Target customer = requester"]
    F -- "Yes (staff)" --> J{"Staff role in\nSuperadmin / Admin / Cashier?"}
    J -- "No" --> H
    J -- "Yes" --> K{"customer_id\nprovided?"}
    K -- "No" --> L(["END: Blocked — customer_id is required (400)"])
    K -- "Yes" --> M["Target customer = customer_id"]
    I --> N{"Which endpoint?"}
    M --> N
    N -- "/credits/balances" --> O["Query credit_balances\nwhere customer_id = target,\nordered by branch_id"]
    O --> P(["END: Returns balances array\n(one row per branch, may be empty)"])
    N -- "/credits/history" --> Q["Look up credit_balances row\nfor (target, branch_id)"]
    Q --> R{"Balance row exists\nfor that branch?"}
    R -- "No" --> S(["END: Returns empty history array\n(not a 404)"])
    R -- "Yes" --> T["Query credit_transactions\nfor that credit_balance_id,\nnewest first"]
    T --> U(["END: Returns full issuance/redemption/\nexpiry history for that branch"])
```

## Notes

- A customer with no staff role can only ever resolve to themself — passing
  someone else's `customer_id` as a customer is a 403, not silently ignored.
- A staff caller who lacks a recognized credit role (`Superadmin`, `Admin`,
  `Cashier`) is forbidden even though they're authenticated staff —
  deliberately narrower than the wider Supervisor/Receptionist set
  [[M08-sales-billing|M08]]'s own billing read roles include, per the
  code's own comment referencing AC-3.
- `/credits/history` always scopes to exactly one branch (`branch_id` is
  required, unlike `/credits/balances` which returns every branch a
  customer has a row for) — this matches the branch-lock:
  `credit_balances` is `UNIQUE(customer_id, branch_id)`.
- A customer/branch pair with no `credit_balances` row yet returns an empty
  array from `/credits/history`, not a 404 — "never had credit at this
  branch" and "had credit and it's all been consumed" look the same at the
  balances level, but history additionally distinguishes them by simply
  being empty either way at the row-lookup step.
- RLS policies on both tables (customer reads own row via `auth.uid()`;
  Cashier/Admin/Superadmin read any) exist as a second line of defense
  behind this application-layer authorization — both were read from
  `supabase/migrations/20260805096_m10_create_credit_balances_schema.sql`
  and `...097_m10_create_credit_transactions_schema.sql`.

## Relationship to other modules

Backs the customer portal's own balance view
([[M02-customer-portal-pet-management|M02]]) and the Credit Management page
used by Cashier/Admin.

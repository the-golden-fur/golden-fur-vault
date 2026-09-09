# Session request — 80-simplify-mark-as-paid-modal

Transcribed from the chat message that started this session.

> Simplify cashier account > transaction > mark transaction as paid modal:
>
> - Currently there's 2 payment fields
> - What is amount to collect for?
> - What is cash tendered for?
> - Simplify and merge, 1 field only and that's the field how much the
>   cashier/customer is going to pay against the transaction
> - You can omit the change label
>
> (see Projects/golden-fur/shared/context/Architectural-Change-History.docx
> for full task context)
> commit new arch changes file in the end

## Decisions taken during planning

1. **Field label:** "Amount paid (PHP)" — neutral wording that reads for
   both the customer ("how much I'm paying") and the receptionist ("how much
   this customer is paying").
2. **Scope expansion:** the customer's own Pay modal
   (`/portal/transactions`, "My Transactions" /
   `CustomerTransactionHistoryPage`) — which had no amount field and always
   paid the full transaction — also gets the single "Amount paid" field,
   **editable for the "Account credit" method only**. For GCash / Maya the
   field is shown disabled and locked to the full amount; a true partial
   payment there needs PayMongo-webhook work and is deliberately out of
   scope.

## Task source

The item is line ~20 of `Architectural-Change-History.docx`
("Development" section):

> Simplify cashier account > transaction > mark transaction as paid modal:
> Currently there's 2 payment fields / What is amount to collect for? / What
> is cash tendered for? / Simplify and merge, 1 field only and that's the
> field how much the cashier/customer is going to pay against the
> transaction / You can omit the change label
> — owner: Matthew

The user moved this item to "Merged" in the docx themselves and committed it
on the vault branch `docs/arch-change-simplify-mark-as-paid` (commit
`c054f4e`), alongside a copy of the pre-PR code review.

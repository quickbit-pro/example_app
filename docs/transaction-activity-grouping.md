# Activity transaction grouping

Activity shows one expandable summary per operation. Each underlying record
remains available with its own receipt link. Daily counts count the summaries.
The raw API response, persisted display cache, transaction records, and exports
are unchanged.

## Matching

Explicit transaction group and parent IDs take precedence. Existing Equals
box/order duplicate detection and card/service-fee links are retained, with
original records now accessible on expansion. Card and wallet funding views
can also join by an unambiguous provider or client transaction reference.

Read-only inspection of the reported September 4 Hoppa history confirmed two
legacy shapes without complete references. Their fallbacks are deliberately
restricted and require a unique match in both directions:

- An Equals exchange credit without an order joins an order's funding debit
  in the same budget, booked within one second, only when that order also has
  an FX/exchange record with the matching buy currency and amount. Both ledger
  legs must be settled. The FX summary can arrive later than its ledger legs.
- An Interlace wallet debit and card unload must both carry provider event type
  `3`, with equal amount/currency/status, compatible account/card/wallet scope,
  and timestamps within one second.
- A legacy `card_topup_fee` can join a top-up booked within two seconds when the
  top-up explicitly reports that exact fee and both entries are settled.

Ambiguous or incomplete matches remain separate. Grouping uses the visible,
scoped rows, so filters cannot reveal entries outside the selected scope.

The summary uses the principal transaction amount, never a sum of duplicate
or cross-currency ledger legs. Top-up summaries retain the amount credited to
the card. Matched wallet views of card funding are excluded from net-flow
accounting; standalone wallet movements and genuine fees remain included.

## Validation

Regression coverage includes anonymized versions of the reported FX, unload,
and top-up shapes, ambiguous matches, mismatched currency/status/budget/time,
missing parents, fee accounting, and original record preservation. Hoppa
screen tests cover collapsed and expanded layouts at 375 and 1200 pixels;
separate widget tests cover each record's receipt callback.

Deployment uses each application’s existing release scripts. No customer
ledger mutation or database migration is required by this fix.

The focused grouping/totals/receipt/cache suite passes 49 tests, and all 18
localization tests pass (67 distinct tests). Analysis of all changed Dart
files is clean. The broader inherited layout suite has five
failures (four large-text app-bar clipping checks and one failed-withdrawal
status overflow), reproduced with the original screen from HEAD.

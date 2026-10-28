# Activity transaction grouping

Activity shows one summary per operation. Matched fees appear in the main
transaction's details, not as list rows or expanded children. Non-fee related
records remain available on expansion. Daily counts count the summaries.
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

The all-activity summary includes charged fees in the source currency, never a
sum of duplicate or cross-currency ledger legs. A top-up of $15.67 with a $0.24
fee shows a $15.91 source deduction; details retain the card credit and fee.
Selected card/account views retain their own ledger leg. An exchange with
explicit sell metadata uses the sell amount plus same-currency fees and keeps
the received amount in details. Declined purchases show only charged fees.
Account/card boundaries apply before grouping; search, date, direction and
type filters apply to the group so they cannot detach a fee from its parent.
Matched wallet views of card funding are excluded from net-flow accounting;
standalone wallet movements and genuine fees remain included.

The Equals API presentation preserves an unambiguous `relatedCreditId` from a
duplicate webhook fee when it keeps the authoritative activity record. This
enriches response metadata without mutating tracked entities or stored ledger
records. Missing or ambiguous links remain visible as standalone fees.

## Validation

Regression coverage includes anonymized versions of the reported FX, unload,
and top-up shapes, ambiguous matches, mismatched currency/status/budget/time,
missing parents, fee accounting, and original record preservation. Hoppa
screen tests cover collapsed and expanded layouts at 375 and 1200 pixels;
separate widget tests cover each record's receipt callback.

Deployment uses each application’s existing release scripts. No customer
ledger mutation or database migration is required by this fix.

The October fee-presentation checks pass 60 Flutter tests covering grouping,
fees, totals, receipts, account menus and mobile/desktop layouts, plus 18 API
fee-deduplication and metadata-link tests. Analysis of all changed Dart files
is clean. The previously checked broader inherited layout suite has five
failures (four large-text app-bar clipping checks and one failed-withdrawal
status overflow), reproduced with the original screen from HEAD.

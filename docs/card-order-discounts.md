# Card order discounts

The Flutter order screen uses the existing app surfaces and theme. Customers can validate a discount code, see original and discounted issuance/monthly/yearly prices (including tier overrides), and review the same prices before accepting the order. Editing a code invalidates the old validation; only a successfully applied code is submitted. Fixed discounts specify the final fee, including zero.

The mobile backend exposes `POST /api/v1/mobile/cards/discount-codes/validate` with `{ "code": "SAVE" }`. It derives the user from the authenticated session and forwards to the company-scoped `POST /api/v2/discount-codes/validate` in CryptoCardPlatform.NET. That endpoint uses the same discount service as the dashboard and verifies company ownership of the user. Validation does not consume a code; card creation remains authoritative.

Issued-card details show the backend's persisted `discountCode`, including after loading a cached card. Cards without a code do not display a discount row.

Deploy the CryptoCardPlatform.NET API changes (public validation endpoint and card response field), then the mobile backend and Flutter builds together. No database migration is needed.

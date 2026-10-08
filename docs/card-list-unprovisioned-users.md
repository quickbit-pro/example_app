# Card lists before account provisioning

Hoppa returns HTTP 404 with `code: "ACCOUNT_NOT_FOUND"` when an existing user
does not yet have the account link required to list cards. This replaces the
previous generic HTTP 500 for that condition.

For `GET /api/v2/cards` only, the shared Hoppa client recognizes that exact
404 error and supplies `{"cards":[],"total":0,"pageTotal":0}`. Mobile card
listing and admin customer synchronization can therefore represent the
unprovisioned state as an empty collection.

Flutter also accepts the explicit 404 code directly or inside the older proxy's
JSON-encoded ProblemDetails `detail`. Empty lists do not trigger card artwork
or tier requests.

Missing users, ambiguous `USER_OR_ACCOUNT_NOT_FOUND` errors, authentication
failures, malformed errors and HTTP 500 responses remain failures. This handling
does not apply to card creation, card details or other endpoints.

Deploy the Hoppa API fix to eliminate the production 500 responses. The app
changes do not suppress the old generic 500 or provision provider accounts.

# Standalone MOR portal contract

Implementation: `mor_vue/` in this repository. The existing `admin_vue/`
application has no MOR routes, imports, sidebar items, or changed files.
Reference: https://mor.hoppa.global/mor and the Hoppa `user_simple` dashboard source.

## Role boundaries

The portal has its own login, session storage, router, layout and build:

| Verified Hoppa role | Landing page | Visible functionality |
| --- | --- | --- |
| `white_label_admin_mor` | `/mor` | Overview, KYB, wallets, transactions, users, cards, account security |
| `user_simple` | `/simple` | Assigned cards and balances, per-card transactions, load requests, freeze/unfreeze, secure details, account security |

There is no role selector, general admin console, or parent-company provisioning
page. Frontend route guards return each role to its own landing page when it
tries the other role's route. API authorization independently enforces the same
boundary. Ordinary local `Admin` or `User` claims do not imply either MOR role.

Authentication reuses `/api/v1/auth/login`, `/login/2fa`, `/logout` and the
backend's existing password, account-connection and two-factor services.
`GET /api/v1/mor/session` resolves the signed `hoppa_user_id` against company user
metadata from `/api/v2/mor/public/transactions?page=1&pageSize=1`. That metadata
includes all company users regardless of transaction pagination. Only the exact
MOR roles are accepted. Missing mapping, another company's user, a company without
`mor_enabled = true`, or an unrelated upstream role cannot grant access. Provider errors are not
converted to successful identity responses. Membership is checked on each API
request and only reused within that request.

Invited users can use **Connect your MOR account** on the login page, which
reuses the existing email account-claim flow. Enable
`Company:Features:ExistingAccountClaimEnabled` on the backend for this flow.
No local password or identity is created merely from a submitted email address.

## Backend routing

Vue data requests go only to the configured sample backend. No Hoppa credentials
or direct Hoppa data API calls are in the browser. Hosted secure card widgets use
HTTPS iframe URLs obtained through the backend.

MOR admin routes use `/api/v1/mor/admin/*`, protected by `MorAdmin` authorization.
Most forward to the equivalent `/api/v2/mor/public/*` resource:

| Method | Local resource | Source / behavior |
| --- | --- | --- |
| GET | `context` | Verified company capability; local installation display name |
| GET | `overview` | Projection of cards, wallets, onboarding and transaction user metadata |
| GET | `onboarding-status?refresh=true` | Existing public onboarding status |
| POST | `kyb`, `cardholder` | Existing public verification/cardholder operations |
| GET/POST | `users` | Filtered `user_simple` metadata / existing public creation |
| GET | `cards`, `cards/available`, `cards/analytics?days=30` | Portfolio, merchant-tier products, analytics |
| POST | `cards/batch` | 1–20 cards; preserves partial results |
| POST | `cards/{id}/assign`, `/unassign`, `/cancel`, `/load`, `/unload` | Existing public services |
| GET | `cards/{id}/secure-widget` | Existing public widget; no-store |
| GET | `users/{id}/cards` | Existing assigned-card summary |
| GET | `wallets`, `transactions` | Existing public reads |
| GET | `wallets/quantum-topup/estimate` | Reuses `/api/v2/cards/quantum-topup/estimate` |
| POST | `wallets/crypto-to-quantum-transfer` | Reuses `/api/v2/transfers/crypto-to-quantum-transfer` |

Creating a user requires `email`, `firstName`, `lastName`, `phone`, and `password`.
The phone number must include its international country code with `+` and no
spaces, for example `+38640123456`. The sample backend validates and forwards
`phone` to Hoppa, which validates the mobile number and saves it for the existing
email-and-phone password recovery flow. This does not mark the phone as verified.

Quantum funding derives the merchant admin ID from scoped metadata; the browser
cannot supply it. Destination currency is USD. Cards stay gated until KYB passes
and the company cardholder has an ID and ACTIVE/APPROVED/PASSED status. Analytics
accepts 7–90 days. Transactions whitelist page, pageSize, userId, status and type.
Partial bulk orders show created/requested counts and errors without retrying.
Cancellation retains Hoppa's zero available, pending and frozen balance checks.

The prior parent provisioning backend remains separately under
`/api/v1/admin/mor/companies` with the existing local admin policy and upstream
parent-key checks. It is not part of either portal role or its browser API allowlist.

## Cardholder API

All routes below require `MorUser` authorization. The actor comes only from the
signed session. No browser userId/companyId/query can override it. Each card
action rechecks assignment; other users' cards are rejected before forwarding.

| Method | Local path under `/api/v1/mor/user/cards` | Upstream |
| --- | --- | --- |
| GET | root | `/api/v2/mor/public/users/{signedUserId}/cards`; returns cards and capabilities |
| POST | `/{cardId}/freeze` | `/api/v2/cards/{cardId}/freeze?userId={signedUserId}` |
| POST | `/{cardId}/unfreeze` | `/api/v2/cards/{cardId}/enable?userId={signedUserId}` |
| POST | `/{cardId}/widget` | `/api/v2/cards/{cardId}/widget?userId={signedUserId}` after local identity verification |
| GET | `/{cardId}/transactions?limit=25&offset=0` | `/api/v2/mor/public/users/{signedUserId}/cards/{cardId}/transactions` |
| POST | `/{cardId}/load-requests` | `/api/v2/mor/public/users/{signedUserId}/cards/{cardId}/load-requests` |

Both user-scoped routes are published in the staging OpenAPI as of 2026-09-10.
Assigned-card history was verified with a live read; the load-request contract
matches the local adapter without submitting a real request.
`Mor:UserTransactionsEnabled` and `Mor:UserLoadRequestsEnabled` default to true.
An explicit false disables the corresponding feature: buttons indicate
unavailability and direct endpoint calls return 501. No mock data is used by
the app.

Transactions expect `{data,total,limit,offset}` with the existing simple-card
transaction fields. Load requests accept `{amount,note}` and return the existing
request summary including `adminEmailSent`; allowed amount is 0.01–250000 and
note length is at most 500. These requests do not fund cards directly.

Secure widget requests accept `{currentPassword,code?}`. The backend verifies
the current local password and TOTP when enabled, with rate/attempt limiting,
before requesting a widget. Passwords/codes are never sent to Hoppa. Responses
are no-store; widget URLs are redacted in provider logs. The browser clears
credentials and destroys the iframe on close. This reuses local authentication
instead of relying on the upstream API-key widget endpoint to perform step-up.

## Installation setup

Use the installation's existing Hoppa API key for a Company/WhiteLabel with
`mor_enabled = true`. Store it in server configuration; no credentials are
included in this export. No additional API key, company ID or KYB `profileId`
is needed to authorize the portal. Sign in with linked MOR-admin/cardholder
accounts and configure the portal origin in `Cors:AllowedOrigins`.

Verify provider-backed login, KYB and card operations in the customer's test
environment before deployment. Local builds and automated tests do not verify
live provider access or perform funding, account provisioning or card actions.

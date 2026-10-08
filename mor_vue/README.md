# MOR portal (Vue)

Standalone application for two Hoppa roles. It has its own build, router, layout,
login and browser session (`mor_vue.auth`), separate from `admin_vue`.

- `white_label_admin_mor` → `/mor`: overview, KYB, wallets, transactions, users and cards.
- `user_simple` → `/simple`: assigned cards, balances, history, load requests,
  secure details and freeze/unfreeze.
- Both roles have `/account-security`, using the existing backend password/2FA APIs.

No general administration or parent-company provisioning navigation is included.
Login calls the existing sample backend authentication API, then
`GET /api/v1/mor/session` verifies the linked user's actual MOR role and company
membership. Users cannot choose or elevate their role in the browser.

## Run

```sh
npm ci
npm run dev
```

Open http://127.0.0.1:5184. The default backend is http://localhost:5188.
The backend needs its existing database configuration (`ConnectionStrings:NeoBankingDb`)
to start.
Copy `.env.example` to `.env.local` to change the backend URL or public branding.
For deployment, build with `npm run build`, serve `dist`, configure an SPA fallback
to `index.html`, and allow the portal origin in backend `Cors:AllowedOrigins`.
The API key belongs only in server configuration, never in this app.

## Backend setup

Use the existing Hoppa API key for the installation’s Company/WhiteLabel with
`mor_enabled = true`. Company and WhiteLabel are the same tenant; no additional
API key or company ID is needed. `profileId` identifies a KYB profile, not a tenant
credential. Existing local accounts must have verified Hoppa user mappings. The login page includes
the existing email account-connection flow (enable
`Company:Features:ExistingAccountClaimEnabled` on the backend); local `Admin`/`User` role labels alone
do not grant portal access.

`/api/v1/mor/admin/*` requires verified `white_label_admin_mor` membership.
`/api/v1/mor/user/cards*` requires verified `user_simple` membership and derives
all actor IDs from the signed session. Card actions recheck assignment. Secure
details require the local password and, if enabled, the current TOTP code.
The public provider widget API is called only after that verification.

Cardholder transaction history and load requests are published in the staging
Hoppa API and enabled by default. Assigned-card history was verified with a live
read on 2026-09-10; the load-request schema matches the adapter, but no real
request was submitted. To disable either feature explicitly, set its backend
flag to false:

```json
{"Mor":{"UserTransactionsEnabled":false,"UserLoadRequestsEnabled":false}}
```

No simulated data or successful responses are substituted in the real app.
See `../docs/mor/api-contract.md` for paths and validation notes.

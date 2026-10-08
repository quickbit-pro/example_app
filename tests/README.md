# Validation Tests

This directory contains repository-level validation checks owned by Worker 4.

Current coverage:

- Static scaffold assertions for the Flutter mobile KYC flow.
- Static scaffold assertions for the Vue admin route guard and backend API client.
- Full feature coverage assertions across backend auth, onboarding, KYC, KYB, accounts, balances, budgets, tiers, cards lifecycle, banking transfers/payees, payments, transactions/export/sync, wallets/assets, audit/admin settings, Hoppa proxy, Flutter, and Vue seams.
- Full-flow assertions that fail when any requested KYC, KYB, tier selection, card-tier resolution, card ordering/lifecycle, EqualsMoney, providers, budgets, Interlace wallet/asset/deposit-address/balance, payment, payee, transfer, transaction export/stats/sync, or admin resource coverage is missing.
- Hoppa OpenAPI coverage assertions using `/Users/rok/Downloads/cryptocard-platform-api_staging.json` when present, plus Vue source-operation checks against that document and an explicit required Vue source-operation matrix.
- Backend-only Hoppa assertions that block direct Hoppa staging URLs, Hoppa API key material, direct vendor hosts in Flutter/Vue source, and direct Hoppa client/header usage in API controllers.
- SumSub route assertions for `POST /api/v1/mobile/kyc/sumsub-token`.
- Admin/user route separation assertions for backend controller policies and frontend API route usage.
- Documentation assertions for the modern neo-banking UI/UX review checklist: clear overview, intuitive onboarding, simple money movement, card controls, EqualsMoney/Interlace status clarity, and admin dashboard density/readability.
- Documentation assertions for the validation plan.

Backend contract and integration tests should be added here once the backend solution is available.

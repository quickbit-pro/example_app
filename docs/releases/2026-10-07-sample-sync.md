# October 7 customer app update

Source: `quickbit-pro/sample_mobile_app` at `f8e0aaac`, including its local
changes captured on October 7, 2026. The previous export used `263bb090`.
Source Git history, deployment credentials and private deployment files are not
imported. Existing customer branding is retained.

## Included changes

- Ask AI concierge: voice input, departure lookup, trip preferences, saved chat
  history, cited recommendations and private account-activity analysis.
- Biometric/passkey recovery, password-reset improvements and onboarding progress.
- Automatic card top-ups, card balances, positive-balance wallet guidance, and
  card-order verification gates and review dialogs.
- Customer-specific tier availability, plan inclusions, and EqualsMoney identity
  verification and document guidance.
- Grouped transaction activity and international receiving IBAN selection.
- Referral eligibility and community partners.
- Admin transaction ledger, KPI reporting, customer stages, reminders and AI
  insights; MOR user phone numbers for account recovery.
- Tests and the rebuilt single-file offline customer guide.

## Bill-splitting exclusion

Receipt and total bill splitting are absent, including screens, routes, entry
points, guest invitations, receipt scanning, payment tracking, guest wallet
bundles and bill database objects. Ordinary peer payments remain available.

The assistant and admin insights use an independent `OpenRouterOptions` class.
Admin reminder links use `AdminReminders:AppUrl`; there is no bill-service URL
fallback. Migration designers and the model snapshot omit the bill entities and
bill-specific user/peer-payment fields.

## Database and configuration

Apply the four new migrations using the existing customer migration procedure:

- `20260923120000_AddActivationProgress`
- `20260923130000_AddAssistantUsageReservations`
- `20260925075741_AddAdminTransactionLedger`
- `20260925095413_AddAdminTransactionStatusReason`

Do not import the source app's `AddHoppaBillSplitting` migration. This export
upgrades the existing example-app schema directly. The relational tests verify
migration execution and that the final model has no pending changes.

All committed API-key, JWT signing-key, webhook-secret and bearer-token values
are empty. Configure your own credentials in server environment variables or an
ignored local configuration file. Never put provider keys in Flutter defines or
`VITE_` variables. Customer signing/Firebase files and production settings are
ignored by Git. The export check scans known credential formats and checks
credential fields in committed configuration; synthetic privacy-test fixtures
are excluded from the pattern scan.

Both `Assistant:Enabled` and `AdminInsights:Enabled` default to false. To enable
AI, set `OpenRouter__ApiKey` in the server secret store and configure
`OpenRouter:Model` for your supported provider. The inherited model default is
`deepseek/deepseek-v4.1-flash`. Configure the assistant's daily/per-minute/global
limits, and enable `Assistant:RecommendationLinksEnabled` only when desired.
Apply migrations before enabling the assistant. With the assistant disabled,
the app retains local help; admin insights can use their deterministic fallback.

For browser dictation/location, serve the app over HTTPS and allow
`microphone=(self)` and `geolocation=(self)` in its Permissions-Policy. Allow
sufficient reverse-proxy time for the assistant's 90-second request deadline
(for example, a 120-second read timeout). Device permission is still required.
Use the customer onboarding guide for the rest of the server setup.

Set `AdminReminders:AppUrl` to the customer's HTTPS app URL before sending
reminders; it defaults to empty and sending is blocked until configured.
Set the customer's actual admin/MOR origins in `Cors:AllowedOrigins`; the
committed examples use local development origins.

## Validation

- Backend: 880 passed, 8 skipped. Disposable PostgreSQL tests covered migrations,
  onboarding concurrency, assistant quotas, reporting, referrals and nicknames.
  The remaining skips require separate support/session/statement fixtures.
- Admin and MOR production builds/typechecks passed; 89 admin tests passed.
- Guide and browser-script checks: 85 Node tests passed; 41 Python tests passed.
- Flutter analysis: no errors or warnings; three inherited informational lints.
- Flutter full suite: 2,125 passed, 50 skipped, 29 failed. All 29 failing test
  names were reproduced in the source checkout: 11 translation-catalog checks
  (local verification copy currently covers English/German), four outdated
  assistant-branding expectations, two activation goldens, and 12 existing
  transaction-layout/money-dialog failures. No export-only failures were found.
- Offline guide release build passed and packaged 312 Flutter files. Interactive
  browser/physical-device behavior was not manually verified during this sync.
- `python3 scripts/validate-customer-export.py` and `git diff --check` passed.

No customer database or deployed application was changed by this update.

# September 22 customer app update

Source: `quickbit-pro/sample_mobile_app` at
`263bb090` (September 19, 2026). This export previously used
`798d1b7` for application code, with later customer-guide updates.

## Included changes

- Durable referral sign-up quotes and attribution, referral administration,
  member status and analytics, residence restrictions, and optional reward caps.
- Password keyboard recovery and sign-up validation fixes.
- Cached Home/activity recovery, bounded read retries and service-worker updates.
- Hosted KYC reopening and missing document issue-date explanations.
- Empty card lists for accounts awaiting provisioning; admin card refresh.
- Unique member nicknames and nickname-based peer lookup.
- Customer synchronization caching, invalidation and failure backoff.
- Card-order discount validation, price breakdowns and persisted code details.
- Separate MOR merchant/cardholder portal and its authenticated backend routes.
- Corresponding automated tests and rebuilt offline Flutter customer preview.

Application source is copied without importing internal Git history. Sanitized
backend settings, customer branding and export documentation are retained.
Internal deployment scripts, database dumps and internal notes are excluded.

## Database and configuration

Apply pending EF Core migrations before starting the updated API:

- `20260915172937_AddDurableReferralSignup`
- `20260918095415_AddUserNicknames`
- `20260919124744_AddCustomerSyncSchedule`

Follow the migration procedure in the customer onboarding guide. Nicknames gain
a unique normalized index; referral delivery state and customer refresh schedules
are persisted. The synchronization worker uses 15-minute freshness and failure
backoff from 2 to 60 minutes; run one reconciliation worker per database.
`appsettings.Example.json` documents the optional `AdminCustomerSync` settings.

The portal setup is in [mor_vue/README.md](../../mor_vue/README.md). Add the
portal's local or deployed origin to `Cors:AllowedOrigins`, and configure the
installation's existing eligible Hoppa API key only on the server. Referral
administration delegation, when enabled, needs installation-specific server
configuration as described in
[REFERRAL_FEEDBACK.md](../../backend/docs/REFERRAL_FEEDBACK.md).

Card discounts require the provider's discount-validation endpoint and card
response fields. See [card-order-discounts.md](../card-order-discounts.md).

## Validation

- Backend: 374 passed, 5 skipped; disposable PostgreSQL covered the three new
  migrations plus referral persistence, nickname claims and sync scheduling.
- Vue: admin and MOR production builds/typechecks passed; 83 admin tests passed.
- Guide/service-worker checks: 60 Node tests passed. Python preview packaging:
  16 passed. Python branding: 25 passed.
- Flutter full suite: 1,807 passed, 50 skipped, 12 failed. All 12 failures were
  reproduced in the source `sample_mobile_app` checkout: transaction-ledger
  layout/filter tests and money-movement dialog tests. They are inherited and
  remain unresolved in this synchronization.
- Flutter analysis reports one inherited informational `prefer_single_quotes`
  lint in `referral_copy_test.dart`; no errors or warnings.
- The offline customer guide rebuilt successfully from the current Flutter
  preview (311 packaged files). Browser policy blocked opening the local HTML,
  so manual visual/export/reimport verification was not completed in this run.

No customer database migration or application deployment was performed.

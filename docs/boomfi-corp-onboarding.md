# Business Exchange onboarding

The mobile API and Flutter app support BoomFi CORP onboarding through the core
Hoppa API. Keep this flow aligned across sample_mobile_app, example_app and
SongsWallet.

## Mobile API contract

All routes require an authenticated user and BoomFiExchangeEnabled. The target
user comes from the session, never the request. Onboarding does not require wallet
outflows. Suppress request/response payload logging, including email codes and
saved company details. Do not cache the business draft.

Base: `/api/v1/mobile/exchange/verification`

| Method/path | Behaviour |
| --- | --- |
| GET `business` | Saved legalName, contactName, contactEmail, contactPhone, issues, readyToSubmit. No provider creation. |
| POST `business` | Create/recover CORP; returns tier, status, verificationUrl. |
| POST `business/authorisation/send-code` | Explicitly request an owner email code. |
| POST `business/authorisation` | Body `{ "code": "123456" }`; require authorised=true before retrying business creation. |

Upstream prefix: `/api/v2/crypto-virtual-accounts/verification`. Deploy the core API
with the GET business draft endpoint before deploying the mobile API/app changes.

## Flutter behaviour

Review saved details, then start business verification. Handle authorisation_required
with an explicit send-code step and code entry. Open/resume the hosted KYB URL and
refresh provider status. A legacy approved Sumsub business verification must not
trigger personal activation or a new personal questionnaire. Personal onboarding
remains on its existing flow. Business actions require businessOnboardingSupported.

The core API reuses the saved Equals Money registered name and the authenticated
owner's contact details. It validates required fields, a valid international mobile-number format and the
50-character legal-name limit. This does not import the broader Equals KYB file
into BoomFi's hosted Sumsub application or grant approval. The legacy phone-verified flag is not required and no phone ownership or SMS
check is performed. The dialog links to support to correct saved contact details.

## EDD documents pending provider agreement

EDD is text-only for now. Do not add document URL fields, publicly accessible files,
signed URLs, document copying or uploads. The core API rejects non-empty file_urls,
including requests from old apps. Reuse of company documents, directors/UBOs and
other KYB information needs a documented BoomFi import/prefill interface and a secure
document-transfer agreement. Do not substitute ordinary email attachments.

## Regression coverage

Run `MobileExchangeControllerTests` in the backend test project and Flutter's
`exchange_business_onboarding_test.dart` plus `exchange_sumsub_reuse_test.dart`.
These use mocks and do not create live provider accounts or send real email codes.

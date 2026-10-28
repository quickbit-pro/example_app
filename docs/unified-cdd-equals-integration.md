# Unified CDD and Equals Money integration

Updated 2026-10-28. This describes the app and its backend, not a replacement for the published Hoppa public API contract.

## Registration and resuming an application

Crypto cards remain included. When the installation enables Exchange or Banking, registration can also select those services. Card-only registration retains the established verification flow. Selecting either additional service starts the unified CDD flow, including proof of address. It does not run the SDD journey first.

Read installation capabilities before offering a service. Enablement of this app path is derived from supported providers; deploying the app does not enable a provider in the company configuration. Existing public API callers and existing card-only users retain their established routes.

Store service selections with the user. The CDD session, questionnaire answers and submission are resumed from server state. Read identity and proof of address from the CDD applicant rather than the legacy card applicant. Reuse collected answers and request only missing details. Preserve the Equals questionnaire, including card interest, card purpose, annual card spending, card quantity and ATM requirements, even when issuing Equals cards is outside the current launch scope.

An approved identity check does not mean every provider has approved the customer. Submit the selected services once; Crypto cards is always included. Render queued, submitting, pending and uncertain outcomes as progress with an appropriate explanation. Do not present an uncertain provider response as a fresh application. Only offer a retry when the server says it is safe. Refreshing a status must not erase questionnaire answers or create a second provider application.

Existing unified applications return to the saved questionnaire or progress view. They must not fall back to the old Banking proof-of-address upload. The engine and Service Bus worker must both contain the corresponding unified CDD implementation. Exchange provider submission is disabled in staging because the provider has no staging environment; that state must never be presented as provider approval.

## App backend routes

These are authenticated routes on the example app backend. They are not URLs for a browser to call directly on Hoppa's public API.

| Action | App backend route |
| --- | --- |
| Read available products and legal settings | `GET /api/v1/mobile/config` |
| Read saved service selection | `GET /api/v1/mobile/onboarding/cdd/preferences` |
| Read CDD application | `GET /api/v1/mobile/onboarding/cdd` |
| Start or resume CDD | `POST /api/v1/mobile/onboarding/cdd/session` |
| Save questionnaire | `PUT /api/v1/mobile/onboarding/cdd/answers` |
| Submit selected services | `POST /api/v1/mobile/onboarding/cdd/submit` |
| Read invite, tier and payment requirements | `GET /api/v1/mobile/onboarding/requirements` |
| Read current agreement status | `GET /api/v1/mobile/agreements/equals/status` |
| Read the approved document | `GET /api/v1/mobile/agreements/equals/documents/{kind}` (`terms` or `privacy`) |
| Record separate agreement acceptance | `POST /api/v1/mobile/agreements/equals/accept` |
| Create and queue forwarding of a complaint | `POST /api/v1/mobile/complaints` |

The dedicated upstream mobile-onboarding contract is an explicit opt-in and is excluded from the general OpenAPI catalogue. Do not advertise it as a transparent migration for all public API integrations. Company credentials stay on the app backend; the backend resolves user and installation ownership. Review the controller and engine contract together when adapting this workflow.

## Invitations, tiers and payment

The personal onboarding gate reads current server requirements before proceeding. It supports requesting an invite, displaying pending approval, redeeming the issued code and continuing after admin approval. It also handles the selected tier and Stripe onboarding checkout. A redirect or a successful button click does not establish payment completion: reload the authoritative requirement state. Do not bypass invite, payment or explicit payment-terms acceptance requirements.

Private API responses, including invite status, must not be served from the PWA offline cache. Existing installed browsers receive the versioned worker and an update prompt.

## Dashboard legal settings

Set these server-owned `Company` properties to the tenant's existing active/default domain entry:

- `DashboardBrandingUrl`: HTTPS public domain-branding endpoint.
- `DashboardBrandingDomain`: exact domain in the returned entry.
- `DashboardCompanyId`: expected company identifier.

The response must match the company, domain, active state and default variant. Legal content is cached briefly. A failed or mismatched dashboard response blocks Equals acceptance instead of silently accepting an older document. Credentials and appsettings overlays remain outside release commits.

Use separate Terms and Privacy controls. Each document opens in a readable dialog; confirmation remains disabled until content loads and the bottom is reached. Confirming review does not tick acceptance. Unavailable documents cannot unlock acceptance. The authenticated agreement gate has its own navigator because it is hosted above the app router; a regression test verifies that Terms can open and close in this placement. Acceptance records document identity/version and the distinct customer actions, and a changed version requires renewed acceptance.

## Payments and Help & Legal

The payee flow displays the returned name-check result, including the provider's returned name when available. A mismatch or unavailable result must not be silently represented as a match; follow the explicit acknowledgement and server validation required by that result.

Payment confirmation uses the quote's fee and total-debit information and shows trusted-payee wording. Email OTP remains the configured delivery method for the email approval flow. Cardeo's existing device/passkey approval implementation is preserved. The engine and the dashboard email template must be aligned for the delivered OTP message to contain the same payment facts.

Help & Legal includes the user's assigned Equals fee schedule, legal documents, safeguarding information and complaints. Fees come from the assigned plan in the existing backend; do not duplicate a price list in Flutter. Quote charges remain authoritative for each transaction. Safeguarding content and terms links must use the applicable programme and region.

Submitting a complaint creates the support record and forwarding job together. The admin can inspect forwarding state and retry failed dispatch. Production forwards through the configured email dispatcher. Staging holds the forwarding job for test review. Queueing is not proof of delivery; retain delivery outcome and operational follow-up.

## Evidence and outstanding sign-off

See [Repeatable evidence capture](equals-evidence-codex-scenario.md) and `scripts/evidence/`. The collector supports screenshots, videos, imported records, timestamps, build provenance and SHA-256 hashes, and generates an index of captured and missing cases. Use the brand's staging profile and synthetic accounts. Unknown profile scope must be resolved before a certification run. Do not capture production customer data as test evidence.

Implementation, successful builds and automated tests are not Equals approval. Complete the applicable happy and unhappy paths, actual payee-result variants, delivered OTP messages with non-zero fees, complaint dispatch, website disclosures and native-device evidence where required. Agree retention periods and demonstrate retained records. Email OTP alone must not be described as satisfying any separate stronger-authentication requirement. Record excluded or deferred card/VoP cases explicitly and confirm scope with the programme reviewer.

No evidence is automatically sent to Equals. The handoff requires a review of recordings and missing cases.

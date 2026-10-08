# Referral customer feedback facade

Both installations expose the explicit engine referral administration resources through `/api/v1/admin/referrals`. Company IDs and API credentials are installation configuration, never query passthrough. Member lifecycle/history/geo endpoints derive the upstream user ID from the authenticated session. Customer support resolves a local customer GUID to its company-bound provider mapping before requesting relationships.

## Signup and consent

1. POST `/api/v1/mobile/auth/referral-quote` with a fresh random `registrationAttemptId`, referral code, source, optional invitation token and locale. The facade stores and returns the authoritative quote unchanged, including localized terms and offered boosts. Repeat requests return the same quote. A different code/source requires a new attempt.
2. Show the quoted terms before consent. Signup supplies `registrationAttemptId`, `referralQuoteId`, `referralTermsHash`, `referralPolicyHash` and explicit `referralAccepted`. The server captures consent reception time. A source label alone never establishes invitation acceptance.
3. Missing/expired/unsupported quotes do not prevent account creation. A requested referral gets an unsent `NEEDS_REVIEW` intent with `QUOTE_CONFIRMATION_REQUIRED`; clients may explicitly choose `referralNeedsReview: true` with `referralAccepted: false`. No referral policy or money reservation is fabricated. Ordinary account validation still applies.
4. Before upstream user creation, persist the signup journal. Commit local user, identity, provider mapping and delivery intents together after the upstream response. No upstream HTTP occurs inside a local database transaction.
5. The worker retrieves a command receipt before posting the immutable command. A lease prevents concurrent local delivery; the engine command ID makes retries safe after a lost response. Only engine `COMMITTED` maps to `APPLIED`. Account-created responses report `PENDING` until confirmed.
6. GET `/api/v1/mobile/auth/referral-attribution` returns only the signed-in user's latest attribution outcome. Admin `/signup-attempts` and `/signup-attempts/{id}` expose tenant-scoped correlation, states and delivery errors, without consent payloads or risk fingerprints.

Upstream account creation currently has no verified idempotent ownership-recovery contract. A lost response or stale `CREATING` journal becomes `CREATION_UNCERTAIN`. Automatic recreation or email-based linking is deliberately unsupported; support must reconcile through authenticated ownership evidence. The unique company/email journal prevents another upstream creation while unresolved. `NEEDS_REVIEW` is an operational outcome, not permission to apply different terms; renewed consent needs a new reviewed quote and command workflow.

## Risk observations

An independent intent records signup observations when referrals are enabled, including accounts created without a referral code. The IP uses the existing nginx trust boundary: a loopback peer may supply its overwritten `X-Real-IP`; other peers use only their actual connection address. A loopback address without a valid forwarded client is an unavailable observation, never a shared fraud fingerprint. An optional resettable UUID `installationToken` is a weak risk observation, not identity proof. Do not reuse analytics identifiers whose disclosure excludes account linking.

The worker attempts observations before attribution commands, without blocking attribution when risk configuration is absent. It uses the stable `signup:{attemptId}` source key. Configuration failures remain visibly pending and retry independently. Raw delivery observations are cleared after terminal processing or after a maximum 24-hour delivery period; the latter becomes `UNAVAILABLE`. Abandoned uncommitted quotes are removed after one day. No raw risk observations are returned through member or support endpoints. Retention for completed signup journals follows the installation's account/audit retention policy and should be configured operationally before long-term production use.

When the accepted engine policy explicitly enables signup checks, the engine independently holds payout until evidence is durably evaluated or unavailable evidence receives an audited review decision. Producer ordering alone does not authorize payout. Milestone contributors follow the same evidence gate.

## Authenticated audit delegation

Configure `Hoppa:ReferralAuditDelegation` only when the matching engine installation trust is configured:

```json
{"Enabled":false,"InstallationId":"application-installation","CompanyId":123,"Secret":"configure-through-secret-store"}
```

The enabled signer requires a secret of at least 32 UTF-8 bytes. It signs the exact outgoing method, path/query, body SHA-256, server-derived authenticated actor ID, company, random nonce and a 120-second expiry. Every retry gets a fresh nonce while preserving the operation idempotency key. Client actor headers are never forwarded. Disabled signing yields the engine's service actor rather than a claimed human actor. Do not log signing secrets or signed delegation headers.

## Exports and rollout

CSV resources use a separate tenant-bound HTTP transport with `ResponseHeadersRead` and a disposable streaming response. They do not pass through JSON buffering or log the exported dataset. Monthly reports require one currency; `asOf` is forwarded unchanged. Opening balances are explicit audited engine operations.

Apply the installation's additive `AddDurableReferralSignup` EF migration before starting the API worker. The two installations have different pre-existing schemas, so each has its own generated migration designer and snapshot. Margin-sharing and subpartner settings are unchanged. Engine capabilities and risk/boost/alert deployment flags remain authoritative.

## Verification

`REFERRAL_FACADE_TEST_POSTGRES` enables the PostgreSQL test fixture. It creates and drops a random isolated database on the specified **test server**. It applies all migrations twice, checks concurrent signup against the unique journal, observes the durable record before upstream HTTP, then races two dispatchers and verifies a single command delivery and raw signal cleanup. Unit tests cover quote immutability, unavailable quote outcomes, missing consent, lost upstream responses, receipt lookup behavior, HMAC byte binding, nonce freshness and declared route filters.

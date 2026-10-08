# Referral program administration

Open **Referral program** in the admin sidebar (`/referrals`).

The page supports public/default and private programs, status and payout rules,
reward levels and ordering, activity and commission periods, fee-minus-cost limits,
private membership with expiry/revocation, and inviter-specific tier/discount offers.
User search returns up to 50 matches; refine the search for additional users.
Private programs do not allow inheritance. New programs start as drafts with zero rewards.

## Request path

`admin_vue` → `/api/v1/admin/referrals/*` in `backend/` → `/api/v2/referrals/*` on Hoppa.

`AdminReferralsController` requires the existing Admin authorization policy and
uses the existing Hoppa proxy/client. `Hoppa:BaseUrl` and `Hoppa:ApiKey` remain
server settings; `x-api-key` is added by the backend client. The browser does not
receive the key or call dashboard APIs. Company IDs and arbitrary client query
parameters are not forwarded. Hoppa resolves company scope from the API key.

The backend exposes these fixed resources:

| Resource | Methods |
| --- | --- |
| `programs` | GET, POST |
| `program` | GET, PUT |
| `overview` | GET |
| `invite-benefits` | GET, PUT |
| `programs/{programId}/members` | GET |
| `programs/{programId}/members/{userId}` | PUT |
| `options` | GET |

`program`, `overview` and `invite-benefits` accept an optional `programId`.
Omitting it selects the public default. `options` accepts `search`.

## Prerequisites and saving

The configured Hoppa API must deploy `PublicCompanyReferralsController` and the
company must have Interlace referrals enabled. The admin backend does not create
its own referral database or bypass Hoppa's eligibility, membership or margin rules.
A missing/disabled public API displays an unavailable message and no editable defaults.

Saves include the loaded revision. A conflict preserves the draft and reports the
API error; reload before editing again. Reward limits must be loaded, including
valid zero limits. Actual payouts are also capped upstream at settled fee minus cost.
Changes are persisted only when an admin presses a save/assignment action.

## Optional per-tier caps

The eligible top-up volume and recurring-reward amount are independent limits.
Program defaults use `null` for **No cap**, while numeric zero is a real zero
limit. Each tier selects **Inherit default**, **No cap**, or **Set amount** for
each limit. Inheriting an unlimited program default and explicitly selecting no
cap have the same effective limit today but behave differently after a default
changes, so the editor preserves that distinction.

The engine contract uses `VolumeCapMode` / `VolumeCapAmount` and
`RecurringRewardCapMode` / `RecurringRewardCapAmount` on each level. Modes are
`INHERIT`, `UNLIMITED`, and `CAPPED`. The engine also returns effective amounts
and their source (`PROGRAM_DEFAULT`, `LEVEL_UNLIMITED`, or `LEVEL_CAP`). The
admin resolves effective values from the current draft while editing; returned
effective values are not used to overwrite draft choices.

The Hoppa facade forwards referral JSON without projecting these fields into a
separate DTO or interpreting null as zero. `ReferralCapContractTests` checks the
actual controller, proxy and HTTP serialization path in both directions.
The connected engine must support this cap contract before publishing an offer
that uses it. No separate Hoppa facade database migration is needed for caps.

Saving a draft does not publish it or enable signup. Publication continues through
the reviewed version endpoint, including its preview hash and idempotency key.
Reviewed drafts require fixed qualification rewards and matching welcome/payout
currencies. The editor checks both before saving or requesting publication;
percentage-of-card-fee qualification rewards remain a legacy-only option.
The engine owns publication checks, attribution, accounting and accepted offer
snapshots. Existing referrals keep their accepted rates and caps; subsequent
default or tier changes apply to new accepted offers. Per-referral lifetime
counters do not reset after a tier edit or refund. An uncapped offer still obeys
its earning window and fee-minus-cost safeguard.

The mobile app displays effective caps from the engine's published offer. Signup
continues to show the engine's immutable quoted terms before consent.

## Verification

```sh
npm --prefix admin_vue run build
node --test admin_vue/tests/referrals.test.mjs
dotnet test backend/tests/NeoBanking.Api.Tests/NeoBanking.Api.Tests.csproj --filter FullyQualifiedName~AdminReferralsControllerTests
```

Frontend tests cover API casing, safe draft defaults, caps for all three reward
calculations, missing/zero limits, level validation and revision-preserving saves.
Backend tests cover the Admin policy, all public proxy paths, allowed queries and
error propagation. Browser verification uses local fixture responses, never live
referral program writes.

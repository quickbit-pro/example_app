# In-app support tickets

Customers open **Settings → Support tickets** to create a request or continue an
existing ticket. Admins use **Support tickets** in the admin navigation to read,
filter, reply, resolve, or reopen requests. Each admin ticket links to its
customer profile in a new tab for quick access to customer details, balances,
and transactions while keeping the ticket and reply draft open.

Tickets use dated correspondence and explicit asynchronous-response copy.
There is no typing indicator, online presence, real-time polling, or promised
response time. Subjects allow 160 characters and messages allow 8,000 characters.
Both clients preserve reply text on submission errors and ticket refresh.

## Workflow

- A new ticket or customer reply sets `awaiting_support`.
- An admin reply sets `awaiting_user` and queues an in-app/push notification.
- Admins can mark a ticket `resolved` or reopen it to `awaiting_support`.
- A customer reply to a resolved ticket reopens it automatically.
- Status changes also notify the customer. Notification previews contain generic
  text; the ticket correspondence is only visible after authentication.
- Notifications link to `/support/{ticketId}`. Push delivery uses the existing
  notification outbox and Firebase configuration. The app inbox works without
  a registered push device.

## API and access control

Customer endpoints are rooted at `/api/v1/mobile/support-tickets`:

- `GET /?offset=0&limit=30`: paginated list of the authenticated user's tickets.
- `POST /`: create with `{ "subject": "...", "body": "..." }`.
- `GET /{id}`: ticket summary and chronological messages.
- `POST /{id}/replies`: reply with `{ "body": "...", "revision": "..." }`.

Admin endpoints are rooted at `/api/v1/admin/support-tickets`, require the admin
policy, and are restricted to the authenticated installation:

- `GET /?status=awaiting_support&offset=0&limit=30`: filtered, paginated inbox.
- `GET /{id}`: ticket details, including customer name and email.
- `POST /{id}/replies`: reply with body and revision.
- `PATCH /{id}/status`: set `resolved` or `awaiting_support`, with revision.

Customers cannot supply the owner or author identity, mark replies as admin, or
read other customers' tickets. Invalid ownership or installation returns `404`.
A ticket revision guards every update. A stale revision returns `409` and asks
the client to refresh while keeping its draft. Reply, status, and notification
outbox changes commit in one database transaction.

## Release

Apply migration `20260908090355_AddSupportTickets` before enabling the updated
clients. It adds `neobanking.support_tickets` and
`neobanking.support_ticket_messages`; existing tables are not modified.
Use the repository's complete-commit deployment process and migration option.
Release the API, admin panel, and Flutter app together. This feature does not
require a new email provider or replace transactional-email templates.

## Verification

Build the admin panel with `npm run build` in `admin_vue` and run the normal
backend test suite. PostgreSQL integration tests create and delete unique
`support_test_*` databases and apply the complete migration history. To include
them, use an isolated local PostgreSQL instance with database-creation rights:

```bash
SUPPORT_TEST_POSTGRES='Host=127.0.0.1;Port=5432;Username=postgres;Database=postgres' \
  dotnet test backend/tests/NeoBanking.Api.Tests \
  --filter FullyQualifiedName~SupportTicketsControllerTests
```

Without `SUPPORT_TEST_POSTGRES`, the three database tests are explicitly skipped;
the authorization-policy test still runs. They cover persisted two-way replies,
resolution and reopening, notification creation, user/installation isolation,
validation, and concurrent updates.

From `mobile_flutter`, run:

```bash
flutter test test/features/support test/features/notifications
```

For a staging smoke test: create a ticket as a customer, reply as an admin,
open the reply notification as the customer, respond again, resolve as admin,
and confirm a further customer reply reopens the ticket.


## Equals complaints

Settings → Help & legal → Complaints provides both customer routes: submit in
this app or open the existing regional Equals complaints procedure. The
forwarding address is not displayed to customers. This route remains separate
from general support and identifies the banking/payment services Equals provides.

`POST /api/v1/mobile/complaints` accepts a stable `requestId`, subject and body.
The authenticated installation/user and account reference come from the session.
The request creates a support ticket and `equals_complaint_forward` email in one
save. Repeating the request ID returns the existing ticket without another email.
The initial email ID equals the ticket ID; follow-ups use the customer message ID.
Existing tables and API contracts are reused; no migration is needed.

Production queues the complete complaint to the address in guidance 1.4,
`complaints@equalsmoney.com`, with programme, account reference and customer
contact information. It does not screen merits. The existing dispatcher retries
transient failures and stores provider acceptance/time. The customer sees queued,
forwarded or needs-attention status; a forwarding receipt is only added after
provider acceptance. That is not proof Equals has resolved or accepted the claim.
Email delivery is at least once: a crash after provider acceptance but before the
database save can resend the same complaint reference.

Staging/development store `staging_preview` and never dispatch these complaints.
Logging and SendGrid sandbox delivery cannot mark them forwarded. A real,
configured sender is required in production; disabled delivery leaves work queued.

The app admin support inbox shows forwarding state. For complaints received as
ordinary tickets, `POST /api/v1/admin/support-tickets/{id}/forward-to-equals`
forwards the full thread with the customer's mapped account reference. It requires
current revision and tenant authorization. Pending/sent repeats do not resend;
failed/held deliveries may be retried explicitly. Customer follow-ups on complaint
tickets are forwarded too. Deploy the admin Vue panel to expose these controls.

Operations must monitor queued/failed/held messages and forward any complaint
received outside this route the same business day. Triage is provider routing,
never a judgment on merit; unclear-provider cases go to Equals. The app must not
be used to resolve a complaint on Equals' behalf. Mail delivery evidence, failure
escalation ownership and the marketing-homepage complaints link still require
operational sign-off. No real complaint was sent during development testing.

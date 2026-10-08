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

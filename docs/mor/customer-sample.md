# MOR dashboard code sample

This repository contains the ASP.NET Core backend, Flutter application, general
admin frontend, and a separate Vue 3 MOR dashboard. This guide focuses on the
MOR dashboard and its shared backend.

The browser calls this backend; only the backend holds the Hoppa API key.
Hosted secure card details open in the provider's HTTPS iframe after backend
authorization.

| Hoppa role | Dashboard | Access |
| --- | --- | --- |
| `white_label_admin_mor` | `/mor` | Overview, KYB, wallets, transactions, users, cards, account security |
| `user_simple` | `/simple` | Assigned cards, balances, history, load requests, secure details, freeze/unfreeze, account security |

The backend verifies role and company membership on each MOR request. A local
`Admin` account alone does not grant MOR access.

## Requirements

- .NET 10 SDK (`dotnet --version`).
- Node.js 22.12 or newer on the Node 22 release line, with npm. The included
  lockfile was validated with Node 22.17.0.
- A running PostgreSQL database and credentials for a **new, dedicated database**.
  The database user must be able to create schemas, tables and indexes.
- A Hoppa API key for your Company/WhiteLabel with `mor_enabled = true`, and
  existing users with the roles above. Company and WhiteLabel mean the same
  tenant. No additional Hoppa CompanyId or API key is needed; `profileId` is a
  KYB identifier.
- Access to NuGet and the npm registry to install dependencies.

Commands below run from the root of this repository. The examples
use a macOS/Linux shell; on Windows use PowerShell's `Copy-Item` instead of `cp`.

## 1. Configure the backend

Copy the configuration template:

```sh
cp backend/src/NeoBanking.Api/appsettings.Example.json backend/src/NeoBanking.Api/appsettings.Local.json
```

Edit `appsettings.Local.json` and fill in:

| Setting | Value |
| --- | --- |
| `ConnectionStrings:NeoBankingDb` | `Host=localhost;Port=5432;Database=mor_sample;Username=YOUR_DB_USER;Password=YOUR_DB_PASSWORD` (use your PostgreSQL host and TLS settings) |
| `Hoppa:ApiKey` | Your Company/WhiteLabel API key |
| `Hoppa:BaseUrl` | Staging is preconfigured; use the matching environment for your key |
| `Jwt:SigningKey` | A unique random secret of at least 32 characters; for example generate one with `openssl rand -hex 32` |
| `Company:Name`, `Company:BrandName` | Your display names |
| `Company:InstallationId` | A stable local installation label, such as `customer-mor`; this is not a Hoppa CompanyId |
| `SeedAdmin:Email`, `SeedAdmin:Password`, `SeedAdmin:DisplayName` | Your own local bootstrap administrator credentials, used only for initialization |

Set `Company:Features:ExistingAccountClaimEnabled` to true to enable
**Connect your MOR account**. Keep Hoppa keys in backend configuration only;
never put them in a `VITE_` variable or a frontend source file.

For local development, set `Email:Provider` to `log`; recovery/verification
messages are then written to development logs. For delivered backend emails, configure
`Email:Provider` as `sendgrid`, its API key and a verified sender. The Hoppa
account-connection OTP is sent by Hoppa and requires working upstream email
configuration. Disable `MarketData:Enabled` and `PushNotifications:Enabled` if those services
are not needed for your local MOR setup.

## 2. Initialize the database

Create the empty database in PostgreSQL first, for example with your database
administration tool. Then restore dependencies and apply the included migrations:

```sh
dotnet restore backend/NeoBanking.sln
dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj --launch-profile http -- --migrate-and-seed
```

This creates the backend schema, its default local company record and the local
bootstrap administrator. It exits when complete. It does not create a Hoppa
company, MOR user, or card. There is no database dump to import.

After initialization, remove `SeedAdmin:Password` from `appsettings.Local.json`.
The bootstrap administrator is for the backend's general administration APIs;
it is not a MOR dashboard login. Use a different email for this account from the
MOR accounts you will connect in step 5.

## 3. Start the backend

```sh
dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj --launch-profile http
```

Keep this terminal open. The `http` launch profile sets the Development environment,
loads `appsettings.Local.json`, and listens at `http://localhost:5188`.

- Health: http://localhost:5188/health
- API reference: http://localhost:5188/scalar/v1
- OpenAPI: http://localhost:5188/openapi/v1.json

Normal startup does not apply database migrations automatically. The API host
runs its existing background services; the separate Workers project is not
needed for this dashboard.

## 4. Start the Vue dashboard

In a second terminal, from the package root:

```sh
cp mor_vue/.env.example mor_vue/.env.local
npm --prefix mor_vue ci
npm --prefix mor_vue run dev
```

Open http://127.0.0.1:5184. The default backend URL is
`http://localhost:5188`. To change it, edit `VITE_BACKEND_API_BASE_URL` in
`mor_vue/.env.local` and restart Vite. `VITE_APP_NAME` and `VITE_APP_LOGO` control
public login branding.

## 5. Connect a MOR account and sign in

1. Make sure the user already belongs to the API key's Hoppa Company/WhiteLabel
   and has `white_label_admin_mor` or `user_simple` role.
2. On the login page, select **Connect your MOR account**.
3. Enter that user's email, request the verification code, enter the code sent
   by Hoppa, and set a local password. This creates the verified local account
   mapping. Existing connected accounts can sign in directly.
4. Sign in using the local credentials (and TOTP if enabled). MOR admins land
   on `/mor`; cardholders land on `/simple`. The role is not selectable.

A cardholder needs an assigned card in Hoppa to see cards. Card ordering is gated
by KYB approval and an active company cardholder. History and load requests are
enabled by default. A load request asks the MOR admin for funds; it does not fund
the card directly. Real card/funding actions use the configured Hoppa environment.

When adding a MOR user, supply their phone number with its country code, including
`+`, without spaces (for example `+38640123456`). Hoppa stores this number for its
email-and-phone password recovery flow.

## Checks and troubleshooting

```sh
dotnet test backend/NeoBanking.sln
npm --prefix mor_vue run build
```

- **Database connection missing / connection refused:** check local configuration,
  PostgreSQL credentials and that the database exists.
- **Table/schema missing:** complete the migration command in step 2.
- **Account connection unavailable (404):** enable
  `Company:Features:ExistingAccountClaimEnabled` and restart the backend.
- **Account already connected:** use its local password or the recovery flow.
- **Login succeeds but MOR access is denied:** verify the user's exact Hoppa role,
  verified local mapping, Company/WhiteLabel membership, and `mor_enabled = true`.
  Do not substitute the local bootstrap admin or a KYB profile ID.
- **Cannot reach API / CORS error:** check `VITE_BACKEND_API_BASE_URL`. Development
  permits localhost origins; deployed frontends require an explicit CORS origin.
- **Upstream 401/403:** check that the API key belongs to the selected Hoppa
  environment and enabled Company/WhiteLabel.

See [the API contract](docs/api-contract.md) for the local routes and role checks.
See [package validation](VALIDATION.md) for checks performed on this source sample.

## Deployment notes

The archive contains source only. Restore/install dependencies before building:

```sh
dotnet publish backend/src/NeoBanking.Api/NeoBanking.Api.csproj -c Release -o publish/backend
npm --prefix mor_vue run build
```

Run the published API with `dotnet publish/backend/NeoBanking.Api.dll`. Set
`ASPNETCORE_ENVIRONMENT=Production`, `ASPNETCORE_URLS`, and backend settings through
your deployment environment or secret store (for example `Hoppa__ApiKey`,
`ConnectionStrings__NeoBankingDb`, `Jwt__SigningKey`, `Company__InstallationId`,
`Company__Features__ExistingAccountClaimEnabled`, and `Cors__AllowedOrigins__0`).
`appsettings.Local.json` is loaded only in Development and is never published.
Use the same signing key and installation settings across restarts.

Set the public API URL in the Vue environment before building. Serve
`mor_vue/dist` with an HTTPS static server and an SPA fallback to `index.html`
for routes such as `/mor` and `/simple`. Put the API behind HTTPS and configure
its CORS origin to the deployed dashboard URL. Apply migrations to the deployment
database before starting the new API version. Development logging email is for
local setup; configure email delivery for customer-facing recovery flows.

`node_modules`, `dist`, `build`, .NET `bin`/`obj`, logs, local secrets and database
contents are excluded from this archive. They may be created locally when you
run installation and build commands.

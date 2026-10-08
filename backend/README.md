# NeoBanking Backend Foundation

Backend solution skeleton for the NeoBanking API.

## Projects

- `src/NeoBanking.Api`: ASP.NET Core API host, authentication, authorization, company context middleware, health endpoint, OpenAPI and Scalar API reference.
- `src/NeoBanking.Application`: application-level primitives such as authorization policy names and company/branding context abstractions.
- `src/NeoBanking.Domain`: framework-free domain constants shared by the backend, including User/Admin roles.
- `src/NeoBanking.Infrastructure`: infrastructure registration hook for future adapters.
- `src/NeoBanking.Workers`: worker host skeleton wired to Application and Infrastructure.

## Run

```bash
dotnet restore backend/NeoBanking.sln
dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj
```

Useful endpoints:

- `GET /health`
- `GET /openapi/v1.json`
- `GET /scalar/v1`
- `GET /swagger` redirects to Scalar

## Customer Implementation Docs

- `../docs/customer-implementation-guide.md`: setup, architecture, frontend/backend boundaries, auth, KYC/SumSub flow, webhook notes, and extension process.
- `../docs/hoppa-api-call-flow.md`: Hoppa proxy request lifecycle, Mermaid flowcharts, endpoint mapping, and example calls.
- `../docs/customer-implementation-guide.md#transactional-email`: SendGrid-backed password reset, email confirmation, and account-connected emails with admin-editable templates.
- `../docs/backend-ubuntu-nginx-deployment.md`: no-Docker Ubuntu deployment plan for `demo-api.roks.dev` and `demo-admin.roks.dev` using Nginx and an external PostgreSQL database.

- [In-app support tickets](../docs/support-tickets.md): workflow, endpoints, migration, and verification.

## Auth and Company Context

JWT bearer authentication is configured from the `Jwt` section in appsettings. The foundation handler supports HS256 tokens with `iss`, `aud`, `exp`, optional `nbf`, and `role` or `roles` claims.

Authorization policy constants live in `NeoBanking.Application.Security.AuthorizationPolicyNames`:

- `authenticated_user`
- `role_user`
- `role_admin`

Role constants live in `NeoBanking.Domain.Security.ApplicationRoles`:

- `User`
- `Admin`

This starter is a single-company, white-label installation. Company and branding values are loaded from the `Company` section in appsettings and exposed through `ICompanyContextAccessor`; there is no tenant header, tenant claim, or runtime tenant isolation policy in the foundation.

Use `CompanyContext` for per-install metadata. Each customer runs their own copy of the sample with one configured Hoppa API key and one company profile.

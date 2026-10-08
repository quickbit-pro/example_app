# Hoppa mobile app

A configurable white-label mobile banking application with its ASP.NET Core API
and Vue administration panel.

## Branding and local builds

[`mobile_flutter/config/hoppa.json`](mobile_flutter/config/hoppa.json) is the
active configuration (icon, font, palette, API base URL). See
[the configuration guide](docs/branding.md).

```bash
./scripts/run-mobile-branded.sh mobile_flutter/config/hoppa.json -d chrome
./scripts/build-mobile-branded.sh web mobile_flutter/config/hoppa.json --release
```

Install the Python branding dependencies as described in [the setup guide](docs/branding.md).
Brand changes require rebuilding. `sample.json` and `sunrise.json` are examples
for other customers. Server installation, database migration and operation are
covered by the interactive customer guide below.

## Customer onboarding

Open or share the single-file [interactive customer guide](docs/customer-onboarding.html)
to configure branding, inspect real Flutter screens with local sample data,
export the app JSON and asset bundle, and generate Linux/PostgreSQL setup
instructions for a separate customer installation. The guide runs offline.

See [customer guide maintenance](docs/customer-guide.md) for the handoff workflow,
scope, validation and the reproducible `./scripts/build-customer-guide.sh` build.

## Repository contents

- `mobile_flutter/`: configurable customer application for Android, iOS, and web.
- `admin_vue/`: the inherited Vue administration application.
- `backend/`: the inherited ASP.NET Core API and services.
- `mor_vue/`: separate merchant and assigned-cardholder portal.
- `scripts/`: branding/build tools and the customer guide builder.

## Validate

```bash
cd mobile_flutter
flutter pub get
flutter analyze
flutter test
```

See [the validation record](docs/validation.md) for the inherited scaffold
validator's existing limitations.

## Public template snapshot

This repository starts from a clean, single-commit snapshot with neutral source
names and customer-configurable artwork. Use `design.layout: "example"` for the
full banking layout. See [snapshot notes](docs/releases/2026-10-08-public-template.md)
for validation and setup. Clone afresh if you used the previous history.

## October 2026 update

The application includes `sample_mobile_app` through `f8e0aaac` plus its local
card-verification, EqualsMoney and MOR changes captured on October 7, 2026.
Bill splitting is excluded. API keys and deployment credentials are not included.
See [the update notes](docs/releases/2026-10-07-sample-sync.md) for migrations,
configuration, and validation, including inherited Flutter test failures.

Run `python3 scripts/validate-customer-export.py` before publishing an export.

## Merchant and cardholder portal

`mor_vue/` has its own login, router, session and build. Verified MOR
administrators use `/mor`; assigned cardholders use `/simple`.
Run `npm --prefix mor_vue ci` and `npm --prefix mor_vue run dev`, then open
http://127.0.0.1:5184. See [portal setup](mor_vue/README.md) and
[API contracts](docs/mor/api-contract.md) for tenant eligibility, role checks
and server configuration.

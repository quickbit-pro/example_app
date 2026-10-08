# Customer branding and installation guide

Share [customer-onboarding.html](customer-onboarding.html) with the customer and
their implementation team. It is one self-contained HTML file, currently about
18 MB (the packaged preview includes every Flutter asset, including the
PDF-export fonts). Open it locally in a recent Chrome or Edge browser; no hosting, account,
package installation or internet connection is needed to use the wizard.
Documentation links open external sites only when followed.

The preview runs the actual production Flutter screens and widgets with local
fixtures. It includes its compiled JavaScript, CanvasKit renderer, fonts and
images. It does not connect to a live API, authenticate a customer, start Firebase
or submit payments. Home, login, cards and profile can be inspected in light and
dark appearances. The splash replay and loader also use production widgets.
Sample issued cards omit artwork supplied separately by the card provider.
The separate preview entrypoint reuses the shipped app's screen layouts and
shared widgets. The guide also includes the shared splash-wordmark fix so its
name renders without Flutter's fallback text decoration.

## Customer workflow

The guide is written for a developer who has never deployed a .NET app or
configured nginx and PostgreSQL: short sentences, every term defined the first
time it appears, and every command block labelled with where it runs
(**Laptop**, **Server** or **Database admin**) plus a "What you should see"
line. Steps 2–5 edit the brand configuration and show the live Flutter preview;
the other steps are reading material generated from the same data.

1. **Before you start:** what the product is (customer app for phone and web,
   admin website, API; one PostgreSQL database; one Ubuntu server; the Hoppa
   platform), an inline SVG architecture diagram, a prerequisites checklist
   grouped by who provides each item (Hoppa, the customer, the developer), a
   time estimate per phase and a legend for the badges and copy buttons.
2. **Brand basics:** choose the public name, support details, legal entity and
   permanent Android/iOS identifiers.
3. **Colors & type:** choose or edit both palettes, typography and shape. Contrast
   feedback helps identify combinations that need review.
4. **Logos & launch:** supply logos, icon, splash/loader artwork and any licensed
   custom font files. Source images and fonts are included in the handoff ZIP.
5. **Connections:** set the public API and app domains, legal URLs and optional
   Firebase client configuration. Server credentials belong on the server.
6. **Run it on your laptop:** install PostgreSQL (or one Docker container),
   create a development database, write `appsettings.Local.json` (each key
   explained), run `--migrate-and-seed`, start the API on port 5188, the admin
   on port 5173 with `VITE_BACKEND_API_BASE_URL`, and the app through
   `run-mobile-branded.sh` with `--dart-define=API_BASE_URL=http://localhost:5188`.
7. **Customize beyond branding:** a repository map, how to change a screen's
   text (`assets/l10n/*.json` rule), how to add a screen and a route
   (`lib/app/routes.dart`, `lib/app/router/app_router.dart`), how the admin and
   API are extended, the real `Company:Features` list from `CompanyOptions.cs`,
   and the release build commands.
8. **Server setup:** generated instructions for a dedicated Ubuntu 24.04 server,
   local or managed PostgreSQL, API configuration, migrations, administrator
   seeding, nginx/HTTPS, verification, backups, updates and rollback, followed
   by a Troubleshooting section and a Glossary. Each section starts with a
   one-paragraph overview and a numbered outline; each step has "What this
   does" and "Watch out" lines. The `pg_hba.conf` change is a script that
   checks the file first, keeps a backup and prints a diff.
9. **Review & export:** download the app's schema-version-1 JSON or the complete
   handoff ZIP. The JSON covers the supported configuration schema, including
   advanced public build defines; the real repository validator is the final
   check before a customer build. The bundle README repeats the structure above
   and adds a "Quick start in 10 steps" list.

The server guide's data model (`CustomerServerGuide.render`) returns sections
with `summary`, `outline`, `steps` and, for the glossary, `terms`. Each step has
`title`, `text`, optional `where` (one of `CustomerServerGuide.WHERE`), `watch`,
`expect`, `code` and `language`. `app.js` renders the same fields into HTML and
into `server-setup.md`.

The ZIP contains `config/brand.json`, its referenced assets and public Firebase
client files, font licenses, `server-setup.md`, a build README and public
`onboarding-settings.json`. Copy its `config/` directory to
`mobile_flutter/config/<brand-id>/` in a separate customer checkout. Paths in the
JSON remain relative to that directory.

Reimport the guide's original handoff ZIP to resume with its configuration,
assets and public server choices. JSON-only import restores configuration;
referenced files must be supplied again. Keep the exported ZIP as the complete
handoff. ZIP resume accepts this guide's uncompressed export format, rather than
arbitrary repacked or encrypted archives. Editing is kept in the current page;
export before closing it.

Follow the generated validation and branded-build commands after unpacking.
Brand changes require a new build and deployment. Review the built app on real
devices, including authentication, loading/error states and provider-backed
flows, before release. Native store accounts, signing, APNs/Firebase ownership,
provider onboarding and credentials are separate setup tasks. The mobile JSON
does not configure the admin's complete color theme or provider-hosted screens.

The server commands describe a **new dedicated customer installation**. They do
not execute from the HTML and have not been run against a fresh Linux host as
part of guide validation. An infrastructure owner must review the generated
values, execute the recipe and complete its acceptance and restore checks.
The default repository URL is `https://github.com/quickbit-pro/example_app.git`;
change it in the Server setup step when the customer uses their own copy.
Before granting customer source access, the delivery team must remove inherited
credentials from both the provided tree and any shared Git history.

Statements the guide could not verify against the code are marked "check with
your Hoppa contact" in the text (the correct Hoppa base URL for a customer, the
set of enabled provider modules, test accounts). The laptop step relies on
`--dart-define` taking precedence over `--dart-define-from-file`; if it does
not on a given Flutter version, the guide tells the reader to edit
`flutterDefines.API_BASE_URL` instead.

## Rebuild the distributable

Use Python 3.10+ and the repository's tested Flutter SDK (currently Flutter
3.44.2 / Dart 3.12.2). Initial Flutter dependency resolution may need network
access. From the repository root:

```bash
./scripts/build-customer-guide.sh
```

The script builds `lib/customer_preview_main.dart` in release mode with no
service worker, packages its output through `package-customer-preview.py`, and
assembles `docs/customer-onboarding.html` with `build-customer-guide.py`.
`scripts/customer-guide/generated/` is an ignored intermediate directory;
the resulting HTML is the file to distribute and commit.

The source parts are:

| Source | Responsibility |
| --- | --- |
| `mobile_flutter/lib/customer_preview/` | Fixture host around production app screens and widgets |
| `scripts/customer-guide/template.html` | Wizard structure and styling |
| `scripts/customer-guide/app.js` | Editing, preview messages and handoff workflow |
| `scripts/customer-guide/config-engine.js` | Supported schema, defaults and validation |
| `scripts/customer-guide/file-tools.js` | Local assets and ZIP import/export |
| `scripts/customer-guide/server-guide.js` | Parameterized Linux/PostgreSQL instructions |
| `scripts/customer-guide/flutter-embed.js` | Embedded Flutter runtime loading and communication |

Rebuild the complete pipeline after changing app screens, shared widgets,
preview fixtures, brand presets or packaged assets so the distributed preview
stays in sync. After guide-only edits, `python3 scripts/build-customer-guide.py`
can reuse an already built preview package; use the complete pipeline for a
release of the guide. Keep configuration-engine changes aligned with
`scripts/prepare-mobile-brand.py` and review server instructions when backend
configuration or deployment requirements change.

Run the focused checks before distributing:

```bash
node --test scripts/tests/test_customer_*.mjs
python3 -m unittest discover -s scripts/tests -p 'test_customer_preview_package.py'
python3 -m unittest discover -s scripts/tests -p 'test_branding.py'
(cd mobile_flutter && flutter test test/customer_preview/customer_preview_test.dart)
```

One engine test and `test_branding.py` import `scripts/prepare-mobile-brand.py`,
which needs Pillow. Point `BRANDING_PYTHON` at a virtual environment created
from `scripts/branding/requirements.txt` (and run the unittest command with that
interpreter) when the system `python3` lacks Pillow. `test_customer_server_guide.mjs`
also checks that every command block has a `where` badge, that the
Troubleshooting and Glossary sections exist, and that no internal deployment
scripts or other customers are referenced.

Also open the generated file, inspect real Flutter screens, change branding,
export and reimport a ZIP, and validate the unpacked JSON/assets with
`prepare-mobile-brand.py --check`. Test the file with networking unavailable to
confirm the preview remains self-contained. These checks validate the guide;
they do not replace testing a customer's build or infrastructure.

The Brand configuration CI workflow runs these checks, rebuilds the guide from
the current Flutter screens and uploads `customer-onboarding-guide` as a build
artifact. Download that artifact for the latest passing build, or distribute the
checked-in HTML after rebuilding locally.

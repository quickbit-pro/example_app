# Configuring a customer app

Hoppa is the active deployment in this repository. Use
`mobile_flutter/config/hoppa.json` for its official identity and existing hosted
API. [Hoppa branding](hoppa-branding.md) records asset sources and palette
choices; [the deployment guide](deploy-hoppa.md) covers the single deployment
command. The reference examples below remain useful for other customers.

`mobile_flutter/config/sample.json` is the complete reference configuration. It
produces **Sample Pay** with teal colors and its own application identifiers.
`mobile_flutter/config/sunrise.json` demonstrates a second brand with a warm
palette, different icon, tighter corners, and a circular loader. Both preserve
the inherited account, card, crypto, onboarding, and settings layouts.

Run these commands from the repository root:

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/branding/requirements.txt
export BRANDING_PYTHON="$PWD/.venv/bin/python"

# Validate only; no files change.
"$BRANDING_PYTHON" scripts/prepare-mobile-brand.py mobile_flutter/config/sample.json --check

# Prepare the selected brand and start Flutter.
./scripts/run-mobile-branded.sh mobile_flutter/config/sample.json -d chrome

# Prepare and build. Supported targets: apk, appbundle, ios, ipa, web.
./scripts/build-mobile-branded.sh web mobile_flutter/config/sample.json --release
./scripts/build-mobile-branded.sh apk mobile_flutter/config/sample.json --debug
```

Flutter, the Android SDK, and Xcode remain the platform build prerequisites.
The Python tool requires Python 3.10+ and Pillow. `BRANDING_PYTHON` selects the
interpreter; it defaults to `python3`. Native release signing is configured
separately with your customer's signing identities and store accounts.

The wrappers generate `.dart_tool/branding/defines.json`, bundle the chosen
artwork and fonts, update native resources and identifiers, then pass the
resulting defines to Flutter. Use the wrappers whenever changing brands. A plain
`flutter run` does not automatically load the JSON. The generator changes files
only in this clone. Because it replaces generated files, run simultaneous brand
builds in separate clones or worktrees.

The sample points to `http://localhost:5000` in development and has Firebase
push disabled. Replace `flutterDefines.API_BASE_URL` with your backend URL.
A phone's `localhost` is the phone; use a reachable development server instead.
Android release builds require an HTTPS API unless you deliberately change the
platform network policy. `APP_FLAVOR` accepts `dev`, `staging`, or `prod`.

## Configuration fields

The JSON has `schemaVersion: 1` and these top-level objects. Unknown keys fail
validation so configuration typos do not quietly become another appearance.
Paths are relative to the JSON file's folder, must remain inside that folder,
and cannot contain `..` or be absolute. Symlinks escaping the folder are rejected.
All input validation runs before generation writes any files.

| Object | Fields | Purpose |
| --- | --- | --- |
| `app` | `name`, `id`, `description`, `themeMode`, `supportEmail`, `supportPhone`, `legalEntity`, `transferDashboardUrl` | App/store display name, brand identity, support information and initial theme. |
| `design` | `layout`, `light`, `dark`, `typography`, `shape`, `assets`, `loader`, `splash`, `motion` | Flutter appearance and web/native launch presentation. |
| `native` | `androidApplicationId`, `iosBundleId`, `icon`, `iconBackground`, `firebase` | Separate installed-app identities, launcher icons, optional customer push configuration. |
| `fonts` | Array of `{family, files: [{path, weight, style}]}` | Additional bundled TrueType/OpenType font families. |
| `flutterDefines` | Object with uppercase scalar keys | Environment settings such as `API_BASE_URL` and `APP_FLAVOR`. These values are compiled into the app; do not put secrets here. |

`app.name` is required, up to 60 characters, and must be safe for native build
configuration. `app.id` is a lowercase identifier such as `sample` or
`customer_one`; it is separate from the native reverse-DNS identifiers.
`app.themeMode` is `system`, `light`, or `dark`. Flutter and the web loading page
honor the customer's saved theme afterward. Native launch screens cannot read
Flutter preferences before Flutter starts: they follow the device when configured
as `system`, or use the fixed configured theme.

`design.layout: "example"` retains the full inherited screen layout while using
the selected branding. This is a compatibility layout name, not a requirement
to display Example artwork. `"generic"` opts into the inherited generic screen
variants; it can change which presentation paths those screens use. Start from
the sample's `example` setting to retain the existing experience.

## Colors, typography, and shape

Both `design.light` and `design.dark` contain semantic colors. Use `#RRGGBB` for
opaque colors or `#AARRGGBB` for alpha first, for example `#18007F78`. The tool
translates alpha ordering for CSS. Native splash and icon background colors must
be opaque.

Required color roles:

| Area | Palette keys |
| --- | --- |
| Surfaces | `paper`, `surface`, `surfaceSubtle`, `surfaceHigh`, `navigation`, `navigationGlass`, `rail`, `glassTop`, `glassBottom` |
| Text | `ink`, `textSecondary`, `textTertiary`, `onFill` |
| Borders | `border`, `borderSubtle`, `borderEmphasis`, `controlEdge` |
| Actions and status | `fill`, `accent`, `success`, `danger`, `warning`, `teal` |
| Effects | `shadowAmbient`, `shadowLift`, `skeletonBase`, `skeletonHighlight`, `sheenPeak` |
| Gradients | `cardStart`, `cardEnd`, `heroStart`, `heroEnd`, `mutedStart`, `mutedEnd` |

Optional roles are `onAccent`, `snackbar`, `atmospherePrimary`, `atmosphereMid`,
`atmosphereSecondary`, `loader`, `cardMiddle`, `cardForeground`, `cardDecoration`,
and `cardOverlay`. They fall back to related configured colors in Flutter. Both
examples set them explicitly. In particular, `cardForeground` is independent of
page text so a dark payment card can remain legible inside a light screen.

`design.typography` accepts `fontFamily`, `monoFontFamily`, and `scale`
(0.75–1.5). The bundled families are `Geist` and `GeistMono`. An empty family
uses the platform/default fallback. For another font, add its files beside the
configuration and declare the family:

```json
"fonts": [
  {
    "family": "Customer Sans",
    "files": [
      {"path": "assets/CustomerSans-Regular.ttf", "weight": 400, "style": "normal"},
      {"path": "assets/CustomerSans-Bold.ttf", "weight": 700, "style": "normal"}
    ]
  }
]
```

Set `design.typography.fontFamily` to `Customer Sans`. Fonts support `.ttf` and
`.otf`, weights 100–900 in increments of 100, and `normal` or `italic`. Include the
font license alongside its source files. The generator adds font declarations
to `pubspec.yaml`; custom families do not replace the bundled Geist families.
`design.shape.radiusScale` accepts 0–2, with 1 preserving the default geometry.
Provider-hosted verification/payment content retains its provider appearance;
its theme follows the selected light/dark mode where supported.
Typography and radius controls affect themed components; changing screen
structure or introducing a new interaction still requires Flutter changes.

## Logos, loaders, icons, and splash screens

`design.assets.logo` is required. `logoDark`, `splash`, and `loader` are optional.
Images support PNG, JPEG, WebP, or GIF up to 8192 pixels per dimension. SVG files
must be exported to PNG before use. Input images are converted to the first
frame of PNG for Flutter, web, and native assets. Loader animation is controlled
by the app so disabling motion also stops custom artwork animation.

For example:

```json
"assets": {
  "logo": "assets/logo.png",
  "logoDark": "assets/logo-on-dark.png",
  "splash": "assets/launch-mark.png",
  "loader": "assets/loading-mark.png"
}
```

Without a splash override, the matching light/dark logo is used. Without a
loader override, the matching logo is used. Native launch images are fitted
inside a centered square; use a compact transparent mark for reliable small
sizes. Provide a large square `native.icon` image, ideally 1024 × 1024. The tool
creates opaque iOS/app-store and legacy Android icons, padded Android adaptive
icons, maskable PWA icons, an Apple touch icon, and a favicon. `iconBackground`
sets the opaque background behind artwork.

`design.loader.style` is `logo` or `circular`. Both use customer-configured
artwork and colors; there is no built-in product logo. `durationMs` accepts 200–10000. Native launch screens remain
static; the web boot page uses the configured logo or circular animation.

`design.splash` accepts `enabled`, `backgroundLight`, `backgroundDark`,
`minimumDurationMs` (0–10000), and `maximumDurationMs` (0–30000). The minimum
cannot exceed the maximum. Duration bounds apply to the Flutter boot
presentation; operating systems control how long their native launch screen
is shown. The web shell fades after Flutter's first frame, with the existing
startup recovery screen available if initialization fails.

`design.motion.enabled` controls configured branding animation;
`durationScale` accepts 0.1–3. Loaders and the web shell also honor device
reduced-motion settings.

## Customer Firebase setup

The sample has `native.firebase: {}`. Preparing it removes active copied
`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` and
removes the iOS resource reference. Generated Firebase Dart values are empty,
so there is no fallback to the original app's project. Push notifications stay
disabled until customer files are supplied.

To enable Firebase for a customer, download its Android and/or iOS client
configuration files into a local subfolder of the configuration directory:

```json
"firebase": {
  "android": "private/google-services.json",
  "ios": "private/GoogleService-Info.plist"
}
```

Register the exact customer application/bundle IDs in that Firebase project.
The generator validates those IDs and requires both files to use the same
project when both are supplied. It derives the matching `FIREBASE_*` Dart
settings and enables the Android plugin/iOS resource only when the customer
file is present. Do not use `flutterDefines` to override generated Firebase
settings. APNs capabilities, signing, push certificates, and backend credentials
still belong to the customer's platform setup. Add local configuration files
to your ignore rules if they should not be checked in; never add Firebase Admin
or service-account private keys to the client app.

## Generated files and verification

Treat `config/*.json` and their source assets as the edit points. The tool
regenerates `assets/branding/`, native icons/splash resources, Android
`brand.properties`, iOS `Flutter/Brand.xcconfig`, web branding assets,
`web/index.html`, `web/manifest.json`, and custom font declarations. The
reference sample's generated native/web files are checked in so the clone has
safe default identifiers and artwork. Generated Dart defines are under the
ignored `.dart_tool/` directory.

The web template is `scripts/branding/index.template.html`. Shared runtime
bridges remain in `web/app_bridges.js`, and recovery behavior remains in
`web/app_recovery.js`. Their internal `example*` names are compatibility hooks
used by existing Dart code; they do not determine the brand shown to customers.
After a web build the wrapper versions the service-worker cache from built
content and adds the selected web branding assets to the offline shell.

```sh
python3 -m unittest discover -s scripts/tests -p 'test_branding.py'
node --test mobile_flutter/test/web/*.mjs
```

Before shipping a customer app, build its native targets with that customer's
signing and verify light/dark mode, launch icons, startup, and key flows on real
devices. The shared non-design fixes workflow is described in
[`upstream-sync.md`](upstream-sync.md).

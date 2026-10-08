# Configurable mobile application

Flutter application using Material 3, Riverpod, go_router, and Dio. Example's
screen layouts are available as a design preset with customer-controlled
branding. Backend API integrations and application flows are inherited from
the original repository.

## Branding

Edit [`config/hoppa.json`](config/hoppa.json), then run from the repository root:

```bash
./scripts/build-mobile-branded.sh web mobile_flutter/config/hoppa.json
```

The preparation step validates the config, bundles its assets/fonts, generates
native and web identity resources, and passes the same design to Flutter.
Use the wrapper for customer builds so startup screens and app icons match
the in-app theme. A bare `flutter run` uses legacy Dart defaults.

See [the branding guide](../docs/branding.md) for local previews, config fields,
supported asset formats, build targets, and a second design example.

## Backend and credentials

Set `APP_FLAVOR` and `API_BASE_URL` in the config's `flutterDefines` object.
Staging and production require a backend URL. Use a separately configured
backend for isolated customer data; a new mobile repository does not isolate
accounts or provider connections by itself.

Hoppa uses the separate Android/iOS identifier `global.hoppa.sampleapp`. Supply matching customer
Firebase client files through the brand config to enable native push. Server
Firebase service-account credentials remain in the backend secret store.
Release signing, Apple provisioning, APNs setup, and store records are separate
from visual branding. iOS targets version 15 or later.

## Validation

```bash
flutter pub get
flutter analyze
flutter test
```

KYC calls `POST /api/v1/mobile/kyc/sumsub-token`; the SumSub adapter keeps the
provider SDK separate from presentation code. Other provider requests continue
through the backend API.

See [the upstream sync guide](../docs/upstream-sync.md) to import selected
functional fixes from Example while reviewing changes to shared screens.

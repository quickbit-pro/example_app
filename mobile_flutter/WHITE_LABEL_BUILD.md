# White-label mobile build

The WL admin's **Mobile design** page owns the build-time branding values for
each company installation. Save the design and download
`wl-flutter-design.json`.

Build Android App Bundle:

```bash
./scripts/build-mobile-branded.sh appbundle /path/to/wl-flutter-design.json
```

Build iOS archive:

```bash
./scripts/build-mobile-branded.sh ipa /path/to/wl-flutter-design.json
```

The JSON file is passed to Flutter through `--dart-define-from-file`. It maps to
the existing `AppBranding.fromEnvironment()` values in `lib/flavors.dart`.

## Login background

Set **Login background color** in the admin editor to use a solid six-digit
hexadecimal color on the login screen. Leave it blank to retain the standard
theme-aware gradient. The exported key is `APP_LOGIN_BACKGROUND_COLOR`.

## Logo asset

The admin stores an asset reference such as `assets/brand/acme-logo.png`; it
does not upload the binary into the source repository. Copy the logo into that
path and declare the directory in `pubspec.yaml` before building:

```yaml
flutter:
  assets:
    - assets/brand/
```

## Custom font

Copy the approved `.ttf` or `.otf` files into the app, declare their family in
`pubspec.yaml`, and use that exact family name in the admin editor:

```yaml
flutter:
  fonts:
    - family: Acme Sans
      fonts:
        - asset: assets/fonts/acme-sans-regular.ttf
        - asset: assets/fonts/acme-sans-bold.ttf
          weight: 700
```

The editor can preview a local logo or font file, but those files remain local
and must be reviewed and committed to the Flutter project separately.

# Hoppa branding

`mobile_flutter/config/hoppa.json` is the Hoppa app configuration. It keeps the
existing account, card, payment, and settings layouts and supplies the Hoppa
identity, colors, typography, splash screen, loader, and native/PWA icons.

```sh
python3 scripts/prepare-mobile-brand.py mobile_flutter/config/hoppa.json --check
./scripts/run-mobile-branded.sh mobile_flutter/config/hoppa.json -d chrome
./scripts/build-mobile-branded.sh web mobile_flutter/config/hoppa.json --release
```

The API URL is `https://hoppa-api.roks.dev`. `APP_FLAVOR` is fixed to `prod` for
the runtime's HTTPS and release behavior; it does not introduce a deployment
environment selector. No API keys or server credentials are compiled into this
configuration.

## Official sources

Brand assets and published contact details were checked on 8 September 2026.

| Source | Applied in the app |
| --- | --- |
| [Hoppa website](https://hoppa.global/) and [published stylesheet](https://hoppa.global/assets/index-R1t8j_lB.css) | Purple `#621A96`, deep purple `#4E1578`, aubergine `#46164A`, lime `#C6F24E`, ink `#141414`; Inter body typography. |
| [Official 512-pixel app icon](https://hoppa.global/icon-512.png), linked by the [site manifest](https://hoppa.global/site.webmanifest) | Unmodified purple H! mark on lime, saved as `config/assets/hoppa-icon.png`; used for logos, splash, loader, and application icons. |
| [Official favicon source](https://hoppa.global/favicon.svg) | Confirms the app-icon artwork's purple `#3B1A55` and lime `#CCFF00`. The icon background uses its original lime to keep native/PWA padding consistent. |
| [Hoppa contact page](https://hoppa.global/contact) | Existing-customer address `support@hoppa.global`. |
| [Google Fonts stylesheet requested by Hoppa](https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Sora:wght@400;500;600;700&display=swap) | Bundled static Inter weights 400, 500, 600, and 700, loaded locally at runtime. |
| [Inter SIL Open Font License](https://github.com/google/fonts/blob/main/ofl/inter/OFL.txt) | Saved alongside the fonts as `config/assets/hoppa-inter-OFL.txt`. |

The official compact app icon fits the existing square logo slots and remains
legible at small sizes. The site also publishes a photograph-style square logo;
this app uses its existing flat app icon for consistency across platforms. The
artwork has not been redrawn or recolored. Generated native sizes are produced
by the normal branding tool from the original 512 × 512 image.

Hoppa's website uses Sora for headings and Inter for body text. The current app
configuration exposes one main font family, so the app uses Inter throughout
and retains Geist Mono for tabular/code content. No runtime font download is
required.

## App palette and identity

The website declares a light appearance. The mobile dark appearance is an app
adaptation of its purple surfaces, lime actions, and pale lilac text. Light-mode
links and action labels use deep purple, while lime appears on artwork, cards,
and soft decorative areas. This keeps small text readable on light surfaces.

The configured text, secondary text, tertiary text, accent, status, and teal
foregrounds were checked against `paper`, `surface`, `surfaceSubtle`, and
`surfaceHigh`. Their minimum contrast is 4.81:1 in light mode and 6.18:1 in dark
mode. Button text and card text also exceed 4.5:1 on their configured fills,
and control edges exceed 3:1 on those four surfaces. These checks cover the
base color pairs; translucent effects and final screens still benefit from
device review.

The visible name is `Hoppa`; the brand ID is `hoppa`. Android and iOS use
`global.hoppa.sampleapp`, a separate sample-app identity chosen for this clone,
not a claim about an existing published Hoppa app's identifier. Firebase is
empty until Hoppa-specific client files are supplied. The legal-entity field,
phone, and external transfer-dashboard URL remain empty because their intended
app values were not established from the supplied site.

## Source file integrity

The unmodified official icon has SHA-256
`8d8fd3f52e42558106481cbba3df45fe6edc8de4def1e7f44996852a59f3363a`.

The font source URLs, as returned by the Google Fonts stylesheet, are:

- [Inter 400](https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf)
- [Inter 500](https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuI6fMZg.ttf)
- [Inter 600](https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYMZg.ttf)
- [Inter 700](https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZg.ttf)

For all configurable fields and the platform generation behavior, see
[`branding.md`](branding.md).

# Offline Flutter fallback font

`NotoSansSymbols.woff2` is the genuine Google Fonts file referenced by Flutter's
CanvasKit font fallback table. It covers symbols used by the production screens.
The packager registers the font and maps Flutter's internal fallback request to
these embedded bytes. It does not substitute a different font or contact a font
server when the customer opens the guide.

Source: [Google Fonts Noto Sans Symbols v43](https://fonts.gstatic.com/s/notosanssymbols/v43/rP2up3q65FkAtHfwd-eIS2brbDN6gxP34F9jRRCe4W3gfQ8gb_VFRkzrbQ.woff2).
License: [Google Fonts official Noto Sans Symbols OFL](https://github.com/google/fonts/blob/main/ofl/notosanssymbols/OFL.txt), copied as `NotoSansSymbols-OFL.txt` with trailing whitespace normalized and embedded in the guide.

Downloaded September 8, 2026. The files are committed so subsequent builds run
without downloading fonts.

| File | SHA-256 |
| --- | --- |
| NotoSansSymbols.woff2 | `08202e258ea583254c036cff46a7077bb5af4f82c41a6c0a6775f6e44d99f1aa` |
| NotoSansSymbols-OFL.txt | `e87c2ed7ff174c637d55fa381939ebb96f43f0415ad94605a37589228f4cbf4f` |

The Roboto fallback and its license come separately from the installed Flutter
SDK's `bin/cache/artifacts/material_fonts` directory during packaging.

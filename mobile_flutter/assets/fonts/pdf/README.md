PDF-only fonts, loaded on demand by the deferred export renderer.

Source: https://github.com/google/fonts/tree/main/ofl
Families: Noto Sans Arabic, Noto Sans Devanagari, Noto Sans JP, Noto Sans KR.
Downloaded 2026-09-09. Each font retains its adjacent SIL Open Font License.
Variable fonts were instantiated at weight 400 and their default width with
fontTools to reduce the package size. These assets are not startup font families.

Japanese and Korean use embedded PDF fonts. Arabic and Hindi pages use Flutter's
text shaping and are embedded as page images, preserving joins and text direction.
Those two exports are visually readable but do not provide selectable PDF text.

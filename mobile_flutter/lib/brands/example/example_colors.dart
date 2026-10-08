import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';

abstract final class ExampleColors {
  // Official EXAMPLE brand palette.
  static const night = Color(0xFF0D0B22);
  static const indigo = Color(0xFF2E2A6E);
  static const violet = Color(0xFF7B6CF6);
  static const iris = Color(0xFFA78BFA);
  static const lavender = Color(0xFFC9B8F5);
  static const pearl = Color(0xFFF2EAFB);

  // Twilight application tokens from the EXAMPLE HTML handoff.
  static const appBackground = Color(0xFF050713);
  static const navigationSurface = Color(0xFF0A0D1C);
  static const darkSurface = Color(0xFF101425);
  static const darkSurfaceSubtle = Color(0xFF1B2035);
  static const darkSurfaceHigh = Color(0xFF221C56);
  static const darkBorder = Color(0xFF2B3047);
  static const success = Color(0xFF20D996);
  static const teal = Color(0xFF27D7C2);
  static const warning = Color(0xFFF2B94B);
  static const danger = Color(0xFFFF6474);

  // Twilight glass surfaces used by the Example App design canvas.
  static const glassTop = Color(0xB31C1E40); // rgba(28,30,64,.70)
  static const glassBottom = Color(0xE60E1026); // rgba(14,16,38,.90)
  static const glowMid = Color(0xFF171540);
  static const railSurface = Color(0xBF080A1C); // rgba(8,10,28,.75)
  static const navigationGlass = Color(0xD9080A1C); // rgba(8,10,28,.85)
  static const textSecondary = Color(0xADF2EAFB); // pearl .68
  /// Tertiary ink, pearl .53 — **body-grade on every Twilight ground**, which
  /// is the floor it has to meet: tertiary carries real sentences (row
  /// subtitles, timestamps, limit captions, nav labels), not decoration.
  ///
  /// Measured, alpha-composited then WCAG 2.1:
  ///
  /// | ground                             | ratio |
  /// | ---------------------------------- | ----- |
  /// | [appBackground] / [navigationSurface] | 5.15 |
  /// | [darkSurface]                      | 5.10  |
  /// | [glassBottom] over [appBackground] | 5.13  |
  /// | [glassTop] over [appBackground]    | 5.00  |
  /// | [glowMid] (atmosphere mid stop)    | 4.95  |
  /// | [darkSurfaceSubtle]                | 4.84  |
  /// | [glassTop] over [darkSurfaceHigh]  | 4.63  |
  /// | [darkSurfaceHigh]                  | 4.66  |
  ///
  /// Raised from .46, which measured 4.10 / 4.13 / 3.99 / 3.85 on the four
  /// ladder steps: it cleared the 3:1 icon floor but not the 4.5:1 body floor,
  /// and it left chevrons and timestamps reading as *disabled* rather than
  /// quiet. .53 is the smallest step with headroom — .518 is the first alpha
  /// that clears 4.5:1 anywhere ([darkSurfaceHigh] at 4.52), which leaves
  /// 0.016 of a ratio point and would be eaten by the next surface tweak.
  /// Going further is the real risk: at .68 tertiary *is* [textSecondary], and
  /// the three volumes collapse to two. The gap to [textSecondary] is 1.55x
  /// on [appBackground] (7.98 against 5.15), and the light theme is tuned to
  /// the same 1.51x, so the hierarchy reads identically in both materials.
  ///
  /// Not a ground: [indigo]. It is a brand hue and the Material
  /// `surfaceContainerHigh` slot, not a step on the Example surface ladder —
  /// tertiary on it is 4.16:1, and the one Example screen that fills with it
  /// writes `onSurfaceVariant` (lavender, 6.97:1). See the palette audit
  /// followups before making it a text ground.
  static const textTertiary = Color(0x87F2EAFB); // pearl .53
  static const borderSubtle = Color(0x24C9B8F5); // lavender .14
  static const borderEmphasis = Color(0x61A78BFA); // iris .38
  static const bitcoin = Color(0xFFF7931A);
  static const ethereum = Color(0xFF627EEA);
  static const flagRed = Color(0xFFB22234);
  static const flagBlue = Color(0xFF0B3B8C);
  static const flagGold = Color(0xFFF5C518);

  // ─── Pearl daylight: the Example light mode ────────────────────────────────
  //
  // Same brand, sunlit. The ground is paper rather than white so the page
  // never glares, surfaces climb toward white instead of toward indigo, and
  // every accent hue is re-darkened until it carries text on that ground.
  //
  // Every ratio below is WCAG 2.1, measured after alpha-compositing the token
  // onto the named ground, and quoted for both grounds a Example light screen
  // has: `lightSurface` (#FFFFFF, panels and cards) and `lightPaper`
  // (#F8F5FC, the scaffold). Body text needs 4.5:1, secondary text, icons and
  // focus rings 3:1. Nothing below is used on dark: the dark tokens above are
  // untouched, so a dark screen renders exactly the pixels it rendered before
  // light mode existed.

  // Surfaces. The ladder mirrors ExampleSurface level0..3 on dark, inverted:
  // level0 = lightPaper, level1 = lightSurface, level2 = lightSurfaceSubtle,
  // level3 = lightSurfaceHigh.
  // Every value below carries a deliberate violet cast: this is Example's
  // daylight, not a neutral white theme. The measure is B-R, how far the
  // blue channel outruns the red — paper went 4 -> 8, surface 0 -> 4 (a
  // sterile #FFFFFF card is what made light mode read as someone else's
  // app), subtle 8 -> 12, high 14 -> 18. Luminance is held, so every ink
  // ratio moves by hundredths and the AA floors all still clear.
  static const lightPaper = Color(0xFFF4EEFC);
  static const lightSurface = Color(0xFFFBF8FF);
  static const lightSurfaceSubtle = Color(0xFFEFE8FB);
  static const lightSurfaceHigh = Color(0xFFEAE1FC);
  static const lightBorder = Color(0xFFD8CBF0);

  /// Chrome (bars, rails) on light: white, so it separates upward from the
  /// paper ground the way [navigationSurface] separates upward from
  /// [appBackground] on dark.
  static const lightNavigationSurface = Color(0xFFFBF8FF);

  /// Frosted navigation bar: white .85, the same alpha as [navigationGlass].
  static const lightNavigationGlass = Color(0xD9FBF8FF);

  /// Frosted desktop rail: white .75, the same alpha as [railSurface].
  static const lightRailSurface = Color(0xBFFBF8FF);

  /// Frosted panel over atmosphere or artwork: white .60 with blur 18.
  /// Ink on it keeps ≥ 15:1 because every light atmosphere peak stays above
  /// the paper ground in luminance.
  static const lightGlassTop = Color(0x99FBF8FF);

  /// Lower stop of the frosted gradient: [lightSurfaceSubtle] at .85.
  static const lightGlassBottom = Color(0xD9EFE8FB);

  // The three daylight glow tokens below are the atmosphere's *measured
  // ceiling*, not its source. `ExampleAtmosphere` composes its light presets
  // from (hue, alpha) pairs — a violet dawn with iris in the falloff and a
  // cool teal counter-glow, for the temperature contrast a flat lavender haze
  // would lose — so these premultiplied values exist to state, once and in
  // one place, how bright the backdrop is ever allowed to get and what ink
  // reads on it. Any new light glow must land at or below these.

  // Re-measured after the daylight budget rose from .4 to .80. The old
  // figures described a ground that composited to a 1.09:1 field — paper with
  // no sky — and the painter now runs past every one of them, so they are
  // restated here against the brightest stack the presets actually produce
  // (`_authLight`: violet .20 with an iris mid at .13, both times .80).

  /// Solid mid stop of the light atmosphere, the daylight mirror of
  /// [glowMid]. Ink (#0D0B22) on it: 14.9:1.
  static const lightGlowMid = Color(0xFFE7E0FB);

  /// Brightest point the light atmosphere is allowed to reach: composited over
  /// [lightPaper] it is #DBCEFB, a 1.30:1 travel from paper. All three ink
  /// volumes are body-grade on it — ink 13.08:1, [lightTextSecondary] 6.50:1,
  /// [lightTextTertiary] 4.51:1 — which is the point of the .604 tertiary: an
  /// auth screen puts its headline *and* its helper caption straight onto this
  /// ground, so the peak is a text ground whether or not it was declared one.
  ///
  /// Coloured ink on the same peak lands at 3.52:1 ([lightTeal]) to 4.23:1
  /// ([lightIris]) — above the 3:1 floor for icons, pills and links, below the
  /// 4.5:1 body floor. This is a property of the accents, not of the budget:
  /// at the old .4 the worst was still 4.12:1, so flattening the ground buys
  /// half a ratio point and costs the whole daylight sky. The rule that
  /// follows is compositional, and every screen in the build already obeys it:
  /// a *sentence* in a coloured accent belongs on a surface — [lightSurface],
  /// or [lightSurfaceSubtle] — never directly on the backdrop's bright half.
  /// Pills, icons, links and short labels may sit on it; a caption on the peak
  /// takes [lightTextTertiary], which is exactly what it is for.
  static const lightGlowIris = Color(0x52A78BFA);

  /// Brightest permitted counter-glow: [lavender] at .22, times the .80
  /// budget, over paper. Peak composite #F0EAFB, ink on the peak 16.1:1.
  static const lightGlowLavender = Color(0x2DC9B8F5);

  // Ink. Night at three volumes, the daylight mirror of pearl / textSecondary
  // / textTertiary.

  /// Primary ink. 18.36:1 on lightSurface, 16.99:1 on lightPaper.
  static const lightTextPrimary = Color(0xFF0D0B22); // night

  /// Secondary ink, night .72. 7.79:1 on lightSurface, 7.49:1 on lightPaper —
  /// still body-grade, so it may carry sentences, not only captions.
  static const lightTextSecondary = Color(0xB80D0B22);

  /// Tertiary ink, night .604 — body-grade on **every** daylight ground,
  /// including the two the .58 value missed:
  ///
  /// | ground                                  | .58  | .604 |
  /// | --------------------------------------- | ---- | ---- |
  /// | [lightSurface] / [lightNavigationSurface] | 4.69 | 5.09 |
  /// | [lightPaper]                            | 4.58 | 4.96 |
  /// | [lightSurfaceSubtle]                    | 4.51 | 4.88 |
  /// | [lightSkeletonBase]                     | 4.48 | 4.84 |
  /// | [lightGlowLavender] peak over paper     | 4.47 | 4.82 |
  /// | [lightSurfaceHigh]                      | 4.43 | 4.78 |
  /// | [lightGlowMid]                          | 4.41 | 4.76 |
  /// | [lightGlowIris] peak over paper         | 4.20 | 4.51 |
  ///
  /// The two grounds that forced the raise are the ones a caption is most
  /// likely to sit on and least likely to be checked against: the *selected*
  /// row ([lightSurfaceHigh]) and the daylight sky itself. An auth screen
  /// lands its headline and its helper caption directly over the atmosphere,
  /// so the peak is a text ground whether or not anyone declared it one.
  ///
  /// .604 rather than a rounder .60 because .60 leaves the atmosphere peak at
  /// 4.46 — under the floor by less than the eye can see and by exactly enough
  /// for the test to be right to fail. Raised from .50 (3.64 / 3.58 / 3.42),
  /// then .58. It stays plainly quieter than [lightTextSecondary]: 7.49
  /// against 4.96 on paper is a 1.51x gap, the same spacing Twilight uses
  /// between [textSecondary] and [textTertiary] (1.55x), so the three volumes
  /// read the same in both materials.
  ///
  /// Also the daylight `controlEdge` — the boundary of a field or an outlined
  /// button, where WCAG 1.4.11 asks 3:1 and [lightBorder] gives 1.35. The
  /// raise strengthens that edge from 4.58 to 4.96 on paper.
  static const lightTextTertiary = Color(0x9A0D0B22);

  /// Resting hairline and panel edge, lavender .30 (the dark [borderSubtle]
  /// is lavender .14). Composite over white #EFEAFC, 1.18:1 — a boundary, not
  /// a line, exactly as on dark.
  static const lightBorderSubtle = Color(0x4DC9B8F5);

  /// Selected / focused / active edge, [lightViolet] at .55. Composite over
  /// [lightSurface] #A89FEE, 2.26:1 as a hairline — a *state* on an element
  /// the content already identifies, not the element's own boundary. The
  /// 2 px focus ring, which WCAG 1.4.11 does hold to 3:1, takes [lightViolet]
  /// itself: 4.72:1 on paper and 5.10:1 on [lightSurface].
  static const lightBorderEmphasis = Color(0x8C6455E0);

  // Accents. Roles match dark: violet fills, iris is the foreground accent.
  // The values invert — on paper the foreground accent must be the darker of
  // the two, or it cannot carry a link.

  // Every "as text" ratio in this block was re-measured after the surface
  // ladder took its violet cast (`lightSurface` #FFFFFF -> #FBF8FF,
  // `lightPaper` #F8F5FC -> #F4EEFC, `lightSurfaceSubtle` #F2ECFA -> #EFE8FB).
  // The ink volumes were restated at the time; the accents were not, and they
  // moved by a quarter of a ratio point, not "hundredths" — enough to walk
  // `lightDanger` under the body floor on paper without anything saying so.
  // The "white on it" figures are unaffected: they never touched a surface.
  //
  // Read the four numbers as surface / paper / subtle / high. **Level 0 and
  // level 1 are the body grounds for a coloured accent**: a sentence in a
  // status hue belongs on the scaffold or on a panel. Level 2 is the pressed
  // tint and level 3 is the one selected element — a pill, a chip, a glyph,
  // never a paragraph — and every accent clears the 3:1 non-text floor there
  // with room to spare (worst: `lightTeal` 4.13). Closing level 2 and 3 to
  // 4.5:1 as well would mean re-darkening the whole family, which is a design
  // decision and not an accessibility repair; the audit records it instead.

  /// Primary fill on light (buttons, selected segment, focus ring). White on
  /// it 5.36:1, [pearl] 4.58:1. As text: 5.10 / 4.72 / 4.49 / 4.26.
  static const lightViolet = Color(0xFF6455E0);

  /// Foreground accent on light — links, active icons, active nav labels; the
  /// role [iris] plays on dark, and the brightest of the family because a link
  /// has to win against body ink. As text: 5.93 / 5.49 / 5.23 / 4.95.
  static const lightIris = Color(0xFF5B49D6);

  /// Positive / verified on light. White on it 5.37:1.
  /// As text: 5.11 / 4.73 / 4.50 / 4.26.
  static const lightSuccess = Color(0xFF097A50);

  /// Negative / destructive on light. White on it 5.36:1, [pearl] 4.58:1.
  /// As text: 5.10 / 4.72 / 4.49 / 4.25.
  ///
  /// Deepened from #D22A44, which measured 4.81 / **4.45** / 4.24 / 4.01: it
  /// failed the body floor on [lightPaper], and paper is precisely where error
  /// text lives — a form error sits on the scaffold, under the field, not on a
  /// panel. Of the six daylight accents it was the only one under 4.5:1 on a
  /// level-0 or level-1 ground, so this is a repair, not a re-tone.
  ///
  /// The new value is picked to land on [lightViolet]'s exact luminance step
  /// (identical to two decimal places on all four grounds, and the same 5.36:1
  /// under white), so destructive and primary are one family at one weight —
  /// a destructive button and a primary button now read as the same object in
  /// two colours, which is what makes the pair legible as a choice.
  static const lightDanger = Color(0xFFCB2841);

  /// Pending / caution on light. White on it 5.56:1.
  /// As text: 5.29 / 4.90 / 4.66 / 4.42. Amber cannot pass 4.5:1 on paper, so
  /// daylight caution is bronze.
  static const lightWarning = Color(0xFF8F5E0C);

  /// Crypto / secondary accent on light. White on it 5.20:1.
  /// As text: 4.94 / 4.57 / 4.36 / 4.13.
  static const lightTeal = Color(0xFF0B7A72);

  /// Ambient shadow on light, night .06, blur 24 y 8. Depth on paper comes
  /// from shadow first and surface second — the reverse of dark.
  static const lightShadowAmbient = Color(0x0F0D0B22);

  /// Raised-card shadow on light, night .10, blur 24 y 8.
  static const lightShadowLift = Color(0x1A0D0B22);

  /// Skeleton block on light — lavender, not the grey every other wallet
  /// ships (the dark equivalent is ExampleSurface.level2). 1.13:1 off
  /// lightPaper and 1.22:1 off lightSurface, against dark's 1.14:1 and
  /// 1.25:1, so a loading screen carries the same weight in either theme:
  /// present enough to read as reserved space, never enough to read as
  /// content.
  static const lightSkeletonBase = Color(0xFFEDE5F8);

  /// Peak of a ExampleSheen band on dark: pearl .14.
  static const sheenPeak = Color(0x24F2EAFB);

  /// Peak of a ExampleSheen band on light: white .35.
  static const lightSheenPeak = Color(0x59FFFFFF);
}

/// The whole Example token set resolved for one brightness. **This is the
/// model.** Everything else in the vocabulary is a lens onto it.
///
/// ## The model in one read
///
/// [ExampleColors] above is the dictionary: every literal the brand owns, dark
/// and light, each carrying its measured contrast ratio. It is a flat list of
/// names, so it cannot answer "what colour is a panel *here*".
///
/// This class is the two answers to that question, frozen as [dark] and
/// [light] — one `const` instance each, ~26 named **roles** (`paper`,
/// `surface`, `ink`, `borderSubtle`, `accent`, ...). A role means the same
/// thing in both themes even where the value inverts: [accent] is the
/// foreground accent (iris on night, a *darker* violet on paper, because on
/// paper the foreground accent has to be the darker of the two), and [fill] is
/// the primary fill (violet in both, re-darkened on light so white sits on it
/// at 5.36:1).
///
/// Three properties make this safe to build the app on:
///
/// 1. **Dark is provably unchanged.** Every field of [dark] is spelled as the
///    historical constant the app already rendered — `ink` *is*
///    [ExampleColors.pearl], `surface` *is* [ExampleColors.darkSurface],
///    `navigation` *is* [ExampleColors.navigationSurface]. Replacing a
///    hard-coded dark literal at a call site with the matching role is
///    therefore a byte-identical edit in Twilight, and only fixes daylight.
/// 2. **Light is a designed second material, not an inversion.** Paper climbs
///    to white where night climbs to indigo; depth on paper is shadow first
///    and surface second, the reverse of dark; every accent is re-darkened
///    until it carries text on paper. The ratios are on the tokens above.
/// 3. **Consumers resolve, they never hard-code.** Read
///    `ExamplePalette.of(context)` once at the top of `build` and use roles.
///    A Example widget should never write `isDark ? a : b` by hand, and never
///    name a brightness-specific literal.
///
/// Both instances are `const`, so resolving costs one `Theme.of` and nothing
/// else. This is deliberately a plain value class rather than a
/// `ThemeExtension`: it needs no registration, no `lerp` and no theme
/// rebuild, and it cannot disagree with the [ThemeData] built in
/// `lib/core/theme/app_theme.dart` because both read the constants above.
///
/// ## Where the other names went
///
/// The vocabulary used to grow a second facade beside this one, and a
/// reviewer had to learn both. They are now **one-line lenses over this
/// class**, kept only because renaming ~700 call sites buys nothing:
///
/// | Lens                                | Reads as                        |
/// | ----------------------------------- | ------------------------------- |
/// | `ExampleTheme.isLight(c)`            | `of(c).isLight`                 |
/// | `ExampleTheme.pick(c, dark:, light:)`| `of(c).pick(dark:, light:)`     |
/// | `ExampleInk.primary(c)`              | `of(c).ink`                     |
/// | `ExampleInk.secondary(c)`            | `of(c).textSecondary`           |
/// | `ExampleInk.tertiary(c)`             | `of(c).textTertiary`            |
/// | `ExampleInk.accent(c, hue)`          | `of(c).accentFor(hue)`          |
/// | `ExampleInk.tint(c, hue)`            | `of(c).tint(hue)`               |
/// | `ExampleInk.selection(c)`            | `of(c).fill`                    |
/// | `ExampleInk.onSelection(c)`          | `of(c).onFill`                  |
/// | `ExampleInk.hover(c)`                | `of(c).hover`                   |
/// | `ExampleSurface.of(c, n)`            | `of(c).surfaceLevel(n)`         |
/// | `ExampleSurface.navigationOf(c)`     | `of(c).navigation`              |
///
/// Nothing below duplicates a decision made elsewhere: this class is the only
/// place in the vocabulary that asks *which brightness am I in* and the only
/// place that decides *what colour that makes it*. `ExampleBorders`,
/// `ExampleShadows`, `ExampleSurface` and `ExampleInk` (all in
/// `example_tokens.dart`, which imports this file) route through it.
///
/// ## Guessing the right call
///
/// * A bare `const` on a token class is a fixed **Twilight** value
///   (`ExampleBorders.subtleSide`, `ExampleShadows.lift`,
///   `ExampleSurface.level1`); the same name with a `light` in it is its
///   explicit daylight twin (`subtleLightSide`, `liftLight`, `light1`).
/// * A member taking a `BuildContext` is **resolved for the active theme**.
///   It is named `of(context)` when the plain name is free, and `<name>Of`
///   when the class also exposes a const of that name — `subtleSideOf`,
///   `liftOf`, `navigationOf`.
/// * When in doubt, reach for `ExamplePalette.of(context)` and a role. It can
///   answer anything the lenses can.
@immutable
class ExamplePalette {
  const ExamplePalette({
    required this.brightness,
    required this.paper,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceHigh,
    required this.navigation,
    required this.navigationGlass,
    required this.rail,
    required this.glassTop,
    required this.glassBottom,
    required this.ink,
    required this.textSecondary,
    required this.textTertiary,
    required this.borderSubtle,
    required this.borderEmphasis,
    required this.fill,
    required this.accent,
    required this.success,
    required this.danger,
    required this.warning,
    required this.teal,
    required this.shadowAmbient,
    required this.shadowLift,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.sheenPeak,
    this.design = const AppDesign(),
  });

  /// Twilight. Every value is the token the dark screens already render.
  static const dark = ExamplePalette(
    brightness: Brightness.dark,
    paper: ExampleColors.appBackground,
    surface: ExampleColors.darkSurface,
    surfaceSubtle: ExampleColors.darkSurfaceSubtle,
    surfaceHigh: ExampleColors.darkSurfaceHigh,
    navigation: ExampleColors.navigationSurface,
    navigationGlass: ExampleColors.navigationGlass,
    rail: ExampleColors.railSurface,
    glassTop: ExampleColors.glassTop,
    glassBottom: ExampleColors.glassBottom,
    ink: ExampleColors.pearl,
    textSecondary: ExampleColors.textSecondary,
    textTertiary: ExampleColors.textTertiary,
    borderSubtle: ExampleColors.borderSubtle,
    borderEmphasis: ExampleColors.borderEmphasis,
    fill: ExampleColors.violet,
    accent: ExampleColors.iris,
    success: ExampleColors.success,
    danger: ExampleColors.danger,
    warning: ExampleColors.warning,
    teal: ExampleColors.teal,
    shadowAmbient: Color(0x99050713), // appBackground .60, as ExampleShadows
    shadowLift: Color(0x267B6CF6), // violet .15, as ExampleShadows.lift
    skeletonBase: ExampleColors.darkSurfaceSubtle,
    skeletonHighlight: ExampleColors.sheenPeak,
    sheenPeak: ExampleColors.sheenPeak,
  );

  /// Pearl daylight.
  static const light = ExamplePalette(
    brightness: Brightness.light,
    paper: ExampleColors.lightPaper,
    surface: ExampleColors.lightSurface,
    surfaceSubtle: ExampleColors.lightSurfaceSubtle,
    surfaceHigh: ExampleColors.lightSurfaceHigh,
    navigation: ExampleColors.lightNavigationSurface,
    navigationGlass: ExampleColors.lightNavigationGlass,
    rail: ExampleColors.lightRailSurface,
    glassTop: ExampleColors.lightGlassTop,
    glassBottom: ExampleColors.lightGlassBottom,
    ink: ExampleColors.lightTextPrimary,
    textSecondary: ExampleColors.lightTextSecondary,
    textTertiary: ExampleColors.lightTextTertiary,
    borderSubtle: ExampleColors.lightBorderSubtle,
    borderEmphasis: ExampleColors.lightBorderEmphasis,
    fill: ExampleColors.lightViolet,
    accent: ExampleColors.lightIris,
    success: ExampleColors.lightSuccess,
    danger: ExampleColors.lightDanger,
    warning: ExampleColors.lightWarning,
    teal: ExampleColors.lightTeal,
    shadowAmbient: ExampleColors.lightShadowAmbient,
    shadowLift: ExampleColors.lightShadowLift,
    skeletonBase: ExampleColors.lightSkeletonBase,
    skeletonHighlight: ExampleColors.lightSheenPeak,
    sheenPeak: ExampleColors.lightSheenPeak,
  );

  /// The palette for the active theme.
  ///
  /// Outside a [MaterialApp] this resolves to [light], because `Theme.of`
  /// falls back to `ThemeData.fallback()` and that is `Brightness.light`. The
  /// doc here used to claim [dark]; it never was. Nothing renders outside a
  /// `MaterialApp` in this app, so the claim is corrected rather than the
  /// behaviour — flipping the fallback would move pixels in bare-widget tests.
  static ExamplePalette of(BuildContext context) =>
      fromDesign(Theme.of(context).brightness, AppDesignTheme.of(context));

  /// Resolve semantic overrides once for a palette. Defaults retain the source
  /// app's appearance while each customer can replace the whole visual system.
  static ExamplePalette fromDesign(Brightness brightness, AppDesign design) {
    final base = forBrightness(brightness);
    if (!design.isConfigured) return base;
    Color color(String name, Color fallback) =>
        design.color(brightness, name, fallback: fallback);
    return ExamplePalette(
      brightness: brightness,
      design: design,
      paper: color('paper', base.paper),
      surface: color('surface', base.surface),
      surfaceSubtle: color('surfaceSubtle', base.surfaceSubtle),
      surfaceHigh: color('surfaceHigh', base.surfaceHigh),
      navigation: color('navigation', base.navigation),
      navigationGlass: color('navigationGlass', base.navigationGlass),
      rail: color('rail', base.rail),
      glassTop: color('glassTop', base.glassTop),
      glassBottom: color('glassBottom', base.glassBottom),
      ink: color('ink', base.ink),
      textSecondary: color('textSecondary', base.textSecondary),
      textTertiary: color('textTertiary', base.textTertiary),
      borderSubtle: color('borderSubtle', base.borderSubtle),
      borderEmphasis: color('borderEmphasis', base.borderEmphasis),
      fill: color('fill', base.fill),
      accent: color('accent', base.accent),
      success: color('success', base.success),
      danger: color('danger', base.danger),
      warning: color('warning', base.warning),
      teal: color('teal', base.teal),
      shadowAmbient: color('shadowAmbient', base.shadowAmbient),
      shadowLift: color('shadowLift', base.shadowLift),
      skeletonBase: color('skeletonBase', base.skeletonBase),
      skeletonHighlight: color('skeletonHighlight', base.skeletonHighlight),
      sheenPeak: color('sheenPeak', base.sheenPeak),
    );
  }

  final AppDesign design;

  static ExamplePalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  final Brightness brightness;

  /// Level 0: the page.
  final Color paper;

  /// Level 1: panels, cards, list groups.
  final Color surface;

  /// Level 2: an element resting on a level-1 panel, and the pressed tint.
  final Color surfaceSubtle;

  /// Level 3: the one selected or highlighted element.
  final Color surfaceHigh;

  /// Bars and rails.
  final Color navigation;

  /// Frosted bar fill.
  final Color navigationGlass;

  /// Frosted desktop rail fill.
  final Color rail;

  /// Upper stop of a frosted panel.
  final Color glassTop;

  /// Lower stop of a frosted panel.
  final Color glassBottom;

  /// Body ink. ≥ 17.8:1 on [paper] in both themes.
  final Color ink;

  /// Secondary ink. ≥ 7.3:1 on [paper] in both themes.
  final Color textSecondary;

  /// Tertiary ink. **Body-grade** — ≥ 4.5:1 on every ground either theme
  /// produces, [surfaceHigh] and the atmosphere peak included. It is the
  /// quietest of three volumes, not a disabled state; it carries row
  /// subtitles, timestamps and limit captions, so 3:1 was never its floor.
  final Color textTertiary;

  /// Resting edge and row hairline.
  final Color borderSubtle;

  /// Selected / focused / active edge.
  final Color borderEmphasis;

  /// Primary fill: buttons, selected segment, focus ring. White sits on it at
  /// ≥ 4.5:1 on light; on dark it is the historical violet.
  final Color fill;

  /// Foreground accent: links, active icons, active nav labels.
  final Color accent;

  final Color success;
  final Color danger;
  final Color warning;
  final Color teal;

  /// Ambient depth (sheets, chrome).
  final Color shadowAmbient;

  /// Raised-card depth.
  final Color shadowLift;

  /// Resting fill of a skeleton block.
  final Color skeletonBase;

  /// Peak of the sheen that crosses a skeleton block. The same band the rest
  /// of the alive layer paints — [sheenPeak] — because a loading block is a
  /// sheen host like any other; `ExampleSheen` halves it again for
  /// `ExampleSheenIntensity.soft`, which is what a skeleton asks for (pearl
  /// .07 on night, white .175 on paper). Never a brighter, private shimmer:
  /// a placeholder that outshines the content it stands in for is the
  /// wallet-shimmer cliché this system is built against.
  final Color skeletonHighlight;

  /// Peak of a `ExampleSheen` band: pearl .14 on dark, white .35 on light.
  final Color sheenPeak;

  /// Label on [fill]. Pearl in both themes: the fill moves, the text does
  /// not, so a primary button reads as one object across the two materials.
  Color get onFill =>
      design.color(brightness, 'onFill', fallback: ExampleColors.pearl);

  /// Hover wash over a row or tile. The same .04 in both themes, opposite
  /// ink — the gesture should feel identical weight on paper and on night.
  Color get hover => ink.withValues(alpha: .04);

  /// Transparent form of [hover], so an `AnimatedContainer` lerps within one
  /// hue instead of passing through grey on the way out.
  Color get hoverOff => ink.withValues(alpha: 0);

  /// True while the Twilight (dark) palette is active.
  bool get isDark => brightness == Brightness.dark;

  /// True while pearl daylight is active. The mirror of [isDark]; both exist
  /// so a call site never has to negate to read naturally.
  bool get isLight => brightness == Brightness.light;

  /// Picks between a Twilight and a daylight value. Reads better than a
  /// ternary at a call site that already has three of them.
  T pick<T>({required T dark, required T light}) => isLight ? light : dark;

  /// The surface ladder as a function: 0 = [paper], 1 = [surface],
  /// 2 = [surfaceSubtle], 3 = [surfaceHigh]. [level] is clamped, so a
  /// computed depth (`parentLevel + 1`) is always safe. This is the whole
  /// implementation of `ExampleSurface.of`.
  Color surfaceLevel(int level) => switch (level.clamp(0, 3)) {
        0 => paper,
        1 => surface,
        2 => surfaceSubtle,
        _ => surfaceHigh,
      };

  /// [color] at reading strength for this theme. Pass the brand token
  /// ([ExampleColors.success], `warning`, `iris`, ...) and let this resolve it;
  /// never hand a status hue straight to a `TextStyle` on a Example screen.
  ///
  /// Twilight returns the hue untouched — the brand palette was drawn for
  /// night — so this is a no-op on every dark pixel. Daylight swaps it for the
  /// daylight token of the same role, because success, teal, warning and iris
  /// are all far too light to sit on paper at their Twilight value (success is
  /// 1.8:1 raw, 5.37:1 as [ExampleColors.lightSuccess]).
  ///
  /// **Idempotent**: `accentFor(accentFor(x)) == accentFor(x)` for every colour
  /// this palette owns. That is not decoration, it is the one way this method
  /// can be misused. A caller that resolves a hue, stores it, and lets it come
  /// back through on the next rebuild — or a wrapper that "helpfully" resolves
  /// what it was handed — used to fall into [_deepen] a second time and blend
  /// .55 toward night again: daylight success left as #097A50 (4.73:1 on
  /// paper, plainly green) and came back #0B483B (9.22:1, plainly black). The
  /// bug is invisible in Twilight, where this method is a no-op, so it can
  /// only ever be caught on the light theme — and it is, by
  /// `test/brands/example/contrast_floor_test.dart`.
  Color accentFor(Color color) {
    if (design.isConfigured) {
      if (color == ExampleColors.violet || color == ExampleColors.lightViolet) {
        return fill;
      }
      if (color == ExampleColors.iris || color == ExampleColors.lightIris) {
        return accent;
      }
      if (color == ExampleColors.success || color == ExampleColors.lightSuccess) {
        return success;
      }
      if (color == ExampleColors.danger || color == ExampleColors.lightDanger) {
        return danger;
      }
      if (color == ExampleColors.warning || color == ExampleColors.lightWarning) {
        return warning;
      }
      if (color == ExampleColors.teal || color == ExampleColors.lightTeal) {
        return teal;
      }
      if (color == ExampleColors.lavender) return textSecondary;
    }
    if (isDark) return color;
    return switch (color) {
      ExampleColors.violet => fill,
      ExampleColors.iris => accent,
      ExampleColors.success => success,
      ExampleColors.danger => danger,
      ExampleColors.warning => warning,
      ExampleColors.teal => teal,
      ExampleColors.pearl => textSecondary,
      // Pale by luminance but not past [_accentCeiling], so [_deepen] would
      // otherwise blend it to #746A96 — 4.35:1 on paper, under the body floor
      // and no longer lavender. Named here because the ceiling's own doc has
      // always claimed lavender falls back to the ink, and now it does.
      ExampleColors.lavender => textSecondary,
      _ => _isResolved(color) ? color : _deepen(color),
    };
  }

  /// True when [color] is already something this palette hands out: one of the
  /// six daylight accents or one of the three ink volumes. Resolving such a
  /// value again must be a no-op — see the idempotence note on [accentFor].
  ///
  /// Written against the roles rather than the [ExampleColors] constants on
  /// purpose: re-tone a daylight accent and this keeps working, because it
  /// asks "is this what I would return" and not "is this the hex I remember".
  bool _isResolved(Color color) =>
      color == fill ||
      color == accent ||
      color == success ||
      color == danger ||
      color == warning ||
      color == teal ||
      color == ink ||
      color == textSecondary ||
      color == textTertiary;

  /// A hue with no daylight token of its own — an asset brand colour, a
  /// tenant accent: pale hues fall back to the secondary ink, hues that are
  /// already ink pass through, and the rest are blended toward night until
  /// they carry text.
  ///
  /// One-shot by design: it has no way to tell a raw hue from one it already
  /// blended, so feeding it its own output darkens twice. [accentFor] is the
  /// only caller and guards it, which is why that method is safe to re-enter
  /// and this one is not. No shipped call site reaches it — every Example hue
  /// is named above, and the asset colours ([ExampleColors.bitcoin],
  /// `ethereum`, the flag hues) are painted directly onto artwork that stays
  /// dark in both themes.
  Color _deepen(Color color) {
    final luminance = color.computeLuminance();
    if (luminance > _accentCeiling) return textSecondary;
    if (luminance < _accentFloor) return color;
    return Color.alphaBlend(
      color.withValues(alpha: _accentBlend),
      ExampleColors.night,
    );
  }

  /// Wash behind an accent glyph (status pill, icon tile). The wash keeps the
  /// Twilight hue in both themes — a pale mint behind a deep green glyph is
  /// what a status pill looks like on paper — and only loses a little alpha.
  Color tint(Color color, {double alpha = .13}) =>
      (design.isConfigured ? accentFor(color) : color)
          .withValues(alpha: isLight ? alpha * .92 : alpha);

  /// Fallback deepening for a hue with no daylight token of its own. .55
  /// against night lands a mid-luminance hue between 4.9:1 and 8.5:1 on paper.
  static const double _accentBlend = .55;

  /// Above this relative luminance a hue cannot be deepened into legibility
  /// without losing its identity; those fall back to the secondary ink
  /// instead. [ExampleColors.pearl] and [ExampleColors.lavender] are the brand's
  /// two such hues and both are named in [accentFor] — lavender because at
  /// .533 it sits just under this line and would otherwise be blended, not
  /// replaced. The ceiling exists for tenant and asset hues.
  static const double _accentCeiling = .6;

  /// Below this one it is already ink and is returned untouched.
  static const double _accentFloor = .12;
}

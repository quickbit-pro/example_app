import 'package:flutter/material.dart';

import 'example_colors.dart';

// Spacing and radii already live in the shared theme; re-export them so a
// Example screen can `import 'example_tokens.dart'` and get the whole material
// vocabulary (AppSpacing, AppRadii, ExampleColors, borders, shadows, surfaces)
// from one line without duplicating any of it.
export '../../shared/theme/app_spacing.dart' show AppRadii, AppSpacing;
export 'example_colors.dart';

/// Which of the two first-class Example themes a subtree renders in — a
/// two-member **lens** over [ExamplePalette], which is the model. Read that
/// class once for the whole picture.
///
/// This exists because `ExampleTheme.isLight(context)` reads better at a call
/// site that only needs the *question* and none of the ~26 roles that come
/// with the answer. Both members delegate, so there is exactly one place in
/// the vocabulary that asks a `BuildContext` what brightness it is in.
///
/// Twilight (dark) is the default and its output never changes; pearl daylight
/// (light) is an explicit alternative branch on every token below, so a widget
/// that never calls [isLight] keeps rendering exactly the pixels it rendered
/// before the light theme existed.
///
/// `buildAppThemes` gives the Example light theme `Brightness.light`, a
/// [ExampleColors.lightPaper] scaffold and the `ExampleBrand` extension
/// together, and every widget in this vocabulary is Example-only by
/// construction — so brightness alone is a sufficient test here, where a
/// *screen* uses `context.isExampleLight` and pays for the brand check too.
abstract final class ExampleTheme {
  /// True under the Example light theme (pearl daylight).
  /// Same as `ExamplePalette.of(context).isLight`.
  static bool isLight(BuildContext context) =>
      ExamplePalette.of(context).isLight;

  /// Picks between a Twilight and a daylight value. Reads better than a
  /// ternary at a call site that already has three of them.
  /// Same as `ExamplePalette.of(context).pick(dark: ..., light: ...)`.
  static T pick<T>(
    BuildContext context, {
    required T dark,
    required T light,
  }) =>
      ExamplePalette.of(context).pick(dark: dark, light: light);
}

/// Foreground colours for both themes — a **lens** over [ExamplePalette],
/// which is the model. Every member here is one line long and resolves to a
/// palette role; nothing in this class decides a colour of its own.
///
/// It earns its place because `ExampleInk.secondary(context)` names the *job*
/// (quiet text) where `ExamplePalette.of(context).textSecondary` names the
/// *slot*, and the job is what a screen author is thinking about. 483 call
/// sites agree.
///
/// Twilight puts pearl on night; daylight puts night on paper. The alphas are
/// not symmetric: night ink needs a touch more presence on paper than pearl
/// needs on night, so the light secondary is .72 (7.49:1 on paper) and the
/// light tertiary .58 (4.58:1), against the dark .68 / .53.
///
/// * [primary] (= `palette.ink`): body and titles. 17.9:1 on paper.
/// * [secondary] (= `palette.textSecondary`): subtitles, captions, the label
///   under an icon. Body-grade in both themes — 7.49:1 on paper, 7.97:1 on
///   [ExampleColors.appBackground].
/// * [tertiary] (= `palette.textTertiary`): chevrons, timestamps, nav labels,
///   row subtitles. Body-grade in both themes as of the alpha raises recorded
///   on [ExampleColors.textTertiary] (pearl .53, 5.15:1 on appBackground) and
///   [ExampleColors.lightTextTertiary] (night .58, 4.58:1 on paper). It is the
///   quietest of the three volumes, not a disabled state — `ExampleOpacity`
///   holds that.
/// * [accent] (= `palette.accentFor`): a brand or status hue used as *text or
///   an icon*. Twilight returns the hue untouched; daylight swaps it for the
///   daylight token of the same role. Always pass the palette token —
///   `ExampleInk.accent(context, ExampleColors.success)` — and never a literal.
/// * [selection] / [onSelection] (= `palette.fill` / `palette.onFill`): the
///   filled pill of a selected segment and the label on it. Pearl on the
///   daylight fill is 4.58:1.
abstract final class ExampleInk {
  /// Titles and body.
  static Color primary(BuildContext context) => ExamplePalette.of(context).ink;

  /// Subtitles, captions and labels.
  static Color secondary(BuildContext context) =>
      ExamplePalette.of(context).textSecondary;

  /// Chevrons, timestamps and other quiet glyphs.
  static Color tertiary(BuildContext context) =>
      ExamplePalette.of(context).textTertiary;

  /// [color] at reading strength for the current theme.
  static Color accent(BuildContext context, Color color) =>
      ExamplePalette.of(context).accentFor(color);

  /// Wash behind an accent glyph (status pill, icon tile).
  static Color tint(BuildContext context, Color color, {double alpha = .13}) =>
      ExamplePalette.of(context).tint(color, alpha: alpha);

  /// Filled surface of the one selected control on the screen.
  static Color selection(BuildContext context) =>
      ExamplePalette.of(context).fill;

  /// Label on [selection]. Pearl in both themes; the fill moves, not the text.
  static Color onSelection(BuildContext context) =>
      ExamplePalette.of(context).onFill;

  /// Hover wash over a row or tile. Same .04, opposite ink.
  static Color hover(BuildContext context) => ExamplePalette.of(context).hover;

  /// Transparent form of [hover], so an `AnimatedContainer` lerps within one
  /// hue instead of passing through grey on the way out.
  static Color hoverOff(BuildContext context) =>
      ExamplePalette.of(context).hoverOff;
}

/// Edge treatments for both themes.
///
/// Which one to reach for:
///
/// * [subtle]: the resting edge of any panel, tile or input. Lavender at .14
///   reads as a boundary on `ExampleSurface.level1` and up without adding
///   visual weight. This is the default; use it unless you have a reason not
///   to.
/// * [emphasis]: the one edge on the screen that is selected, focused or
///   active. Iris at .38 is a state, not a decoration; never apply it to a
///   grid of siblings at once.
/// * [hairline]: a single divider between list rows or above a fixed CTA bar.
///   Prefer it over the `Divider` widget inside Example lists so rows keep a
///   4 pt rhythm and the separator paints inside the row's own bounds.
///
/// The `...Side` / `...All` constants are the Twilight values and never
/// change. The `...Of(context)` resolvers return those under Twilight and the
/// daylight mirrors under the light theme: [ExampleColors.lightBorderSubtle]
/// (lavender .30, where the Twilight edge is lavender .14) for structure and
/// [ExampleColors.lightBorderEmphasis] for the one active edge. Both are as
/// quiet on paper as their Twilight counterparts are on night; a daylight edge
/// that has to clear 3:1 on its own — a focus ring — takes
/// [ExampleColors.lightViolet] at 2 px instead.
///
/// All edges are 1 logical pixel. Do not thicken a border to show state; use
/// [emphasis] or a `ExampleShadows.glow` instead.
abstract final class ExampleBorders {
  /// Resting edge as a [BorderSide], for `Border(...)` compositions and
  /// `CircleBorder(side: ...)`.
  static const BorderSide subtleSide = BorderSide(
    color: ExampleColors.borderSubtle,
  );

  /// Selected / focused / active edge as a [BorderSide].
  static const BorderSide emphasisSide = BorderSide(
    color: ExampleColors.borderEmphasis,
  );

  /// Divider-grade edge as a [BorderSide]. Same tint as [subtleSide]; the
  /// name marks intent (a separator between rows, not a panel outline).
  static const BorderSide hairlineSide = BorderSide(
    color: ExampleColors.borderSubtle,
  );

  /// Daylight form of [subtleSide]: lavender .30 on paper.
  static const BorderSide subtleLightSide = BorderSide(
    color: ExampleColors.lightBorderSubtle,
  );

  /// Daylight form of [emphasisSide]: [ExampleColors.lightViolet] at .55.
  static const BorderSide emphasisLightSide = BorderSide(
    color: ExampleColors.lightBorderEmphasis,
  );

  /// Daylight form of [hairlineSide].
  static const BorderSide hairlineLightSide = subtleLightSide;

  /// Daylight boundary of an *interactive* container: night .58, 4.66:1 on
  /// paper and 4.77:1 on white.
  static const BorderSide controlLightSide = BorderSide(
    color: ExampleColors.lightTextTertiary,
  );

  /// The edge of an interactive container — an input, a secondary button, a
  /// choice tile, an OTP cell, a segmented track.
  ///
  /// WCAG 1.4.11 asks 3:1 of a control's boundary. On paper the structural
  /// hairline ([subtleLightSide], lavender .30) is 1.18:1, so daylight draws
  /// controls with tertiary ink instead. Twilight returns the structural edge
  /// unchanged — its own 1.24:1 shortfall is pre-existing and only a
  /// dark-pixel mandate may move it.
  ///
  /// Structural hairlines and dividers keep [subtleSideOf]. This is the
  /// boundary of something the user operates.
  static BorderSide controlSideOf(BuildContext context, {double width = 1}) {
    // Both branches are palette roles, not new literals: on dark
    // `borderSubtle` *is* ExampleColors.borderSubtle and on light
    // `textTertiary` *is* ExampleColors.lightTextTertiary, so this draws the
    // same two edges it always drew while naming them from the model.
    final palette = ExamplePalette.of(context);
    return BorderSide(
      color:
          palette.pick(dark: palette.borderSubtle, light: palette.textTertiary),
      width: width,
    );
  }

  /// Const form of [subtle] for use inside `const BoxDecoration(...)`.
  static const Border subtleAll = Border.fromBorderSide(subtleSide);

  /// Const form of [emphasis] for use inside `const BoxDecoration(...)`.
  static const Border emphasisAll = Border.fromBorderSide(emphasisSide);

  /// Daylight form of [subtleAll].
  static const Border subtleLightAll = Border.fromBorderSide(subtleLightSide);

  /// Daylight form of [emphasisAll].
  static const Border emphasisLightAll =
      Border.fromBorderSide(emphasisLightSide);

  /// Resting panel edge on every side.
  static Border subtle({double width = 1}) =>
      Border.all(color: ExampleColors.borderSubtle, width: width);

  /// Selected / focused / active edge on every side.
  static Border emphasis({double width = 1}) =>
      Border.all(color: ExampleColors.borderEmphasis, width: width);

  /// Row divider. Defaults to a bottom hairline; pass `top: true` for the
  /// first row of a group that sits directly under a header.
  static Border hairline({bool top = false, bool bottom = true}) => Border(
        top: top ? hairlineSide : BorderSide.none,
        bottom: bottom ? hairlineSide : BorderSide.none,
      );

  /// Resting edge for the current theme.
  static BorderSide subtleSideOf(BuildContext context) =>
      BorderSide(color: ExamplePalette.of(context).borderSubtle);

  /// Emphasised edge for the current theme.
  static BorderSide emphasisSideOf(BuildContext context) =>
      BorderSide(color: ExamplePalette.of(context).borderEmphasis);

  /// Divider edge for the current theme.
  static BorderSide hairlineSideOf(BuildContext context) =>
      BorderSide(color: ExamplePalette.of(context).borderSubtle);

  /// The resting or the active edge for the current theme, in one call, for a
  /// widget that already carries an `emphasis` flag.
  static BorderSide sideOf(BuildContext context, {bool emphasis = false}) =>
      emphasis ? emphasisSideOf(context) : subtleSideOf(context);

  /// [subtle] for the current theme.
  static Border subtleOf(BuildContext context, {double width = 1}) =>
      Border.all(color: subtleSideOf(context).color, width: width);

  /// [emphasis] for the current theme.
  static Border emphasisOf(BuildContext context, {double width = 1}) =>
      Border.all(color: emphasisSideOf(context).color, width: width);

  /// [hairline] for the current theme.
  static Border hairlineOf(
    BuildContext context, {
    bool top = false,
    bool bottom = true,
  }) {
    final side = hairlineSideOf(context);
    return Border(
      top: top ? side : BorderSide.none,
      bottom: bottom ? side : BorderSide.none,
    );
  }
}

/// Depth for both themes.
///
/// In dark mode depth comes from a lighter surface first ([ExampleSurface]
/// levels), and only then from a shadow. So the order of operations for a
/// raised element is: pick the next surface level up, add a [ExampleBorders]
/// edge, and only if it still needs to float add [lift]. Most panels need no
/// shadow at all.
///
/// On paper it is the other way round: the surface ladder runs from paper to
/// white and has almost no contrast left to spend, so daylight depth *is* the
/// shadow. Use [ambientOf] on anything that rests on the page (list groups,
/// glass panels, circle actions): it is nothing under Twilight and a night
/// ambient at .06 under daylight, which is exactly the "one code path, two
/// explicit branches" contract.
///
/// * [none]: the default for panels, list rows, tiles and inputs.
/// * [ambientOf]: a surface resting on the page. Twilight: none. Daylight:
///   night .06, blur 24, y 8.
/// * [lift] / [liftOf]: a raised card or a dragged item. Twilight: one soft
///   violet-hued shadow pulled in with a negative spread. Daylight: night .10,
///   blur 24, y 8.
/// * [sheet] / [sheetOf]: bottom sheets, menus and popovers that hover over
///   content. A night-toned shadow cast upward in both themes.
/// * [glow] / [glowOf]: an active accent that needs energy (selected segment,
///   primary payment card, success state). Pass the accent colour; keep it to
///   one element per screen. On paper [glowOf] drops the bloom to .45 of its
///   alpha and puts the ambient underneath it, so the element is lit *and*
///   grounded instead of floating in a violet haze.
abstract final class ExampleShadows {
  static const List<BoxShadow> none = [];

  /// Raised card. Violet at .15, blur 24, y 10, spread -8.
  static const List<BoxShadow> lift = [
    BoxShadow(
      color: Color(0x267B6CF6), // ExampleColors.violet at .15
      blurRadius: 24,
      offset: Offset(0, 10),
      spreadRadius: -8,
    ),
  ];

  /// Sheet or menu floating over the page. App background at .60, cast
  /// upward.
  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color(0x99050713), // ExampleColors.appBackground at .60
      blurRadius: 32,
      offset: Offset(0, -8),
      spreadRadius: -12,
    ),
  ];

  /// Daylight resting shadow: [ExampleColors.lightShadowAmbient] (night .06),
  /// blur 24, y 8.
  static const List<BoxShadow> ambientLight = [
    BoxShadow(
      color: ExampleColors.lightShadowAmbient,
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -10,
    ),
  ];

  /// Daylight raised shadow: [ExampleColors.lightShadowLift] (night .10),
  /// blur 24, y 8.
  static const List<BoxShadow> liftLight = [
    BoxShadow(
      color: ExampleColors.lightShadowLift,
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  /// Daylight sheet shadow: night .10, blur 32, cast upward.
  static const List<BoxShadow> sheetLight = [
    BoxShadow(
      color: ExampleColors.lightShadowLift,
      blurRadius: 32,
      offset: Offset(0, -8),
      spreadRadius: -12,
    ),
  ];

  /// How much of a [glow] survives on paper. A bloom that reads as light on
  /// night reads as a smudge on white.
  static const double _lightGlowScale = .45;

  /// Accent bloom in [color]. [spread] is negative by default so the glow
  /// stays tucked under the element; raise it toward 0 for a halo. [alpha]
  /// and [blur] are exposed so callers can match the three existing glows in
  /// `example_ui.dart` (payment card .18/26, glass emphasis .35/30, selected
  /// segment .45/14) without inventing new literals.
  static List<BoxShadow> glow(
    Color color, {
    double spread = -6,
    double alpha = .35,
    double blur = 24,
    Offset offset = Offset.zero,
  }) =>
      [
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: blur,
          spreadRadius: spread,
          offset: offset,
        ),
      ];

  /// Resting shadow for the current theme: none under Twilight,
  /// [ambientLight] under daylight.
  static List<BoxShadow> ambientOf(BuildContext context) {
    final palette = ExamplePalette.of(context);
    if (!palette.design.isConfigured) {
      return palette.pick(dark: none, light: ambientLight);
    }
    return palette.isDark
        ? none
        : [ambientLight.first.copyWith(color: palette.shadowAmbient)];
  }

  /// [lift] for the current theme.
  static List<BoxShadow> liftOf(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final legacy = palette.pick(dark: lift, light: liftLight);
    return palette.design.isConfigured
        ? [legacy.first.copyWith(color: palette.shadowLift)]
        : legacy;
  }

  /// [sheet] for the current theme.
  static List<BoxShadow> sheetOf(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final legacy = palette.pick(dark: sheet, light: sheetLight);
    return palette.design.isConfigured
        ? [
            legacy.first.copyWith(
                color:
                    palette.isDark ? palette.shadowAmbient : palette.shadowLift)
          ]
        : legacy;
  }

  /// [glow] for the current theme.
  static List<BoxShadow> glowOf(
    BuildContext context,
    Color color, {
    double spread = -6,
    double alpha = .35,
    double blur = 24,
    Offset offset = Offset.zero,
  }) {
    final palette = ExamplePalette.of(context);
    final resolved =
        palette.design.isConfigured ? palette.accentFor(color) : color;
    if (palette.isDark) {
      return glow(
        resolved,
        spread: spread,
        alpha: alpha,
        blur: blur,
        offset: offset,
      );
    }
    return [
      ...ambientOf(context),
      ...glow(
        resolved,
        spread: spread,
        alpha: alpha * _lightGlowScale,
        blur: blur,
        offset: offset,
      ),
    ];
  }
}

/// Surface ladder for both themes — the const half of the model, plus a
/// **lens** onto [ExamplePalette] for the resolved half. Higher level, closer
/// to the viewer.
///
/// The `level*` / `light*` constants below are here because a `const`
/// `BoxDecoration` cannot read a `BuildContext`; they are the same literals
/// [ExamplePalette.dark] and [ExamplePalette.light] name in their `paper`,
/// `surface`, `surfaceSubtle`, `surfaceHigh` and `navigation` roles. Anything
/// that *can* take a context should call [of] and get the resolved answer.
///
/// Twilight climbs by getting lighter; daylight climbs by going white first
/// and then lavender, which is why the two ladders are not mirror images:
/// level 1 on paper is plain white (the panel), and the tinted steps sit above
/// it. Pair a daylight level with `ExampleShadows.ambientOf` — on paper the
/// step alone is not separation.
///
/// * [level0] / [light0]: the page. `Scaffold` background, the ground under
///   everything. Paper F8F5FC in daylight.
/// * [level1] / [light1]: panels, cards and list groups resting on the page.
///   Plain white in daylight.
/// * [level2] / [light2]: an element resting on a level-1 panel (an input
///   inside a card, a chip inside a list row), and the pressed tint of a
///   level-1 control. Never nest a third card; use spacing or a hairline
///   instead.
/// * [level3] / [light3]: the one selected or highlighted element. Indigo
///   tinted on night, lavender tinted on paper, so it also reads as brand.
///   Use for the active tab, the chosen plan, the current card.
/// * [navigation] / [lightNavigation]: bars and rails. Separated from the page
///   by tone in Twilight and by being plain white in daylight.
abstract final class ExampleSurface {
  static const Color level0 = ExampleColors.appBackground;
  static const Color level1 = ExampleColors.darkSurface;
  static const Color level2 = ExampleColors.darkSurfaceSubtle;
  static const Color level3 = ExampleColors.darkSurfaceHigh;
  static const Color navigation = ExampleColors.navigationSurface;

  static const Color light0 = ExampleColors.lightPaper;
  static const Color light1 = ExampleColors.lightSurface;
  static const Color light2 = ExampleColors.lightSurfaceSubtle;
  static const Color light3 = ExampleColors.lightSurfaceHigh;
  static const Color lightNavigation = ExampleColors.lightNavigationSurface;

  /// Surface for [level], clamped to 0..3, in the theme of [context]. Handy
  /// when nesting depth is computed
  /// (`ExampleSurface.of(context, parentLevel + 1)`).
  ///
  /// Same as `ExamplePalette.of(context).surfaceLevel(level)`. The ladder used
  /// to be switched twice — once per brightness, here — which meant a role
  /// could drift from the palette that names the same colour. It resolves
  /// through the model now, so it cannot.
  static Color of(BuildContext context, int level) =>
      ExamplePalette.of(context).surfaceLevel(level);

  /// Surface for [level] under an explicit [brightness], for painters and
  /// other places with no element to read the theme from.
  static Color forBrightness(Brightness brightness, int level) =>
      ExamplePalette.forBrightness(brightness).surfaceLevel(level);

  /// Bar and rail surface in the theme of [context].
  /// Same as `ExamplePalette.of(context).navigation`.
  static Color navigationOf(BuildContext context) =>
      ExamplePalette.of(context).navigation;
}

/// The one alpha in the system that is a *state*, not a volume.
///
/// Text and icon volumes belong to [ExampleInk], which resolves hue and alpha
/// together and is theme-correct by construction. This class used to mirror
/// those volumes as bare doubles — `secondary`, `tertiary`, `secondaryLight`,
/// `tertiaryLight` and two resolvers over them — and every one of the six had
/// zero call sites while three had drifted to describing alphas the tokens no
/// longer use (`tertiary` claimed pearl .46 against an actual .53,
/// `tertiaryLight` night .50 against .58). Dead code that lies about the
/// design is worse than no code, so it is gone; use [ExampleInk].
abstract final class ExampleOpacity {
  /// Disabled control: the whole control, foreground and all, at .38.
  ///
  /// Matches the value `ExampleCircleAction` already used, and reads the same
  /// on paper — a disabled affordance is meant to fail the contrast floors in
  /// both themes, which is exactly why it is not a [ExampleInk] volume.
  static const double disabled = .38;
}

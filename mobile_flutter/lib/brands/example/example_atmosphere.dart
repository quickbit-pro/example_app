import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import 'example_colors.dart';
import 'example_ui.dart' show ExampleBrand;

/// One radial light source in a [ExampleAtmosphere].
///
/// The falloff is core, mid, transparent: [color] at [alpha] in the centre,
/// [mid] (defaulting to [color]) at [midAlpha] by [midStop], and the mid hue
/// at zero alpha on the rim. The tail keeps the mid hue instead of lerping to
/// `Colors.transparent`, so the light never dips through grey on the way out.
///
/// [center] and [radius] follow [RadialGradient]: an [Alignment] inside the
/// painted box, and a fraction of its shortest side.
@immutable
class ExampleAtmosphereGlow {
  const ExampleAtmosphereGlow({
    required this.color,
    required this.center,
    this.radius = 1,
    this.alpha = .24,
    this.mid,
    this.midAlpha,
    this.midStop = .42,
  });

  /// Hue at the core.
  final Color color;

  /// Where the light is centred, as an [Alignment] in the painted box.
  final Alignment center;

  /// Reach of the light as a fraction of the box's shortest side.
  final double radius;

  /// Alpha at the core.
  final double alpha;

  /// Hue at [midStop]. Defaults to [color].
  final Color? mid;

  /// Alpha at [midStop]. Defaults to `alpha * .4`.
  final double? midAlpha;

  /// Position of the mid stop, 0..1 along the radius.
  final double midStop;

  /// Shader for [rect]. [intensity] scales every alpha; the light theme paints
  /// at .4 so the same presets read as a tint on paper.
  Shader shader(Rect rect, {double intensity = 1}) {
    final midColor = mid ?? color;
    final coreAlpha = (alpha * intensity).clamp(0.0, 1.0).toDouble();
    final midA =
        ((midAlpha ?? alpha * .4) * intensity).clamp(0.0, 1.0).toDouble();
    return RadialGradient(
      center: center,
      radius: radius,
      colors: [
        color.withValues(alpha: coreAlpha),
        midColor.withValues(alpha: midA),
        midColor.withValues(alpha: 0),
      ],
      stops: [0, midStop, 1],
    ).createShader(rect);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExampleAtmosphereGlow &&
          other.color == color &&
          other.center == center &&
          other.radius == radius &&
          other.alpha == alpha &&
          other.mid == mid &&
          other.midAlpha == midAlpha &&
          other.midStop == midStop;

  @override
  int get hashCode =>
      Object.hash(color, center, radius, alpha, mid, midAlpha, midStop);
}

/// Paints a [ExampleAtmosphere]: the base colour, every glow in order, then the
/// optional horizon hairline. Gradients only, no blur and no noise, so it is
/// one cheap fill pass on Flutter web. Static: it repaints only when an input
/// changes.
class ExampleAtmospherePainter extends CustomPainter {
  const ExampleAtmospherePainter({
    required this.base,
    required this.glows,
    this.horizon,
    this.horizonColor = ExampleColors.borderSubtle,
    this.intensity = 1,
  });

  /// Ground colour under the lights.
  final Color base;

  /// Lights, painted in order; the first is the primary.
  final List<ExampleAtmosphereGlow> glows;

  /// Vertical position of the 1 px horizon hairline, 0..1 of the height.
  /// Null paints none.
  final double? horizon;

  /// Peak colour of the hairline; it fades to nothing at both ends.
  final Color horizonColor;

  /// Multiplier on every glow alpha.
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    for (final glow in glows) {
      canvas.drawRect(
        rect,
        Paint()..shader = glow.shader(rect, intensity: intensity),
      );
    }
    final y = horizon;
    if (y == null) return;
    final line = Rect.fromLTWH(
      0,
      (size.height * y).floorToDouble(),
      size.width,
      1,
    );
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: [
            horizonColor.withValues(alpha: 0),
            horizonColor,
            horizonColor.withValues(alpha: 0),
          ],
          stops: const [0, .5, 1],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(ExampleAtmospherePainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.horizon != horizon ||
      oldDelegate.horizonColor != horizonColor ||
      oldDelegate.intensity != intensity ||
      !listEquals(oldDelegate.glows, glows);
}

/// Full-bleed static backdrop for Twilight screens.
///
/// Two lights on [ExampleColors.appBackground]: a violet or indigo dawn glow
/// and a cooler teal counter-glow at five to nine percent from the opposite
/// corner, so a screen has temperature contrast instead of one flat purple
/// haze. Nothing animates; the page boot and the orbit loader are the only
/// motion the brand ground ever carries.
///
/// Pick the preset by what the screen is for:
///
/// * [ExampleAtmosphere.auth]: the dawn. Login, signup, account claim, the
///   first-run setup. Strongest glow, the brand boot lands on it.
/// * [ExampleAtmosphere.home]: the dashboard. Indigo from the top-left, calmer,
///   so dense content and the payment card carry the light.
/// * [ExampleAtmosphere.card]: Cards and card detail. A violet halo behind the
///   upper third where the card sits, with the counter-glow low and left.
/// * [ExampleAtmosphere.quiet]: every utility screen (settings, lists, forms,
///   KYC). A faint indigo cap and a whisper of teal; hierarchy, not a moment.
///
/// [horizon] draws a 1 px lavender hairline across the screen at that fraction
/// of the height, fading at both ends, like the line where sky meets ground.
/// Presets leave it off; a screen that knows its layout can place it under a
/// hero (the card on Cards, the lockup on login) so the element reads as
/// resting on something. Never place it behind text.
///
/// Wrap the `Scaffold` (with a transparent background) as [child], or leave
/// [child] null to use it as a backdrop layer in a `Stack`. The painter sits in
/// its own [RepaintBoundary], so scrolling and state changes in [child] never
/// repaint the gradients.
///
/// Both themes are first-class. Under a Example light theme (scaffold on
/// [ExampleColors.lightPaper]) the ground becomes paper, the horizon hairline
/// becomes [ExampleColors.lightBorder], and every preset swaps to its daylight
/// lights: a violet dawn peaking at six to eight percent on paper plus the
/// same cool teal counter-glow, four to six percent, from the opposite corner.
/// Indigo is dropped on paper — at any alpha that reads, it greys the page
/// instead of tinting it. Pass [base] to pin the ground, or [lightGlows] to
/// give a custom atmosphere its own daylight lights; a custom atmosphere
/// without [lightGlows] keeps the old behaviour and paints [glows] at .4.
///
/// Daylight alphas below are stated *before* the light intensity the painter
/// applies: .80 for a preset that authored [lightGlows] (so `_authLight`'s
/// violet peaks at .20 * .80 = .16), and .4 for a custom atmosphere that has
/// none and is therefore painting Twilight glows onto paper.
class ExampleAtmosphere extends StatelessWidget {
  const ExampleAtmosphere({
    required this.glows,
    this.lightGlows,
    this.child,
    this.base,
    this.horizon,
    super.key,
  });

  /// The dawn: violet from the top, teal low and right.
  const ExampleAtmosphere.auth({this.child, this.horizon, super.key})
      : glows = _auth,
        lightGlows = _authLight,
        base = null;

  /// The dashboard: indigo from the top-left, teal low and right. On paper the
  /// indigo becomes violet, since indigo on white greys rather than tints.
  const ExampleAtmosphere.home({this.child, this.horizon, super.key})
      : glows = _home,
        lightGlows = _homeLight,
        base = null;

  /// Cards: a violet halo behind the upper third, teal low and left.
  const ExampleAtmosphere.card({this.child, this.horizon, super.key})
      : glows = _card,
        lightGlows = _cardLight,
        base = null;

  /// Utility screens: a faint indigo cap and a whisper of teal.
  const ExampleAtmosphere.quiet({this.child, this.horizon, super.key})
      : glows = _quiet,
        lightGlows = _quietLight,
        base = null;

  /// Lights, painted in order over [base].
  final List<ExampleAtmosphereGlow> glows;

  /// Lights used instead of [glows] under a Example light theme. Null paints
  /// [glows] on paper at .4, which is the right answer for a one-off
  /// atmosphere and the wrong one for a preset.
  final List<ExampleAtmosphereGlow>? lightGlows;

  /// Content over the backdrop, usually a transparent `Scaffold`.
  final Widget? child;

  /// Ground colour. Null resolves to [ExampleColors.appBackground], or
  /// [ExampleColors.lightPaper] under a Example light theme.
  final Color? base;

  /// Vertical position of the optional horizon hairline, 0..1.
  final double? horizon;

  static const List<ExampleAtmosphereGlow> _auth = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -1.05),
      radius: 1.15,
      alpha: .38,
      mid: ExampleColors.indigo,
      midAlpha: .55,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1.1, 1.05),
      radius: .9,
      alpha: .07,
      midStop: .45,
    ),
  ];

  static const List<ExampleAtmosphereGlow> _home = [
    ExampleAtmosphereGlow(
      color: ExampleColors.indigo,
      center: Alignment(-.7, -1),
      radius: 1,
      alpha: .7,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1, .9),
      radius: .8,
      alpha: .06,
      midStop: .45,
    ),
  ];

  static const List<ExampleAtmosphereGlow> _card = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -.55),
      radius: .85,
      alpha: .3,
      mid: ExampleColors.indigo,
      midAlpha: .45,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(-1, 1.1),
      radius: .8,
      alpha: .05,
      midStop: .45,
    ),
  ];

  static const List<ExampleAtmosphereGlow> _quiet = [
    ExampleAtmosphereGlow(
      color: ExampleColors.indigo,
      center: Alignment(0, -1.1),
      radius: 1,
      alpha: .45,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1, 1.1),
      radius: .8,
      alpha: .04,
      midStop: .45,
    ),
  ];

  /// The dawn on paper: violet at an effective .08, iris in the falloff, and
  /// the teal counter-glow at .064 low and right.
  static const List<ExampleAtmosphereGlow> _authLight = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -1.05),
      radius: 1.15,
      alpha: .20,
      mid: ExampleColors.iris,
      midAlpha: .13,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1.1, 1.05),
      radius: .9,
      alpha: .16,
      midStop: .45,
    ),
  ];

  /// The dashboard on paper: violet from the top-left at an effective .07,
  /// teal at .056 low and right.
  static const List<ExampleAtmosphereGlow> _homeLight = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(-.7, -1),
      radius: 1,
      alpha: .175,
      mid: ExampleColors.iris,
      midAlpha: .11,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1, .9),
      radius: .8,
      alpha: .14,
      midStop: .45,
    ),
  ];

  /// Cards on paper: a violet halo behind the upper third at an effective
  /// .074, teal at .048 low and left.
  static const List<ExampleAtmosphereGlow> _cardLight = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -.55),
      radius: .85,
      alpha: .185,
      mid: ExampleColors.iris,
      midAlpha: .12,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(-1, 1.1),
      radius: .8,
      alpha: .12,
      midStop: .45,
    ),
  ];

  /// Utility screens on paper: a violet cap at an effective .06 and a whisper
  /// of teal at .04.
  static const List<ExampleAtmosphereGlow> _quietLight = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -1.1),
      radius: 1,
      alpha: .15,
      mid: ExampleColors.iris,
      midAlpha: .09,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1, 1.1),
      radius: .8,
      alpha: .10,
      midStop: .45,
    ),
  ];

  /// Replace familiar legacy light colors even in a screen's custom glow
  /// array. Explicit colors outside the source brand palette stay untouched.
  List<ExampleAtmosphereGlow> _configuredGlows(
    BuildContext context,
    List<ExampleAtmosphereGlow> source,
    ExamplePalette palette,
  ) {
    final design = context.brandDesign;
    if (!design.isConfigured) return source;
    Color resolve(Color color) {
      final secondary = color == ExampleColors.teal;
      final mid = color == ExampleColors.indigo || color == ExampleColors.iris;
      if (!secondary && !mid && color != ExampleColors.violet) return color;
      return design.color(
        palette.brightness,
        secondary
            ? 'atmosphereSecondary'
            : mid
                ? 'atmosphereMid'
                : 'atmospherePrimary',
        fallback: secondary
            ? palette.teal
            : mid
                ? palette.accent
                : palette.fill,
      );
    }

    return source
        .map((glow) => ExampleAtmosphereGlow(
              color: resolve(glow.color),
              center: glow.center,
              radius: glow.radius,
              alpha: glow.alpha,
              mid: glow.mid == null ? null : resolve(glow.mid!),
              midAlpha: glow.midAlpha,
              midStop: glow.midStop,
            ))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ExamplePalette.of(context);
    // Ask the brand, not the scaffold colour: an equality test against
    // lightPaper silently fell back to the Twilight glows at full strength the
    // moment a tenant or a screen changed its ground.
    final light = base == null &&
        theme.brightness == Brightness.light &&
        (theme.extension<ExampleBrand>() != null ||
            theme.scaffoldBackgroundColor == ExampleColors.lightPaper);
    // Daylight budget. .4 left every authored light glow at an effective .08,
    // and the ground composited to a 1.09:1 field — paper with no sky, the
    // strongest "inverted dark theme" tell in the build. .80 more than doubles
    // the travel (paper-to-peak 1.09:1 -> 1.20:1) and still measures, over the
    // brightest preset peak: night ink 14.9:1, secondary 6.34:1, tertiary
    // 3.89:1, lightIris 4.82:1 — every role above its floor. Above .85 the
    // iris links stop clearing 4.5:1, which is what caps it. The fallback
    // stays at .4: a custom atmosphere with no [lightGlows] is painting its
    // DARK glows onto paper, and those were never sized for it.
    final lightIntensity = lightGlows == null ? .4 : .80;
    final painter = ExampleAtmospherePainter(
      base: base ??
          (context.brandDesign.isConfigured
              ? palette.paper
              : light
                  ? ExampleColors.lightPaper
                  : ExampleColors.appBackground),
      glows: _configuredGlows(
          context, light ? (lightGlows ?? glows) : glows, palette),
      horizon: horizon,
      horizonColor: context.brandDesign.isConfigured
          ? palette.borderSubtle
          : light
              ? ExampleColors.lightBorder
              : ExampleColors.borderSubtle,
      intensity: light ? lightIntensity : 1,
    );
    final backdrop = RepaintBoundary(
      child: CustomPaint(painter: painter, size: Size.infinite),
    );
    final content = child;
    if (content == null) return backdrop;
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: backdrop),
        content,
      ],
    );
  }
}

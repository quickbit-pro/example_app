import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter, SemanticsRole;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerExitEvent, PointerHoverEvent;
import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import '../../shared/theme/app_theme_extensions.dart';
import '../../core/models/banking_models.dart';
import '../../core/models/equals_money.dart';
import 'example_atmosphere.dart';
import 'example_mark.dart';
import 'example_motion.dart';
import 'example_route_transition.dart';
import 'example_tokens.dart';

// One import for a Example screen: the component vocabulary below plus the
// mark, the atmosphere, the motion tokens and the wave-1 primitives (amount,
// skeleton, empty and error states). Material tokens (example_tokens.dart)
// are imported explicitly where used, since they re-export ExampleColors and
// AppSpacing and would shadow the imports the 34 existing screens already
// carry; `example.dart` is the barrel that adds tokens and typography for
// screens written from now on.
export 'example_amount.dart';
export 'example_atmosphere.dart';
export 'example_mark.dart';
export 'example_motion.dart';
export 'example_route_transition.dart';
export 'example_skeleton.dart';
export 'example_states.dart';

// Legacy material constants remain valid constructor defaults. Resolve them at
// the paint boundary so customer themes also cover hand-painted components.
Color _configuredColor(BuildContext context, Color legacy,
    {bool artwork = false}) {
  final design = context.brandDesign;
  if (!design.isConfigured) return legacy;
  final palette = artwork
      ? ExamplePalette.fromDesign(Brightness.dark, design)
      : ExamplePalette.of(context);
  return switch (legacy) {
    ExampleColors.night ||
    ExampleColors.appBackground ||
    ExampleColors.lightPaper =>
      palette.paper,
    ExampleColors.indigo || ExampleColors.lightSurfaceHigh => palette.surfaceHigh,
    ExampleColors.glowMid ||
    ExampleColors.darkSurfaceSubtle ||
    ExampleColors.lightSurfaceSubtle =>
      palette.surfaceSubtle,
    ExampleColors.darkSurface || ExampleColors.lightSurface => palette.surface,
    ExampleColors.glassTop || ExampleColors.lightGlassTop => palette.glassTop,
    ExampleColors.glassBottom ||
    ExampleColors.lightGlassBottom =>
      palette.glassBottom,
    ExampleColors.violet || ExampleColors.lightViolet => palette.fill,
    ExampleColors.iris ||
    ExampleColors.lightIris ||
    ExampleColors.lavender =>
      palette.accent,
    ExampleColors.pearl || ExampleColors.lightTextPrimary => palette.ink,
    ExampleColors.textSecondary ||
    ExampleColors.lightTextSecondary =>
      palette.textSecondary,
    ExampleColors.textTertiary ||
    ExampleColors.lightTextTertiary =>
      palette.textTertiary,
    ExampleColors.borderSubtle ||
    ExampleColors.lightBorderSubtle =>
      palette.borderSubtle,
    ExampleColors.borderEmphasis ||
    ExampleColors.lightBorderEmphasis =>
      palette.borderEmphasis,
    ExampleColors.success || ExampleColors.lightSuccess => palette.success,
    ExampleColors.warning || ExampleColors.lightWarning => palette.warning,
    ExampleColors.danger || ExampleColors.lightDanger => palette.danger,
    ExampleColors.teal || ExampleColors.lightTeal => palette.teal,
    _ => legacy,
  };
}

ExamplePalette? _artworkPalette(BuildContext context) =>
    context.brandDesign.isConfigured
        ? ExamplePalette.fromDesign(Brightness.dark, context.brandDesign)
        : null;

extension ExampleThemeContext on BuildContext {
  bool get isExampleTheme {
    final theme = Theme.of(this);
    return theme.extension<ExampleBrand>() != null ||
        theme.scaffoldBackgroundColor == ExampleColors.appBackground;
  }

  /// True on a Example screen rendering in pearl daylight. Screens branch on
  /// this; the vocabulary in this file branches on `ExampleTheme.isLight`,
  /// which is the same brightness test without the brand check, because every
  /// Example component is Example-only by construction.
  bool get isExampleLight =>
      isExampleTheme && Theme.of(this).brightness == Brightness.light;
}

class ExampleBackdrop extends StatelessWidget {
  const ExampleBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) return child;
    return Material(
      color: Colors.transparent,
      child: child,
    );
  }
}

/// Mark plus wordmark. The mark keeps its own spec-exact colour in both
/// themes — it is the identity and never takes ink. The wordmark does: it
/// resolves to the theme's primary ink, which is [ExampleColors.pearl] on
/// Twilight (so dark output is unchanged) and night on Pearl daylight.
/// Without that it painted pearl on #F0ECFB at 1.01:1, i.e. invisible on
/// every light screen.
class ExampleLockup extends StatelessWidget {
  const ExampleLockup({
    this.height = 34,
    this.compact = false,
    this.color,
    super.key,
  });

  final double height;
  final bool compact;

  /// Wordmark ink. Defaults to the theme's primary ink; pass a colour only
  /// where the lockup sits on artwork rather than on a surface.
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExampleMark(size: height),
          SizedBox(width: compact ? 9 : 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ExampleWordmark(
                height: height * .44,
                color: color ?? ExampleInk.primary(context),
              ),
            ),
          ),
        ],
      );
}

/// The card face. Artwork, not surface: it stays night-dark in both themes,
/// exactly as a real card is dark in daylight. What changes on paper is only
/// how it is seated — the violet bloom halves and a night ambient goes under
/// it, so the card rests on the page instead of hovering in a purple haze.
class ExamplePaymentCard extends StatelessWidget {
  const ExamplePaymentCard({
    this.card,
    this.height = 188,
    this.compact = false,
    this.status,
    this.onTap,
    super.key,
  });

  final PaymentCard? card;
  final double height;
  final bool compact;
  final CardStatus? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mini = compact && height < 55;
    final resolvedStatus = status ?? card?.status ?? CardStatus.active;
    final artworkUrl = compact && card?.cardThumbnailUrl.isNotEmpty == true
        ? card!.cardThumbnailUrl
        : card?.artworkUrl ?? '';
    final hasArtwork = artworkUrl.trim().isNotEmpty;
    final contentColor = cardArtworkTextColor(card?.cardTextColor,
        fallback: _configuredColor(context, ExampleColors.pearl, artwork: true));
    final statusLabel = switch (resolvedStatus) {
      CardStatus.active => 'Active',
      CardStatus.frozen => 'Frozen',
      CardStatus.pending => 'Pending',
      CardStatus.cancelled => 'Closed',
    };
    final statusColor = switch (resolvedStatus) {
      CardStatus.active =>
        _configuredColor(context, ExampleColors.success, artwork: true),
      CardStatus.frozen =>
        _configuredColor(context, ExampleColors.warning, artwork: true),
      CardStatus.pending =>
        _configuredColor(context, ExampleColors.iris, artwork: true),
      CardStatus.cancelled =>
        _configuredColor(context, ExampleColors.pearl, artwork: true),
    };
    final content = Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _configuredColor(context, ExampleColors.night, artwork: true),
        borderRadius:
            BorderRadius.circular(context.brandShape.radius(compact ? 11 : 18)),
        border: Border.all(
            color:
                _configuredColor(context, ExampleColors.lavender, artwork: true)
                    .withValues(alpha: .32)),
        boxShadow: ExampleShadows.glowOf(
          context,
          _configuredColor(context, ExampleColors.violet, artwork: true),
          alpha: .18,
          blur: 26,
          spread: 0,
          offset: const Offset(0, 12),
        ),
      ),
      child: Stack(
        children: [
          if (!hasArtwork) ...[
            Positioned(
              right: -height * .20,
              top: -height * .38,
              child: Container(
                width: height * 1.25,
                height: height * 1.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _configuredColor(context, ExampleColors.violet,
                              artwork: true)
                          .withValues(alpha: .42),
                      _configuredColor(context, ExampleColors.indigo,
                              artwork: true)
                          .withValues(alpha: .12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: compact ? 9 : 18,
              bottom: compact ? 5 : 10,
              child: SizedBox.square(
                dimension: height * .54,
                child: context.brandDesign.isConfigured
                    ? ExcludeSemantics(
                        child: ExampleMark(
                          key: const ValueKey('payment-card-brand-artwork'),
                          size: height * .54,
                        ),
                      )
                    : const CustomPaint(painter: _CardRingPainter()),
              ),
            ),
          ] else
            Positioned.fill(
              child: Image.network(
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                artworkUrl,
                key: ValueKey('example-card-artwork-$artworkUrl'),
                fit: BoxFit.cover,
                semanticLabel: card?.cardImageAlt.trim().isNotEmpty == true
                    ? card!.cardImageAlt
                    : context.tr('Card design'),
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (resolvedStatus == CardStatus.frozen)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .32),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(mini
                ? 4
                : compact
                    ? 7
                    : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!hasArtwork)
                      _Chip(
                          size: mini
                              ? 10
                              : compact
                                  ? 15
                                  : 32),
                    if (!compact) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(
                              context.brandShape.radius(99)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: (compact ? 9 : 11) *
                                    context.brandDesign.typographyScale,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                if (hasArtwork && !compact && card?.last4.isNotEmpty == true)
                  Text(
                    '••••  ${card!.last4}',
                    style: TextStyle(
                      color: contentColor,
                      fontSize: 11 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  )
                else if (mini && !hasArtwork)
                  const ExampleMark(size: 10)
                else if (!hasArtwork)
                  // Explicit pearl: this lockup sits on the card artwork,
                  // which stays dark in BOTH themes, so it must not follow the
                  // page's ink. Without it the daylight wordmark resolved to
                  // night ink and the brand's hero object shipped unbranded.
                  ExampleLockup(
                    height: compact ? 14 : 23,
                    compact: true,
                    color: _configuredColor(context, ExampleColors.pearl,
                        artwork: true),
                  ),
                if (!compact && !hasArtwork) ...[
                  const SizedBox(height: 6),
                  Text(
                    card?.last4.isNotEmpty == true
                        ? '••••  ${card!.last4}'
                        : context.brandDesign.isConfigured
                            ? context.tr('PAYMENT CARD')
                            : context.tr('METAL · LIMITED EDITION'),
                    style: TextStyle(
                      color: _configuredColor(context, ExampleColors.pearl,
                              artwork: true)
                          .withValues(alpha: .66),
                      fontSize: 10 * context.brandDesign.typographyScale,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(context.brandShape.radius(compact ? 11 : 18)),
        child: content,
      ),
    );
  }
}

Color cardArtworkTextColor(String? value, {Color fallback = ExampleColors.pearl}) {
  final normalized = value?.trim().replaceFirst('#', '') ?? '';
  if (normalized.length != 6 && normalized.length != 8) {
    return fallback;
  }
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return fallback;
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}

class _Chip extends StatelessWidget {
  const _Chip({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size * 1.3,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          gradient: const LinearGradient(
            colors: [Color(0xFFE8E5F1), Color(0xFF8E91A0)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .38)),
        ),
        child: CustomPaint(painter: _ChipPainter()),
      );
}

class _CardRingPainter extends CustomPainter {
  const _CardRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
      ..color = ExampleColors.violet.withValues(alpha: .5);
    canvas.drawArc(rect, -.3, math.pi * 1.45, false, glow);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [ExampleColors.violet, ExampleColors.lavender, ExampleColors.iris],
      ).createShader(rect);
    canvas.drawArc(rect, -.3, math.pi * 1.45, false, line);
    canvas.drawCircle(
      rect.center,
      rect.width * .31,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ExampleColors.lavender.withValues(alpha: .55),
    );
  }

  @override
  bool shouldRepaint(covariant _CardRingPainter oldDelegate) => false;
}

class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = ExampleColors.night.withValues(alpha: .55);
    canvas
      ..drawLine(Offset(size.width * .34, 0),
          Offset(size.width * .34, size.height), paint)
      ..drawLine(Offset(size.width * .67, 0),
          Offset(size.width * .67, size.height), paint)
      ..drawLine(Offset(0, size.height * .5),
          Offset(size.width, size.height * .5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Marks a [ThemeData] as the EXAMPLE Twilight brand so widgets can detect the
/// brand even when a shell overrides scaffold or app-bar backgrounds.
@immutable
class ExampleBrand extends ThemeExtension<ExampleBrand> {
  const ExampleBrand();

  @override
  ExampleBrand copyWith() => this;

  @override
  ExampleBrand lerp(ThemeExtension<ExampleBrand>? other, double t) => this;
}

/// Radial Indigo-to-Night depth used behind every Twilight screen.
///
/// Painted through [ExampleAtmosphere] as core, mid, transparent over
/// [ExampleColors.night]: indigo at the top edge, [ExampleColors.glowMid] at
/// 42 percent, then the mid hue fading to nothing so the night ground shows
/// through. With no [secondary] this renders the same pixels as the original
/// two-colour version, so the shells and auth screens built on it do not move.
/// Pass [secondary] (teal, or indigo for a cooler indigo) to add the
/// counter-glow from the opposite corner that gives a screen temperature
/// contrast. New screens should reach for a [ExampleAtmosphere] preset instead.
///
/// In pearl daylight the same light is painted soft on paper: a violet dawn at
/// seven percent with iris in the falloff instead of the indigo-to-glowMid
/// ramp, and [secondary] at .6 of [secondaryAlpha]. Indigo is dropped, because
/// on white it greys the page rather than tinting it.
class ExampleGlow extends StatelessWidget {
  const ExampleGlow({
    required this.child,
    this.desktop = false,
    this.secondary,
    this.secondaryAlpha = .07,
    this.secondaryCenter = const Alignment(1, 1.1),
    super.key,
  });

  final Widget child;
  final bool desktop;

  /// Cooler counter-glow hue. Null, the default, paints none.
  final Color? secondary;

  /// Peak alpha of [secondary]. Keep it between .05 and .09; the counter-glow
  /// is felt, not seen.
  final double secondaryAlpha;

  /// Where [secondary] is centred; the bottom-right corner by default.
  final Alignment secondaryCenter;

  @override
  Widget build(BuildContext context) {
    final counter = secondary;
    if (ExampleTheme.isLight(context)) {
      return ExampleAtmosphere(
        base: _configuredColor(context, ExampleColors.lightPaper),
        glows: [
          ExampleAtmosphereGlow(
            color: _configuredColor(context, ExampleColors.violet),
            alpha: .07,
            mid: _configuredColor(context, ExampleColors.iris),
            midAlpha: .045,
            midStop: .42,
            center: Alignment(0, desktop ? -1.2 : -1.16),
            radius: desktop ? 1.2 : 1.3,
          ),
          if (counter != null)
            ExampleAtmosphereGlow(
              color: counter,
              alpha: secondaryAlpha * .6,
              center: secondaryCenter,
              radius: .9,
            ),
        ],
        child: child,
      );
    }
    return ExampleAtmosphere(
      base: _configuredColor(context, ExampleColors.night),
      glows: [
        ExampleAtmosphereGlow(
          color: _configuredColor(context, ExampleColors.indigo),
          alpha: 1,
          mid: _configuredColor(context, ExampleColors.glowMid),
          midAlpha: 1,
          midStop: .42,
          center: Alignment(0, desktop ? -1.2 : -1.16),
          radius: desktop ? 1.2 : 1.3,
        ),
        if (counter != null)
          ExampleAtmosphereGlow(
            color: counter,
            alpha: secondaryAlpha,
            center: secondaryCenter,
            radius: .9,
          ),
      ],
      child: child,
    );
  }
}

/// Surface finish of a [ExampleGlassPanel].
enum ExampleGlassMaterial {
  /// The Twilight gradient (glassTop to glassBottom) with a lavender edge.
  /// The default, and the right answer for anything resting on the page:
  /// list rows, cards, inputs, settings groups.
  matte,

  /// Real blur through the panel plus a lit top edge. Only over an atmosphere
  /// or artwork; see [ExampleGlassPanel].
  frosted,
}

/// Lavender-edged glass card from the Example App design canvas.
///
/// [material] picks the finish. [ExampleGlassMaterial.matte] is the default
/// and renders exactly as before. [ExampleGlassMaterial.frosted] is rare and
/// purposeful: use it only where the panel floats over an atmosphere or
/// artwork it can actually blur, which means the bottom navigation bar, the
/// install banner, a sheet header, or an overlay on a card face. Never frost
/// a panel resting on a flat surface (there is nothing to blur and the filter
/// still pays for a full-size readback), never frost a list of rows, and
/// never stack frosted panels. Frosted falls back to matte when the platform
/// asks for high contrast, so text on it always keeps its ground.
///
/// Both themes are first-class. In pearl daylight the finishes invert their
/// materials: frosted becomes white at .60 behind the same 18-sigma blur with
/// a white lit top edge, matte becomes white settling into
/// [ExampleColors.lightSurfaceSubtle], both edged with the daylight hairline,
/// and the depth that Twilight got from a lighter surface comes from
/// `ExampleShadows.ambientOf` instead. [emphasis] keeps its violet: a lavender
/// tinted fill, a solid violet edge (3.96:1 on white) and the bloom at .45.
/// [borderAlpha] applies to Twilight only; on paper the hairline is opaque,
/// because an alpha edge on white is not an edge.
class ExampleGlassPanel extends StatelessWidget {
  const ExampleGlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 18,
    this.borderAlpha = .22,
    this.onTap,
    this.emphasis = false,
    this.material = ExampleGlassMaterial.matte,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double borderAlpha;
  final VoidCallback? onTap;
  final bool emphasis;

  /// Surface finish. Matte unless the panel sits over something to blur.
  final ExampleGlassMaterial material;

  /// Blur sigma of the frosted finish.
  static const double frostSigma = 18;

  @override
  Widget build(BuildContext context) {
    final frosted = material == ExampleGlassMaterial.frosted &&
        !(MediaQuery.maybeHighContrastOf(context) ?? false);
    return frosted ? _frosted(context) : _matte(context);
  }

  Widget _frosted(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    final borderRadius =
        BorderRadius.circular(context.brandShape.radius(radius));
    final tint = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: light
            ? (emphasis
                ? [
                    _configuredColor(context, ExampleColors.lightSurfaceHigh)
                        .withValues(alpha: .80),
                    _configuredColor(context, ExampleColors.lightGlassBottom),
                  ]
                : [
                    _configuredColor(context, ExampleColors.lightGlassTop),
                    _configuredColor(context, ExampleColors.lightGlassBottom),
                  ])
            : (emphasis
                ? [
                    _configuredColor(context, ExampleColors.indigo)
                        .withValues(alpha: .55),
                    _configuredColor(context, ExampleColors.night)
                        .withValues(alpha: .78),
                  ]
                : [
                    _configuredColor(context, ExampleColors.glassTop)
                        .withValues(alpha: .46),
                    _configuredColor(context, ExampleColors.glassBottom)
                        .withValues(alpha: .66),
                  ]),
      ),
      borderRadius: borderRadius,
      border: Border.all(
        color: light
            ? ExampleBorders.sideOf(context, emphasis: emphasis).color
            : _configuredColor(context, ExampleColors.iris)
                .withValues(alpha: emphasis ? .5 : borderAlpha),
      ),
    );
    Widget body = Padding(padding: padding, child: child);
    body = Material(
      color: Colors.transparent,
      child: onTap == null
          ? body
          : InkWell(onTap: onTap, borderRadius: borderRadius, child: body),
    );
    // Shadow outside the clip, blur bounded to the panel, tint and content
    // over the blur, and the lit edge last so it reads as glass catching
    // light rather than a border.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: emphasis
            ? ExampleShadows.glowOf(
                context,
                _configuredColor(context, ExampleColors.violet),
                spread: -8,
                blur: 30,
              )
            : ExampleShadows.ambientOf(context),
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: frostSigma, sigmaY: frostSigma),
            child: Stack(
              // passthrough, not the default loose: a frosted bar is handed a
              // tight width by its parent and must pass it to the body, or a
              // full-bleed CTA inside collapses to its label. Same trap as
              // the sheen overlay.
              fit: StackFit.passthrough,
              alignment: Alignment.topLeft,
              children: [
                DecoratedBox(decoration: tint, child: body),
                Positioned(
                  top: 0,
                  left: radius,
                  right: radius,
                  height: 1,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: light
                              ? [
                                  _configuredColor(
                                          context, ExampleColors.lightSurface)
                                      .withValues(alpha: 0),
                                  _configuredColor(
                                          context, ExampleColors.lightSurface)
                                      .withValues(alpha: .85),
                                  _configuredColor(
                                          context, ExampleColors.lightSurface)
                                      .withValues(alpha: 0),
                                ]
                              : [
                                  _configuredColor(
                                          context, ExampleColors.lavender)
                                      .withValues(alpha: 0),
                                  _configuredColor(
                                          context, ExampleColors.lavender)
                                      .withValues(alpha: .32),
                                  _configuredColor(
                                          context, ExampleColors.lavender)
                                      .withValues(alpha: 0),
                                ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _matte(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: light
            ? (emphasis
                ? [
                    _configuredColor(context, ExampleColors.lightSurfaceHigh),
                    _configuredColor(context, ExampleColors.lightSurfaceSubtle),
                  ]
                : [
                    _configuredColor(context, ExampleColors.lightSurface),
                    _configuredColor(context, ExampleColors.lightSurfaceSubtle),
                  ])
            : (emphasis
                ? [
                    _configuredColor(context, ExampleColors.indigo)
                        .withValues(alpha: .75),
                    _configuredColor(context, ExampleColors.night)
                        .withValues(alpha: .95),
                  ]
                : [
                    _configuredColor(context, ExampleColors.glassTop),
                    _configuredColor(context, ExampleColors.glassBottom)
                  ]),
      ),
      borderRadius: BorderRadius.circular(context.brandShape.radius(radius)),
      border: Border.all(
        color: light
            ? ExampleBorders.sideOf(context, emphasis: emphasis).color
            : _configuredColor(context, ExampleColors.iris)
                .withValues(alpha: emphasis ? .5 : borderAlpha),
      ),
      boxShadow: emphasis
          ? ExampleShadows.glowOf(
              context,
              _configuredColor(context, ExampleColors.violet),
              spread: -8,
              blur: 30,
            )
          : ExampleShadows.ambientOf(context),
    );
    final content = Ink(
      padding: padding,
      decoration: decoration,
      child: child,
    );
    if (onTap == null) {
      return Material(color: Colors.transparent, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.brandShape.radius(radius)),
        child: content,
      ),
    );
  }
}

/// One-pixel conic light around a hero element: violet into iris where the
/// light lands, fading to nothing along the far edge, the way a foil edge
/// catches a lamp. Static; there is no loop, and nothing to reduce.
///
/// Exactly one per screen: the payment card on Cards, the primary balance
/// panel on Home. A second sweep on the same screen turns a highlight into a
/// pattern. [angle] is where the rim is brightest, in radians clockwise from
/// three o'clock; the default lights the upper-right edge. [radius] must match
/// the child's corner radius so the stroke hugs the corners, and the child
/// should drop its own border so the two do not fight.
class ExampleSweepBorder extends StatelessWidget {
  const ExampleSweepBorder({
    required this.child,
    this.angle = -math.pi / 3,
    this.radius = AppRadii.md,
    this.width = 1,
    this.color = ExampleColors.violet,
    this.highlight = ExampleColors.iris,
    this.floor = .17,
    this.peak = .62,
    super.key,
  });

  final Widget child;

  /// Where the light peaks, in radians clockwise from three o'clock.
  final double angle;

  /// Corner radius of the stroke; match the child's.
  final double radius;

  /// Stroke width in logical pixels. One is the design; do not thicken it to
  /// show state.
  final double width;

  /// Hue of the lit arc as it fades.
  final Color color;

  /// Hue at the peak of the arc.
  final Color highlight;

  /// Alpha the rim rests at once the lit arc has passed.
  ///
  /// A specular highlight brightens an edge that is already there; it does not
  /// conjure one out of nothing. This used to fade to zero, which left a panel
  /// with a bright rule down one side and no edge whatsoever on the other
  /// three — an asymmetry with nothing to balance it, which at 1 px on a dark
  /// ground reads as a rendering fault rather than as light. Resting at a low
  /// alpha closes the rim, so the arc is a brightening of an edge instead of
  /// the only edge.
  final double floor;

  /// Alpha at the peak of the arc.
  ///
  /// Below 1 on purpose. A one-pixel stroke at full accent is ink, not light:
  /// it is the hardest, most saturated line on the panel, and the eye reads it
  /// as a drawn border that someone forgot to finish. Backing the peak off
  /// leaves the falloff — floor to peak and back — doing the work, which is
  /// what makes it read as a sheen.
  final double peak;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  // On paper the rim has to darken to read, so both hues go
                  // through the daylight accent ramp; in Twilight
                  // `ExampleInk.accent` returns them untouched.
                  painter: _SweepBorderPainter(
                    angle: angle,
                    radius: context.brandShape.radius(radius),
                    width: width,
                    color: ExampleInk.accent(context, color),
                    highlight: ExampleInk.accent(context, highlight),
                    floor: floor,
                    peak: peak,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _SweepBorderPainter extends CustomPainter {
  const _SweepBorderPainter({
    required this.angle,
    required this.radius,
    required this.width,
    required this.color,
    required this.highlight,
    required this.floor,
    required this.peak,
  });

  final double angle;
  final double radius;
  final double width;
  final Color color;
  final Color highlight;
  final double floor;
  final double peak;

  /// Fraction of a turn from the start of the fade-in to the peak. The lit arc
  /// runs three leads, about half the perimeter; the rest is dark.
  static const double _lead = .18;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = width / 2;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(inset),
      Radius.circular(math.max(0, radius - inset)),
    );
    final start = angle - _lead * 2 * math.pi;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + 2 * math.pi,
        colors: [
          color.withValues(alpha: floor),
          highlight.withValues(alpha: peak),
          color.withValues(alpha: peak * .55),
          color.withValues(alpha: floor),
          color.withValues(alpha: floor),
        ],
        stops: const [0, _lead, _lead * 2, _lead * 3, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_SweepBorderPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.radius != radius ||
      oldDelegate.width != width ||
      oldDelegate.color != color ||
      oldDelegate.highlight != highlight ||
      oldDelegate.floor != floor ||
      oldDelegate.peak != peak;
}

/// Round 44pt control with a label underneath (Send / Exchange / Buy ...).
///
/// In Twilight the disc is a lighter surface; in pearl daylight it is white on
/// paper with the daylight hairline and the ambient shadow under it, since a
/// white disc on a near-white page needs the shadow to exist at all.
class ExampleCircleAction extends StatelessWidget {
  const ExampleCircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    final Widget disc = Material(
      color: light
          ? ExampleSurface.of(context, 1)
          : _configuredColor(context, ExampleColors.darkSurfaceSubtle),
      shape: CircleBorder(
        side: light
            ? ExampleBorders.subtleSideOf(context)
            : BorderSide(
                color: _configuredColor(context, ExampleColors.lavender)
                    .withValues(alpha: .10)),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: ExampleInk.primary(context),
            size: 19,
          ),
        ),
      ),
    );
    return Opacity(
      opacity: onTap == null ? ExampleOpacity.disabled : 1,
      child: Semantics(
        button: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (light)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: ExampleShadows.ambientOf(context),
                  ),
                  child: disc,
                )
              else
                disc,
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11 * context.brandDesign.typographyScale,
                  color: ExampleInk.secondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tinted status pill (Active / Frozen / Completed ...).
///
/// Pass the brand token ([ExampleColors.success], `warning`, `danger`, ...).
/// The wash keeps the raw hue in both themes; the dot and the label go through
/// `ExampleInk.accent`, which is the identity in Twilight and deepens the hue
/// on paper — success straight from the palette is 1.8:1 on white, and 5.1:1
/// once deepened.
class ExamplePill extends StatelessWidget {
  const ExamplePill({
    required this.label,
    required this.color,
    this.dot = false,
    this.fontSize = 10.5,
    super.key,
  });

  final String label;
  final Color color;
  final bool dot;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final ink = ExampleInk.accent(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ExampleInk.tint(context, color),
        borderRadius: BorderRadius.circular(context.brandShape.radius(99)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            context.tr(label),
            style: TextStyle(
              color: ink,
              fontSize: fontSize * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient avatar with the user's initial, as in the desktop rail.
///
/// Brand artwork, like the card face: the violet-to-lavender disc and its
/// night initial are identical in both themes. Night on that gradient clears
/// 4.5:1 at every point, and a person's avatar reading the same in daylight
/// and Twilight is the point of an avatar.
class ExampleAvatar extends StatelessWidget {
  const ExampleAvatar({required this.name, this.size = 38, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _configuredColor(context, ExampleColors.violet),
            _configuredColor(context, ExampleColors.lavender)
          ],
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: context.brandDesign.isConfigured
              ? ExamplePalette.of(context).onFill
              : ExampleColors.night,
          fontSize: (size * .4) * context.brandDesign.typographyScale,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Currency / asset avatar drawn as real flag and coin artwork: US, EU, UK
/// and UAE flags, Bitcoin and Ethereum marks, and the shipped USDC / USDT
/// logos.
class ExampleCurrencyAvatar extends StatelessWidget {
  const ExampleCurrencyAvatar({required this.code, this.size = 30, super.key});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final symbol = code.trim().toUpperCase();
    Widget painted(CustomPainter painter) => Semantics(
          image: true,
          label: symbol,
          child: ClipOval(
            child: CustomPaint(
              size: Size.square(size),
              painter: painter,
            ),
          ),
        );
    Widget glyph(String text, Color background, {double scale = .5}) =>
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Text(
            text,
            style: TextStyle(
              // The fallback disc follows its own ground, so the same code
              // path reads on the Twilight and the daylight surface.
              color: context.brandDesign.isConfigured
                  ? ExamplePalette.fromDesign(
                          background.computeLuminance() > .5
                              ? Brightness.light
                              : Brightness.dark,
                          context.brandDesign)
                      .ink
                  : background.computeLuminance() > .5
                      ? ExampleColors.night
                      : ExampleColors.pearl,
              fontSize: (size * scale) * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        );
    switch (symbol) {
      case 'USD':
        return painted(const _UsFlagPainter());
      case 'EUR':
        return painted(const _EuFlagPainter());
      case 'GBP':
        return painted(const _UkFlagPainter());
      case 'AED':
        return painted(const _UaeFlagPainter());
      case 'CHF':
        return painted(const _SwissFlagPainter());
      case 'BTC':
        return painted(const _BitcoinPainter());
      case 'ETH':
        return painted(const _EthereumPainter());
      case 'USDC':
      case 'USDT':
        return ClipOval(
          child: Image.asset(
            'assets/crypto/${symbol.toLowerCase()}.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            semanticLabel: context.tr('{p0} logo', {'p0': symbol}),
          ),
        );
      case 'CARD':
        final light = ExampleTheme.isLight(context);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _configuredColor(context, ExampleColors.violet)
                .withValues(alpha: light ? .14 : .3),
          ),
          child: Icon(
            Icons.credit_card_rounded,
            size: size * .5,
            color: light
                ? ExampleInk.accent(
                    context, _configuredColor(context, ExampleColors.violet))
                : _configuredColor(context, ExampleColors.lavender),
          ),
        );
      default:
        // Use the device's colour emoji font for additional fiat flags.
        if (equalsSupportedCurrencyCodes.contains(symbol) &&
            symbol.length == 3) {
          final country = symbol.substring(0, 2);
          if (equalsCountryCodes.contains(country)) {
            final flag = String.fromCharCodes(
                country.codeUnits.map((c) => 0x1F1E6 + c - 65));
            return Semantics(
              image: true,
              label: context.tr('{p0} flag', {'p0': symbol}),
              child: SizedBox.square(
                  dimension: size,
                  child: Center(
                    child: Text(flag,
                        style: TextStyle(
                            fontFamily: '',
                            fontSize: (size * .8) *
                                context.brandDesign.typographyScale,
                            height: 1)),
                  )),
            );
          }
        }
        return glyph(
          symbol.isEmpty
              ? '·'
              : symbol.length <= 3
                  ? symbol
                  : symbol.substring(0, 1),
          ExampleSurface.of(context, 3),
          scale: symbol.length <= 1 ? .42 : .3,
        );
    }
  }
}

class _UsFlagPainter extends CustomPainter {
  const _UsFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Circle-cropped flag: 13 stripes, blue canton with a star grid.
    final stripe = h / 13;
    for (var i = 0; i < 13; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripe, w, stripe + .5),
        Paint()..color = i.isEven ? const Color(0xFFB22234) : Colors.white,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w * .48, stripe * 7),
      Paint()..color = const Color(0xFF3C3B6E),
    );
    final star = Paint()..color = Colors.white;
    final r = w * .028;
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 4; col++) {
        final dx = w * .06 + col * w * .12 + (row.isOdd ? w * .06 : 0);
        final dy = stripe * .9 + row * stripe * 1.3;
        canvas.drawCircle(Offset(dx, dy), r, star);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EuFlagPainter extends CustomPainter {
  const _EuFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF003399));
    final center = size.center(Offset.zero);
    final radius = size.width * .3;
    final star = Paint()..color = const Color(0xFFFFCC00);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        size.width * .045,
        star,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UkFlagPainter extends CustomPainter {
  const _UkFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF012169));
    final whiteDiag = Paint()
      ..color = Colors.white
      ..strokeWidth = w * .18
      ..style = PaintingStyle.stroke;
    final redDiag = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = w * .06
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 0), Offset(w, h), whiteDiag);
    canvas.drawLine(Offset(w, 0), Offset(0, h), whiteDiag);
    canvas.drawLine(const Offset(0, 0), Offset(w, h), redDiag);
    canvas.drawLine(Offset(w, 0), Offset(0, h), redDiag);
    canvas.drawRect(
      Rect.fromLTWH(w * .36, 0, w * .28, h),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * .36, w, h * .28),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * .42, 0, w * .16, h),
      Paint()..color = const Color(0xFFC8102E),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * .42, w, h * .16),
      Paint()..color = const Color(0xFFC8102E),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _UaeFlagPainter extends CustomPainter {
  const _UaeFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final band = h / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, band + .5),
        Paint()..color = const Color(0xFF00732F));
    canvas.drawRect(
        Rect.fromLTWH(0, band, w, band + .5), Paint()..color = Colors.white);
    canvas.drawRect(
        Rect.fromLTWH(0, band * 2, w, band), Paint()..color = Colors.black);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w * .3, h),
      Paint()..color = const Color(0xFFFF0000),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SwissFlagPainter extends CustomPainter {
  const _SwissFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFDA291C));
    final white = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(w * .41, w * .2, w * .18, w * .6), white);
    canvas.drawRect(Rect.fromLTWH(w * .2, w * .41, w * .6, w * .18), white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BitcoinPainter extends CustomPainter {
  const _BitcoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ExampleColors.bitcoin);
    final painter = TextPainter(
      text: TextSpan(
        text: '₿',
        style: TextStyle(
          color: Colors.white,
          fontSize: size.width * .62,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(math.pi / 13);
    painter.paint(
      canvas,
      Offset(-painter.width / 2, -painter.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EthereumPainter extends CustomPainter {
  const _EthereumPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = ExampleColors.ethereum);
    final cx = w / 2;
    final top = Offset(cx, h * .16);
    final mid = Offset(cx, h * .58);
    final bottom = Offset(cx, h * .86);
    final left = Offset(w * .24, h * .52);
    final right = Offset(w * .76, h * .52);
    final light = Paint()..color = Colors.white.withValues(alpha: .95);
    final dark = Paint()..color = Colors.white.withValues(alpha: .6);
    canvas.drawPath(Path()..addPolygon([top, left, mid], true), light);
    canvas.drawPath(Path()..addPolygon([top, right, mid], true), dark);
    canvas.drawPath(
      Path()..addPolygon([left, Offset(cx, h * .66), bottom], true),
      light,
    );
    canvas.drawPath(
      Path()..addPolygon([right, Offset(cx, h * .66), bottom], true),
      dark,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Section heading with an Iris action on the right.
class ExampleSectionTitle extends StatelessWidget {
  const ExampleSectionTitle({
    required this.title,
    this.action,
    this.onAction,
    this.chevron = false,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool chevron;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15.5 * context.brandDesign.typographyScale,
                fontWeight: FontWeight.w700,
                color: ExampleInk.primary(context),
              ),
            ),
          ),
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(context.brandShape.radius(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  chevron ? '$action ›' : action!,
                  style: TextStyle(
                    fontSize: 12.5 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.accent(context, ExampleColors.iris),
                  ),
                ),
              ),
            ),
        ],
      );
}

/// Pill segmented control (Money / Crypto / Exchange, All / Money / Crypto).
class ExampleSegmentedControl<T> extends StatelessWidget {
  const ExampleSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = 40,
    this.selectedColor,
    this.onSelectedColor,
    this.segmentIcons = const {},
    this.segmentIconColors = const {},
    super.key,
  });

  final List<({T value, String label})> segments;
  final T? selected;
  final ValueChanged<T> onChanged;
  final double height;

  /// Optional selection colors for secondary control rows.
  final Color? selectedColor;
  final Color? onSelectedColor;
  final Map<T, IconData> segmentIcons;
  final Map<T, Color> segmentIconColors;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ExampleTheme.isLight(context)
              ? ExampleSurface.of(context, 2)
              : _configuredColor(context, ExampleColors.darkSurface)
                  .withValues(alpha: .7),
          borderRadius:
              BorderRadius.circular(context.brandShape.radius(height / 2)),
          border: Border.all(
            color: ExampleTheme.isLight(context)
                ? ExampleBorders.subtleSideOf(context).color
                : _configuredColor(context, ExampleColors.lavender)
                    .withValues(alpha: .12),
          ),
        ),
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                child: _Segment(
                  label: segment.label,
                  selected: segment.value == selected,
                  selectedColor: selectedColor,
                  onSelectedColor: onSelectedColor,
                  icon: segmentIcons[segment.value],
                  iconColor: segmentIconColors[segment.value],
                  onTap: () => onChanged(segment.value),
                ),
              ),
          ],
        ),
      );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.onSelectedColor,
    this.icon,
    this.iconColor,
  });

  final String label;
  final bool selected;
  final Color? selectedColor;
  final Color? onSelectedColor;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = selected
        ? onSelectedColor ?? ExampleInk.onSelection(context)
        : ExampleTheme.isLight(context)
            ? ExampleInk.secondary(context)
            : _configuredColor(context, ExampleColors.pearl)
                .withValues(alpha: .68);
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13 * context.brandDesign.typographyScale,
        fontWeight: FontWeight.w600,
        color: labelColor,
      ),
    );
    return Semantics(
      role: SemanticsRole.tab,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.brandShape.radius(99)),
        // Selection is a state change: it moves on the state token with
        // the arrive curve and collapses to instant under reduced motion.
        child: AnimatedContainer(
          duration: ExampleMotion.of(context, ExampleMotion.state),
          curve: ExampleMotion.arrive,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // On paper the fill deepens toward indigo so the pearl label
            // clears 4.5:1 (violet alone is 3.96:1); in Twilight
            // `ExampleInk.selection` is violet, unchanged.
            color: selected
                ? selectedColor ?? ExampleInk.selection(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(context.brandShape.radius(99)),
            boxShadow: selected
                ? ExampleShadows.glowOf(
                    context,
                    selectedColor ??
                        _configuredColor(context, ExampleColors.violet),
                    alpha: .45,
                    blur: 14,
                    spread: -4,
                  )
                : ExampleShadows.none,
          ),
          child: icon == null
              ? labelWidget
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                          child: Icon(icon,
                              size: 16,
                              color: selected
                                  ? labelColor
                                  : iconColor ?? labelColor)),
                      const SizedBox(width: 4),
                      Flexible(child: labelWidget),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Dashed outline used by "Order a new card" and document upload tiles.
class ExampleDashedPanel extends StatelessWidget {
  const ExampleDashedPanel({
    required this.child,
    this.onTap,
    this.radius = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.brandShape.radius(radius)),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            radius: context.brandShape.radius(radius),
            // Iris at .42 disappears on paper, so the daylight dash is
            // lightViolet at .75 — 3.2:1 on the panel, which is what an
            // outline that *is* the control's boundary has to clear.
            color: light
                ? _configuredColor(context, ExampleColors.lightViolet)
                    .withValues(alpha: .75)
                : _configuredColor(context, ExampleColors.iris)
                    .withValues(alpha: .42),
          ),
          child: Ink(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: light
                    ? [
                        _configuredColor(context, ExampleColors.lightSurface),
                        _configuredColor(
                            context, ExampleColors.lightSurfaceSubtle),
                      ]
                    : [
                        _configuredColor(context, ExampleColors.glassTop),
                        _configuredColor(context, ExampleColors.glassBottom),
                      ],
              ),
              borderRadius:
                  BorderRadius.circular(context.brandShape.radius(radius)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(.5, .5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 5, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}

/// Square tinted icon tile used in transaction rows.
///
/// Same contract as [ExamplePill]: the wash keeps the raw hue, the glyph goes
/// through `ExampleInk.accent` so it clears 3:1 on paper.
class ExampleIconTile extends StatelessWidget {
  const ExampleIconTile({
    required this.icon,
    required this.color,
    this.size = 34,
    this.radius = 10,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: ExampleInk.tint(context, color, alpha: .14),
          borderRadius:
              BorderRadius.circular(context.brandShape.radius(radius)),
        ),
        child: Icon(
          icon,
          size: size * .5,
          color: ExampleInk.accent(context, color),
        ),
      );
}

/// The Example list row: 56 pt, a 40 pt leading slot, title and optional
/// subtitle, a trailing slot for an amount ([ExampleRowValue]) or a [chevron],
/// and press feedback through [ExamplePressable]. Rows are the rhythm of every
/// list screen (transactions, accounts, settings), so they carry no card of
/// their own: put them in a [ExampleListGroup] for a surface and dividers, or
/// straight into a `ListView.builder` with [divider] on.
///
/// The row is a button only when [onTap] or [onLongPress] is set; it then
/// scales to .985 on press, tints on hover over `ExampleMotion.state`, joins
/// the keyboard tab order and announces its text as one item. A row without a
/// gesture merges its text into a single semantics node. [enabled] false dims
/// the row to `ExampleOpacity.disabled` and drops the gesture. Both the hover
/// tint and the dim collapse to instant under reduced motion.
class ExampleRow extends StatefulWidget {
  const ExampleRow({
    required this.title,
    this.subtitle,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.divider = false,
    this.semanticsLabel,
    this.padding = defaultPadding,
    this.minHeight = 56,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Null lets full text wrap, for content such as notification messages.
  final int? titleMaxLines;
  final int? subtitleMaxLines;

  /// Centred in a [leadingSize] square: a `ExampleIconTile`,
  /// `ExampleCurrencyAvatar` or `ExampleAvatar`.
  final Widget? leading;

  /// Right-hand slot: a [ExampleRowValue], the [chevron], a switch, a pill.
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// Paints a hairline under the row, inset to the text column. Leave it
  /// false inside a [ExampleListGroup], which draws its own.
  final bool divider;

  /// Accessible name when the row is a button; otherwise its text is read.
  final String? semanticsLabel;

  /// Inner padding. The default keeps a 16 pt gutter and 8 pt above and
  /// below; dividers inset from its start edge.
  final EdgeInsetsGeometry padding;

  /// Tap target floor. 56 is the design; never below 44.
  final double minHeight;

  static const double leadingSize = 40;
  static const double leadingGap = AppSpacing.sm;
  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.xs,
  );

  /// Start edge of the text column for a row with a leading slot and
  /// [defaultPadding]; [ExampleListGroup] insets its dividers to it.
  static const double textInset = AppSpacing.md + leadingSize + leadingGap;

  /// Trailing chevron for rows that navigate.
  ///
  /// Keep passing this const: a row detects it by identity and swaps in
  /// [chevronOf] under the light theme, so every screen already written gets
  /// the daylight chevron without a call-site change.
  static const Widget chevron = Icon(
    Icons.chevron_right_rounded,
    size: 20,
    color: ExampleColors.textTertiary,
  );

  /// The trailing chevron in the theme of [context]. Only needed outside a
  /// [ExampleRow]; inside one, [chevron] resolves itself.
  static Widget chevronOf(BuildContext context) => Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: ExampleInk.tertiary(context),
      );

  @override
  State<ExampleRow> createState() => _ExampleRowState();
}

class _ExampleRowState extends State<ExampleRow> {
  bool _hovered = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = widget.padding.resolve(Directionality.of(context));
    final leading = widget.leading;
    // The const chevron carries the Twilight tertiary; on paper it is swapped
    // for the daylight one by identity, so screens keep passing the const.
    final trailing = identical(widget.trailing, ExampleRow.chevron)
        ? ExampleRow.chevronOf(context)
        : widget.trailing;
    final subtitle = widget.subtitle;
    final interactive = _interactive;
    final stateDuration = ExampleMotion.of(context, ExampleMotion.state);

    final titleStyle = (theme.textTheme.titleSmall ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
        .copyWith(
      fontWeight: FontWeight.w600,
      color: ExampleInk.primary(context),
      height: 1.3,
    );
    final subtitleStyle =
        (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
      color: ExampleInk.secondary(context),
      height: 1.35,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget content = Row(
      children: [
        if (leading != null) ...[
          SizedBox.square(
            dimension: ExampleRow.leadingSize,
            child: Center(child: leading),
          ),
          const SizedBox(width: ExampleRow.leadingGap),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: widget.titleMaxLines,
                overflow: widget.titleMaxLines == null
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: titleStyle,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  maxLines: widget.subtitleMaxLines,
                  overflow: widget.subtitleMaxLines == null
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ],
    );

    content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Padding(padding: padding, child: content),
    );

    // Hover is a state, so it moves on the state token; the tint keeps the
    // pearl hue at zero alpha when off so the lerp never passes through grey.
    content = AnimatedContainer(
      duration: stateDuration,
      curve: ExampleMotion.arrive,
      color: _hovered && interactive
          ? ExampleInk.hover(context)
          : ExampleInk.hoverOff(context),
      child: content,
    );

    if (widget.divider) {
      final inset = padding.left +
          (leading != null ? ExampleRow.leadingSize + ExampleRow.leadingGap : 0);
      content = Stack(
        // passthrough for the same reason the sheen overlay and the frosted
        // glass panel need it: a Stack's default StackFit.loose relaxes a
        // tight incoming width, and this one wraps arbitrary row content.
        fit: StackFit.passthrough,
        alignment: Alignment.topLeft,
        children: [
          content,
          PositionedDirectional(
            start: inset,
            end: 0,
            bottom: 0,
            height: 1,
            child: const _Hairline(),
          ),
        ],
      );
    }

    content = MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => _setHovered(true) : null,
      onExit: interactive ? (_) => _setHovered(false) : null,
      child: content,
    );

    if (widget.onTap != null || widget.onLongPress != null) {
      content = ExamplePressable(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        enabled: widget.enabled,
        pressedScale: .985,
        borderRadius:
            BorderRadius.circular(context.brandShape.radius(AppRadii.xs)),
        semanticsLabel: widget.semanticsLabel,
        child: content,
      );
    } else {
      content = MergeSemantics(
        child: Semantics(label: widget.semanticsLabel, child: content),
      );
    }

    return AnimatedOpacity(
      opacity: widget.enabled ? 1 : ExampleOpacity.disabled,
      duration: stateDuration,
      curve: ExampleMotion.arrive,
      child: content,
    );
  }
}

/// One-pixel divider in `ExampleBorders.hairlineSide`, or its daylight form.
/// Fills the width it is given; callers inset it to the text column.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(border: ExampleBorders.hairlineOf(context)),
        child: const SizedBox(height: 1),
      );
}

/// Trailing value for a [ExampleRow]: an amount with an optional caption
/// (status, currency, time), right-aligned, tabular figures throughout so
/// columns of rows line up digit for digit.
class ExampleRowValue extends StatelessWidget {
  const ExampleRowValue({
    required this.value,
    this.caption,
    this.color,
    this.captionColor,
    super.key,
  });

  final String value;
  final String? caption;

  /// Colour of [value]; the primary ink by default. Colour credits with
  /// `ExampleColors.success` and leave debits on the primary ink: money in is
  /// the exception worth marking, and a list that is all red or all green says
  /// nothing. Pass the brand token; on paper it is deepened through
  /// `ExampleInk.accent` so an amount never falls below 4.5:1.
  final Color? color;

  /// Colour of [caption]; the secondary ink by default.
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final captionText = caption;
    final valueColor = color;
    final captionInk = captionColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          style: (theme.textTheme.titleSmall ??
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
              .copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor == null
                ? ExampleInk.primary(context)
                : ExampleInk.accent(context, valueColor),
            height: 1.3,
            fontFeatures: tabular,
          ),
        ),
        if (captionText != null)
          Text(
            captionText,
            maxLines: 1,
            softWrap: false,
            style: (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
                .copyWith(
              color: captionInk == null
                  ? ExampleInk.secondary(context)
                  : ExampleInk.accent(context, captionInk),
              height: 1.35,
              fontFeatures: tabular,
            ),
          ),
      ],
    );
  }
}

/// A run of [ExampleRow]s on one surface: `ExampleSurface.of(context, level)`
/// behind them, `AppRadii.lg` corners, a `ExampleBorders.subtle` edge, hairline
/// dividers between rows inset to the text column, and an optional
/// [ExampleSectionTitle] above. Rows inside keep `divider: false`; the group
/// draws the separators, so the last row never carries one.
///
/// Use it for settings, account lists and short transaction lists (a handful
/// of rows). Long or lazily loaded lists belong in a `ListView.builder` of
/// rows with `divider: true`, not in a group. Never place a group inside a
/// `ExampleGlassPanel`; that is a card in a card.
///
/// In pearl daylight the group is white on paper with the daylight hairline
/// and a night ambient at .06 under it, because the surface step alone is not
/// separation on paper. Twilight is untouched: no shadow, same surface, same
/// edge.
class ExampleListGroup extends StatelessWidget {
  const ExampleListGroup({
    required this.children,
    this.title,
    this.action,
    this.onAction,
    this.level = 1,
    this.radius = AppRadii.lg,
    this.dividers = true,
    this.dividerInset = ExampleRow.textInset,
    this.bordered = true,
    super.key,
  });

  /// The rows, top to bottom.
  final List<Widget> children;

  /// Optional heading rendered as a [ExampleSectionTitle] above the surface.
  final String? title;

  /// Optional action label beside [title] ("See all").
  final String? action;
  final VoidCallback? onAction;

  /// Surface level, 0..3; 1 is a group resting on the page.
  final int level;
  final double radius;
  final bool dividers;

  /// Start inset of each divider. Defaults to the text column of a row with
  /// a leading slot; pass `AppSpacing.md` for rows without one.
  final double dividerInset;

  /// Subtle edge around the surface. Turn it off when the group sits on a
  /// level-0 page and the surface step alone is enough.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        BorderRadius.circular(context.brandShape.radius(radius));
    final rows = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0 && dividers)
          Padding(
            padding: EdgeInsetsDirectional.only(start: dividerInset),
            child: const _Hairline(),
          ),
        children[i],
      ],
    ];
    Widget group = ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(color: ExampleSurface.of(context, level)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
    if (bordered) {
      group = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: ExampleBorders.subtleOf(context),
        ),
        child: group,
      );
    }
    // On paper a white group on near-white paper is separated by the shadow,
    // not by the surface step; in Twilight `ambientOf` is an empty list and
    // this box paints nothing.
    if (ExampleTheme.isLight(context)) {
      group = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: ExampleShadows.ambientOf(context),
        ),
        child: group,
      );
    }
    final heading = title;
    if (heading == null) return group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ExampleSectionTitle(
            title: heading,
            action: action,
            onAction: onAction,
          ),
        ),
        group,
      ],
    );
  }
}

/// Every EXAMPLE route change hands off through the orbiting mark: it orbits
/// over a scrim for a beat while the incoming page fades in beneath it (see
/// [ExampleRouteTransition]). Deliberately no slide or zoom — the desktop shell
/// keeps its rail and header fixed, so moving the content column reads as a
/// full re-create.
class ExampleFadeTransitionsBuilder extends PageTransitionsBuilder {
  const ExampleFadeTransitionsBuilder({this.duration = ExampleMotion.route});

  final Duration duration;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      ExampleRouteTransition(animation: animation, child: child);
}

// ─── The living card ────────────────────────────────────────────────────────

/// The card, as an object rather than a rectangle.
///
/// Issued cards always load their artwork from the provider URL on [card].
/// While unavailable they keep a neutral backing with their actual metadata;
/// the decorative material described below is only for a null-card placeholder.
///
/// [ExamplePaymentCard] draws a night panel with a radial bloom behind it: a
/// good picture of a card. This is the material. Every competitor teardown in
/// this category opens its "beat them by" list with *make the card the hero* —
/// Kast ships a ladder of physical materials, Crypto.com ships one memorable
/// fanned-metal image, Revolut re-skins a real-time PBR face — and the one
/// thing none of them does is make the card in the app behave like metal under
/// a light. That is the whole brief here:
///
/// * **Material.** A vertical indigo-over-night roll, deterministic horizontal
///   grain, and a baked anisotropic specular — the three things that separate
///   brushed aluminium from a flat gradient. The grain is seeded from a fixed
///   constant, never `Random()`, so the face is byte-identical frame to frame
///   and golden to golden.
/// * **Arrival.** One specular pass, 600 ms, after the route settles. Never a
///   loop: this is the card screen's single moment, and a card that keeps
///   glinting is a slot machine, not a bank.
/// * **Tilt.** On web, a pointer over the face rakes it up to 6° with the
///   specular tracking the light. Mouse only — a thumb on glass has no
///   parallax to sell, and a card that tips under a scroll gesture reads as a
///   bug.
/// * **Frozen.** Frost, not a red banner. Freezing is reversible, so the state
///   has to look reversible: the face goes under glass — a real blur, a pearl
///   wash and a snow lattice — and comes back out unchanged.
/// * **Daylight.** A dark card on paper is the hardest object in the light
///   theme. It gets a two-layer seat (a tight contact shadow plus the ambient)
///   and a quieter rim, because on paper the silhouette is already carrying
///   the separation and a bright edge on top of it reads as a sticker.
///
/// Everything painted on the face takes explicit [ExampleColors.pearl]: the
/// artwork stays night in BOTH themes, so it must never follow page ink.
/// Measured on the face: pearl on night 16.49:1, pearl on the indigo band
/// 10.71:1, and the .66 caption 7.47:1 / 4.85:1 — body-grade everywhere.
///
/// This lives **beside** [ExamplePaymentCard], which is unchanged and still
/// backs every non-Example and compact call site that has not moved.
class ExampleLivingCard extends StatefulWidget {
  const ExampleLivingCard({
    this.card,
    this.height = 188,
    this.compact = false,
    this.status,
    this.onTap,
    this.frozen = false,
    this.interactive = true,
    this.enableHoverTilt = true,
    this.sweepOnArrival = true,
    this.semanticsLabel,
    super.key,
  });

  /// Card data. Null renders the brand's fallback face.
  final PaymentCard? card;

  /// Rendered height. Callers size by width / [ExampleLivingCard.aspectRatio].
  final double height;

  /// Thumbnail dressing: fewer marks, tighter padding, no number.
  final bool compact;

  /// Overrides `card.status` while an optimistic freeze is in flight.
  final CardStatus? status;

  final VoidCallback? onTap;

  /// Frost overlay. OR-ed with a frozen [status], so a caller may pass either.
  final bool frozen;

  /// Pointer tilt. Off for a face that is only decoration.
  final bool interactive;

  /// Disable when an ancestor `ExampleTiltCard` already handles pointer and
  /// device motion, keeping one transform while preserving tap interaction.
  final bool enableHoverTilt;

  /// The one specular pass after the route settles. Off for every face but the
  /// one the screen arrives on — a deck of five hosts would be five glints.
  final bool sweepOnArrival;

  /// Accessible name. Null publishes a masked description ("card ending
  /// 1 2 3 4"); an ancestor [ExamplePressable] with its own label already
  /// excludes this subtree, so passing null is right in a deck.
  final String? semanticsLabel;

  /// ISO 7810 ID-1.
  static const double aspectRatio = 1.586;

  /// Height for a face that spans [width].
  static double heightFor(double width) => width / aspectRatio;

  /// Maximum rake, in degrees, at the far corner of the face.
  static const double maxTiltDegrees = 6;

  /// Below this the full dressing cannot fit without truncation, so the face
  /// falls back to the compact layout whatever the caller asked for.
  static const double _fullLayoutFloor = 96;

  @override
  State<ExampleLivingCard> createState() => _ExampleLivingCardState();
}

class _ExampleLivingCardState extends State<ExampleLivingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    // 600 ms: long enough for the band to cross 343 pt as light rather than as
    // a wipe, short enough to be over before a thumb reaches the card.
    duration: const Duration(milliseconds: 600),
  );

  Animation<double>? _routeAnimation;
  bool _swept = false;

  /// Normalised pointer offset from the centre, -1..1 on both axes.
  Offset _tilt = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sweep.duration =
        ExampleMotion.of(context, const Duration(milliseconds: 600));
    if (ExampleMotion.reduced(context)) _sweep.stop();
    _bindRoute();
  }

  @override
  void didUpdateWidget(covariant ExampleLivingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.interactive || !widget.enableHoverTilt) &&
        _tilt != Offset.zero) {
      _tilt = Offset.zero;
    }
  }

  /// Nothing may run during the 420 ms route transition, so the arrival waits
  /// on the route's own animation and fires once, on the trailing edge.
  void _bindRoute() {
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _startSweep();
    } else {
      animation.addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _startSweep();
  }

  void _startSweep() {
    if (_swept || !mounted) return;
    if (!widget.sweepOnArrival) return;
    // Reduced motion keeps the baked anisotropic specular and skips the pass;
    // the material still reads as metal, it just never moves.
    if (ExampleMotion.reduced(context)) return;
    _swept = true;
    _sweep.forward();
  }

  bool get _canTilt =>
      kIsWeb &&
      widget.interactive &&
      widget.enableHoverTilt &&
      !ExampleMotion.reduced(context);

  void _onHover(PointerHoverEvent event) {
    if (!_canTilt) return;
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final next = Offset(
      ((event.localPosition.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
      ((event.localPosition.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
    );
    // Sub-pixel jitter would rebuild the painter on every mouse sample for no
    // visible change; a hundredth of the range is below the rake's resolution.
    if ((next - _tilt).distanceSquared < 0.0001) return;
    setState(() => _tilt = next);
  }

  void _onExit(PointerExitEvent event) {
    if (_tilt == Offset.zero) return;
    setState(() => _tilt = Offset.zero);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    final resolvedStatus =
        widget.status ?? widget.card?.status ?? CardStatus.active;
    final frozen = widget.frozen || resolvedStatus == CardStatus.frozen;
    final compact =
        widget.compact || widget.height < ExampleLivingCard._fullLayoutFloor;
    final mini = compact && widget.height < 55;
    final radius = context.brandShape.radius(compact ? 11.0 : 18.0);

    final artworkUrl =
        widget.compact && widget.card?.cardThumbnailUrl.isNotEmpty == true
            ? widget.card!.cardThumbnailUrl
            : widget.card?.artworkUrl ?? '';
    final hasArtwork = artworkUrl.trim().isNotEmpty;

    // A provisioned card's design belongs to its provider. Keep a neutral
    // backing while its server image loads or when no image is available;
    // custom material is only a decorative, unissued-card placeholder.
    final showFallbackDesign = widget.card == null;

    Widget face = RepaintBoundary(
      child: Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: showFallbackDesign
              ? null
              : _configuredColor(context, ExampleColors.night, artwork: true),
          // The roll, not a fill: night at the ends, indigo through the middle
          // third. A single flat night rectangle is what makes every other
          // wallet's card read as a sticker.
          gradient: showFallbackDesign
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _configuredColor(context, ExampleColors.night,
                        artwork: true),
                    _configuredColor(context, ExampleColors.indigo,
                        artwork: true),
                    _configuredColor(context, ExampleColors.night,
                        artwork: true),
                  ],
                  stops: const [0, .52, 1],
                )
              : null,
          border: Border.all(
            // Daylight seating. On Twilight the rim is the card's lit edge
            // against a near-black page and has to be bright (lavender .32,
            // the historical value). On paper the silhouette already separates
            // — night against #F4EEFC is a 16.99:1 step — so a bright rim on
            // top of it reads as a sticker outline. Halved to .18 and the work
            // moves to the shadow below.
            color:
                _configuredColor(context, ExampleColors.lavender, artwork: true)
                    .withValues(alpha: light ? .18 : .32),
          ),
          boxShadow: _seat(context, light),
        ),
        child: Stack(
          // StackFit.passthrough: the face must keep the tight width its
          // parent gave it. Under the default `loose` the padded column
          // collapses to its intrinsic width and the card unhelpfully shrinks
          // to fit its own wordmark.
          fit: StackFit.passthrough,
          children: [
            if (showFallbackDesign)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BrushedMetalPainter(
                        tilt: _tilt,
                        light: light,
                        palette: _artworkPalette(context)),
                  ),
                ),
              ),
            if (hasArtwork)
              Positioned.fill(
                child: Image.network(
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  artworkUrl,
                  key: ValueKey('example-living-artwork-$artworkUrl'),
                  fit: BoxFit.cover,
                  semanticLabel:
                      widget.card?.cardImageAlt.trim().isNotEmpty == true
                          ? widget.card!.cardImageAlt
                          : context.tr('Card design'),
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            _LivingCardContent(
              card: widget.card,
              status: resolvedStatus,
              compact: compact,
              mini: mini,
              hasArtwork: hasArtwork,
              showFallbackDesign: showFallbackDesign,
              height: widget.height,
            ),
            if (frozen)
              Positioned.fill(
                child: _FrozenGlass(radius: radius),
              ),
            // The arrival pass sits above the frost: a frozen card still
            // catches the light, which is exactly the reading we want — under
            // glass, not switched off.
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => CustomPaint(
                      painter: _SpecularSweepPainter(
                          progress: _sweep.value,
                          color: _configuredColor(context, ExampleColors.pearl,
                              artwork: true)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Card print does not grow with the OS text scale — a physical card's
    // embossing is fixed — and letting it grow is the one thing that can
    // overflow this face. Clamped rather than ignored, so a 1.15 setting still
    // reads slightly larger for anyone who needs it.
    face = MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15, child: face);

    if (_canTilt) {
      face = MouseRegion(
        onHover: _onHover,
        onExit: _onExit,
        child: TweenAnimationBuilder<Offset>(
          tween: Tween<Offset>(end: _tilt),
          // Short enough to feel attached to the cursor, long enough that a
          // fast flick across the face does not read as a twitch.
          duration: ExampleMotion.of(context, const Duration(milliseconds: 110)),
          curve: ExampleMotion.out,
          builder: (context, value, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateX(-value.dy * _kTiltRadians)
              ..rotateY(value.dx * _kTiltRadians),
            child: child,
          ),
          child: face,
        ),
      );
    }

    if (widget.onTap != null) {
      face = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(radius),
          child: face,
        ),
      );
    }

    // One node for the whole object, and never the number. A face that owns
    // its tap is a button; a face inside someone else's pressable is an image,
    // and that ancestor's own label already excludes this subtree.
    return Semantics(
      label: widget.semanticsLabel ??
          _maskedDescription(context, widget.card, resolvedStatus, frozen),
      button: widget.onTap != null,
      image: widget.onTap == null,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: face,
    );
  }

  /// How the card is seated on the page.
  ///
  /// Twilight keeps the historical violet bloom (.18 / blur 26 / y 12) — on a
  /// near-black ground the card is separated by light, not by shadow. Daylight
  /// inverts that: the bloom is halved by [ExampleShadows.glowOf] and a tight
  /// contact shadow goes under the bottom edge, because on paper a dark object
  /// with only a soft halo hovers, and a hovering card looks pasted on.
  List<BoxShadow> _seat(BuildContext context, bool light) {
    final bloom = ExampleShadows.glowOf(
      context,
      _configuredColor(context, ExampleColors.violet, artwork: true),
      alpha: .18,
      blur: 26,
      spread: 0,
      offset: const Offset(0, 12),
    );
    if (!light) return bloom;
    return [
      BoxShadow(
        color: _configuredColor(context, ExampleColors.night, artwork: true)
            .withValues(alpha: .10),
        blurRadius: 8,
        spreadRadius: -2,
        offset: const Offset(0, 2),
      ),
      ...bloom,
    ];
  }
}

const double _kTiltRadians = ExampleLivingCard.maxTiltDegrees * math.pi / 180;

/// Screen readers never hear a card number, masked or not — they hear the last
/// four spoken as digits, which is what a support call asks for.
String _maskedDescription(
    BuildContext context, PaymentCard? card, CardStatus status, bool frozen) {
  if (card == null) {
    final name = AppDesignTheme.nameOf(context);
    return '${name.isEmpty ? (context.brandDesign.isConfigured ? 'Payment' : 'Example') : name} card';
  }
  final parts = <String>[
    card.displayLabel,
    if (card.cardImageAlt.trim().isNotEmpty &&
        card.cardImageAlt != card.displayLabel)
      card.cardImageAlt,
    if (card.last4.isNotEmpty) 'ending ${card.last4.split('').join(' ')}',
    if (frozen)
      'frozen'
    else
      switch (status) {
        CardStatus.active => 'active',
        CardStatus.frozen => 'frozen',
        CardStatus.pending => 'pending',
        CardStatus.cancelled => 'closed',
      },
  ];
  return parts.join(', ');
}

/// Everything printed on the face.
///
/// Pulled out of the state class so the tilt rebuild never walks the text
/// tree: [_ExampleLivingCardState] rebuilds on every mouse sample, this does
/// not, because it is a const-constructible child of the same Stack.
class _LivingCardContent extends StatelessWidget {
  const _LivingCardContent({
    required this.card,
    required this.status,
    required this.compact,
    required this.mini,
    required this.hasArtwork,
    required this.showFallbackDesign,
    required this.height,
  });

  final PaymentCard? card;
  final CardStatus status;
  final bool compact;
  final bool mini;
  final bool hasArtwork;
  final bool showFallbackDesign;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Every dimension scales off the face height and is clamped at both ends,
    // so one layout serves a 48 pt thumbnail and a 240 pt hero without a
    // breakpoint and without an overflow at either edge.
    final pad = mini
        ? 5.0
        : compact
            ? 8.0
            : (height * .085).clamp(10.0, 16.0);
    final chip = mini
        ? 10.0
        : compact
            ? 15.0
            : (height * .17).clamp(18.0, 32.0);
    final numberSize = (height * .078).clamp(11.0, 16.0);
    final lockupHeight = compact ? 14.0 : (height * .122).clamp(14.0, 23.0);
    final captionSize = compact ? 9.0 : 10.0;

    final last4 = card?.last4 ?? '';

    return Padding(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showFallbackDesign) _LivingChip(size: chip),
              if (!compact) ...[
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _StatusPill(status: status),
                    if (card?.virtual == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.tr('Virtual'),
                        style: TextStyle(
                          color: hasArtwork
                              ? cardArtworkTextColor(card?.cardTextColor,
                                  fallback: _configuredColor(
                                      context, ExampleColors.pearl,
                                      artwork: true))
                              : _configuredColor(context, ExampleColors.pearl,
                                  artwork: true),
                          fontSize:
                              captionSize * context.brandDesign.typographyScale,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
          if (!compact && showFallbackDesign)
            _EmbossedNumber(last4: last4, fontSize: numberSize),
          if (mini && showFallbackDesign)
            const ExampleMark(size: 10)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showFallbackDesign)
                  // Explicit pearl: this lockup sits on card artwork, which
                  // stays night in BOTH themes, so it must not follow page ink.
                  ExampleLockup(
                    height: lockupHeight,
                    compact: true,
                    color: _configuredColor(context, ExampleColors.pearl,
                        artwork: true),
                  )
                else if (!compact && last4.isNotEmpty)
                  _EmbossedNumber(
                    last4: last4,
                    fontSize: captionSize + 1,
                    short: true,
                    color: cardArtworkTextColor(card?.cardTextColor,
                        fallback: _configuredColor(context, ExampleColors.pearl,
                            artwork: true)),
                  ),
                const Spacer(),
              ],
            ),
        ],
      ),
    );
  }
}

/// The number, stamped rather than printed.
///
/// Geist Mono with tabular figures so the groups sit on a fixed grid, and two
/// shadows rather than one: a night drop below-right and a pearl catch
/// above-left. That pair is the whole illusion — a single drop shadow reads as
/// text on a card, the pair reads as metal displaced by a die.
class _EmbossedNumber extends StatelessWidget {
  const _EmbossedNumber({
    required this.last4,
    required this.fontSize,
    this.short = false,
    this.color,
  });

  final String last4;
  final double fontSize;
  final Color? color;

  /// Only the visible group, for a face that already carries artwork.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final tail = last4.isEmpty ? '••••' : last4;
    final text = short ? '••••  $tail' : '••••  ••••  ••••  $tail';
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: TextStyle(
        fontFamily: context.brandDesign.monoFontFamily,
        // pearl .88 on the indigo band is 8.4:1 and on night 13.4:1; a full
        // pearl would look printed rather than struck.
        color: color ??
            _configuredColor(context, ExampleColors.pearl, artwork: true)
                .withValues(alpha: .88),
        fontSize: fontSize * context.brandDesign.typographyScale,
        fontWeight: FontWeight.w500,
        letterSpacing: fontSize * .12,
        height: 1.15,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: [
          Shadow(
            color: _configuredColor(context, ExampleColors.night, artwork: true)
                .withValues(alpha: .85),
            offset: const Offset(0, 1.1),
            blurRadius: 1.4,
          ),
          Shadow(
            color: _configuredColor(context, ExampleColors.pearl, artwork: true)
                .withValues(alpha: .22),
            offset: const Offset(0, -.9),
            blurRadius: 0,
          ),
        ],
      ),
    );
  }
}

/// Status as a hairline pill on the artwork.
///
/// The colours are the palette's semantic four, held at the dark values in
/// both themes because the pill is printed on the card, not on the page.
/// Measured on the .12 wash over the roll: success 8.71:1, warning (frozen)
/// 8.86:1 — both far above the 4.5:1 body floor.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final CardStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      CardStatus.active => (
          'Active',
          _configuredColor(context, ExampleColors.success, artwork: true)
        ),
      CardStatus.frozen => (
          'Frozen',
          _configuredColor(context, ExampleColors.warning, artwork: true)
        ),
      CardStatus.pending => (
          'Pending',
          _configuredColor(context, ExampleColors.iris, artwork: true)
        ),
      CardStatus.cancelled => (
          'Closed',
          _configuredColor(context, ExampleColors.pearl, artwork: true)
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius:
            BorderRadius.circular(context.brandShape.radius(AppRadii.pill)),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            context.tr(label),
            style: TextStyle(
              color: color,
              fontSize: 11 * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The chip, in the brand's own metal.
///
/// Every other wallet ships the same silver-grey rectangle. This one is
/// two-tone in the palette — a lavender-to-indigo body with a pearl catch
/// across the top-left corner — so the one hardware detail on the face is
/// Example's rather than stock. The contacts are drawn with a night line and a
/// pearl line one pixel above it, which is the same trick as the embossed
/// number at a smaller scale.
class _LivingChip extends StatelessWidget {
  const _LivingChip({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.3,
        height: size,
        child: RepaintBoundary(
          child: CustomPaint(
              painter: _LivingChipPainter(palette: _artworkPalette(context))),
        ),
      );
}

class _LivingChipPainter extends CustomPainter {
  const _LivingChipPainter({this.palette});

  final ExamplePalette? palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height * .22),
    );
    canvas
      ..save()
      ..clipRRect(rrect)
      // Body: the two tones.
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (palette?.ink ?? ExampleColors.pearl),
              (palette?.accent ?? ExampleColors.lavender),
              (palette?.surfaceHigh ?? ExampleColors.indigo),
            ],
            stops: const [0, .45, 1],
          ).createShader(rect),
      )
      // The catch: a hard specular corner, which is what tells the eye this is
      // a polished surface and not a printed swatch.
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.centerRight,
            colors: [
              (palette?.ink ?? ExampleColors.pearl).withValues(alpha: .85),
              (palette?.ink ?? ExampleColors.pearl).withValues(alpha: 0),
            ],
            stops: const [0, .38],
          ).createShader(rect),
      );

    // Contacts. Two verticals and one horizontal, each a night groove with a
    // pearl lip above it.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.7, size.height * .045)
      ..color = (palette?.paper ?? ExampleColors.night).withValues(alpha: .55);
    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.5, size.height * .03)
      ..color = (palette?.ink ?? ExampleColors.pearl).withValues(alpha: .55);
    for (final x in <double>[size.width * .34, size.width * .67]) {
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), groove)
        ..drawLine(Offset(x - .8, 0), Offset(x - .8, size.height), lip);
    }
    final y = size.height * .5;
    canvas
      ..drawLine(Offset(0, y), Offset(size.width, y), groove)
      ..drawLine(Offset(0, y - .8), Offset(size.width, y - .8), lip)
      ..restore()
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color =
              (palette?.paper ?? ExampleColors.night).withValues(alpha: .35),
      );
  }

  @override
  bool shouldRepaint(covariant _LivingChipPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// The material: grain plus a raked highlight that follows the pointer.
///
/// Brushed metal is anisotropic — it scatters light along the brush direction
/// and holds it across. So the highlight is a wide soft band rather than a
/// point, the grain runs horizontally across the face, and both move together
/// when the card tilts. The grain offsets come from a fixed-seed integer
/// hash rather than `Random()`, so the face is identical on every frame and in
/// every golden.
class _BrushedMetalPainter extends CustomPainter {
  const _BrushedMetalPainter(
      {required this.tilt, required this.light, this.palette});

  final ExamplePalette? palette;

  /// Pointer offset from the centre, -1..1. Zero on touch and under reduced
  /// motion.
  final Offset tilt;

  /// True in pearl daylight.
  ///
  /// The artwork stays night in both themes — but the *scene* around it does
  /// not, and that is where light mode stops being a de-tinted dark theme and
  /// becomes a second material. A dark card photographed on paper shows a
  /// brighter specular, a lit top edge, and a band of light bounced back up
  /// off the page into its lower edge. All three are painted only here, all
  /// three are pearl on night, and none of them changes a single pixel of the
  /// Twilight face.
  final bool light;

  /// Grain lines per 100 pt of height. Dense enough to read as a surface at
  /// 188 pt, sparse enough that a 48 pt thumbnail does not turn into noise.
  static const double _linesPer100 = 34;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // The raked highlight. It travels against the tilt — a card rocked to the
    // right shows the light moving left, which is what a real specular does.
    final cx = .38 - tilt.dx * .22;
    final cy = .10 - tilt.dy * .18;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(cx * 2 - 1, cy * 2 - 1),
          radius: 1.05,
          colors: [
            (palette?.ink ?? ExampleColors.pearl)
                .withValues(alpha: light ? .17 : .13),
            (palette?.accent ?? ExampleColors.iris)
                .withValues(alpha: light ? .09 : .07),
            (palette?.fill ?? ExampleColors.violet).withValues(alpha: 0),
          ],
          stops: const [0, .38, 1],
        ).createShader(rect),
    );

    // Grain.
    final count = math.max(6, (size.height / 100 * _linesPer100).round());
    final step = size.height / count;
    final paint = Paint()..strokeWidth = .7;
    for (var i = 0; i < count; i++) {
      // Deterministic 32-bit mix; the same i always yields the same line.
      final h = (i * 0x9E3779B1) & 0x7FFFFFFF;
      final jitter = ((h >> 8) & 0xFF) / 255;
      final light = ((h >> 16) & 0x1) == 1;
      final y = (i + jitter * .8) * step;
      if (y > size.height) continue;
      final alpha = .012 + ((h >> 20) & 0x1F) / 31 * .028;
      paint.color = light
          ? (palette?.ink ?? ExampleColors.pearl).withValues(alpha: alpha)
          : (palette?.paper ?? ExampleColors.night)
              .withValues(alpha: alpha * 1.8);
      canvas.drawLine(
        Offset(-1, y),
        Offset(size.width + 1, y),
        paint,
      );
    }

    // Milled edge: a lit top lip and a shaded bottom, 1 pt each. This is the
    // difference between a rectangle and an object with thickness.
    canvas
      ..drawLine(
        const Offset(0, .5),
        Offset(size.width, .5),
        Paint()
          ..strokeWidth = 1
          ..color = (palette?.ink ?? ExampleColors.pearl)
              .withValues(alpha: light ? .24 : .16),
      )
      ..drawLine(
        Offset(0, size.height - .5),
        Offset(size.width, size.height - .5),
        Paint()
          ..strokeWidth = 1
          ..color = (palette?.paper ?? ExampleColors.night)
              .withValues(alpha: light ? .42 : .55),
      );

    // Paper bounce. Only in daylight, and only along the bottom sixth: the
    // page under the card throws light back up into its lower edge. It is the
    // cheapest cue in the whole face that the object is resting on something
    // bright rather than floating in front of it.
    if (light) {
      final bounce = Rect.fromLTRB(
        0,
        size.height * .84,
        size.width,
        size.height,
      );
      canvas.drawRect(
        bounce,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              (palette?.ink ?? ExampleColors.pearl).withValues(alpha: .10),
              (palette?.ink ?? ExampleColors.pearl).withValues(alpha: 0),
            ],
          ).createShader(bounce),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrushedMetalPainter oldDelegate) =>
      oldDelegate.tilt != tilt ||
      oldDelegate.light != light ||
      oldDelegate.palette != palette;
}

/// The arrival pass: one band of light across the face.
///
/// 20° off vertical and about a third of the width, which is the same band
/// geometry [ExampleSheen] uses, so the card's moment and the rest of the alive
/// layer read as one system. Peak pearl .18 rather than the scope's .14
/// because this fires once and never repeats — a single pass has to land.
class _SpecularSweepPainter extends CustomPainter {
  const _SpecularSweepPainter(
      {required this.progress, this.color = ExampleColors.pearl});

  final Color color;

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1 || size.isEmpty) return;
    // Eased inside the painter so the band accelerates in and settles out
    // rather than crossing at a constant rate, which reads as a wipe.
    final t = ExampleMotion.arrive.transform(progress);
    final bandWidth = size.width * .34;
    final travel = size.width + bandWidth * 2;
    final centre = -bandWidth + travel * t;
    final band = Rect.fromCenter(
      center: Offset.zero,
      width: bandWidth,
      height: size.height * 2.4,
    );
    // Fade the head and tail of the pass so it enters and leaves as light
    // rather than as an object arriving at the edge.
    final envelope = math.sin(t * math.pi).clamp(0.0, 1.0);
    canvas
      ..save()
      ..translate(centre, size.height / 2)
      ..rotate(-20 * math.pi / 180)
      ..drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: .18 * envelope),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .5, 1],
          ).createShader(band),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _SpecularSweepPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Frozen, as a reversible state.
///
/// A red banner says *something went wrong*; freezing a card is a deliberate,
/// undoable act, so the face goes under glass instead: a real blur, a pearl
/// wash cold enough to read as ice, and a snow lattice. Everything underneath
/// stays legible through it, which is the point — the card is still there, it
/// is just behind something.
///
/// The blur is bounded and clipped, as every [BackdropFilter] in this system
/// is, and the whole layer sits in a [RepaintBoundary].
class _FrozenGlass extends StatelessWidget {
  const _FrozenGlass({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Pearl .10 over the roll lifts the whole face by about a
                // ratio point (pearl still reads 8.18:1 on it) and turns the
                // indigo cold without introducing a second hue.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _configuredColor(context, ExampleColors.pearl, artwork: true)
                        .withValues(alpha: .13),
                    _configuredColor(context, ExampleColors.lavender,
                            artwork: true)
                        .withValues(alpha: .08),
                  ],
                ),
              ),
              child: CustomPaint(
                  painter: _FrostLatticePainter(
                      color: _configuredColor(context, ExampleColors.pearl,
                          artwork: true))),
            ),
          ),
        ),
      );
}

/// Six-armed crystals on a staggered grid. Drawn rather than tiled from a
/// glyph, because an emoji snowflake is an instant reject and a font glyph
/// would not scale with the face.
class _FrostLatticePainter extends CustomPainter {
  const _FrostLatticePainter({this.color = ExampleColors.pearl});

  final Color color;

  static const double _spacing = 34;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .16);
    const r = _spacing * .22;
    final rows = (size.height / _spacing).ceil() + 1;
    final cols = (size.width / _spacing).ceil() + 1;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final cx = col * _spacing + (row.isOdd ? _spacing / 2 : 0);
        final cy = row * _spacing;
        for (var arm = 0; arm < 6; arm++) {
          final angle = arm * math.pi / 3;
          final dx = math.cos(angle);
          final dy = math.sin(angle);
          final tip = Offset(cx + dx * r, cy + dy * r);
          canvas.drawLine(Offset(cx, cy), tip, paint);
          // Barbs at 62% along the arm, the detail that reads as a crystal
          // rather than as an asterisk.
          final mid = Offset(cx + dx * r * .62, cy + dy * r * .62);
          for (final sign in const [1, -1]) {
            final barb = angle + sign * math.pi / 3;
            canvas.drawLine(
              mid,
              Offset(
                mid.dx + math.cos(barb) * r * .3,
                mid.dy + math.sin(barb) * r * .3,
              ),
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FrostLatticePainter oldDelegate) =>
      oldDelegate.color != color;
}

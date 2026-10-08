import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import '../../shared/theme/app_theme_extensions.dart';
import '../../shared/widgets/brand_loader.dart';

import 'example_motion.dart';
import 'example_sheen.dart';
import 'example_tokens.dart';

/// What sits behind a [ExampleGlassButton], and therefore whether there is
/// anything worth blurring.
///
/// Flutter cannot ask "what is painted under me", so the adopter states it.
/// Getting it wrong is cheap in one direction and expensive in the other: a
/// [surface] button on an atmosphere merely looks solid, while an
/// [atmosphere] button on a flat panel blurs a flat panel and disappears.
/// That asymmetry is why [surface] is the default.
enum ExampleGlassGround {
  /// A plain painted surface — a scaffold, a panel, a sheet, a list footer.
  /// Nothing behind is worth sampling, so the material goes opaque and keeps
  /// the identical silhouette, radius, edge treatment and motion. This is the
  /// safe default: it never dissolves.
  surface,

  /// A `ExampleAtmosphere`, a glow, a photo, a scrolling list passing beneath a
  /// pinned CTA bar. The bounded backdrop blur runs and the tinted body lets
  /// 6–12 percent of it through, so the button samples the page it is sitting
  /// on instead of inventing its own white haze.
  atmosphere,

  /// Directly on card artwork, which stays night in both themes. Pins the
  /// whole material to Twilight — a paper-toned button on a dark card is the
  /// single most common light-mode regression in this codebase.
  artwork,
}

/// The three jobs a decisive CTA does.
enum ExampleGlassButtonTone {
  /// The one action the screen exists for: Sign in, Continue, Confirm
  /// payment, Order card, Add money.
  primary,

  /// The same object, unfilled — a paired second choice that must not read as
  /// louder than [primary], but must not shrink into a text link either.
  neutral,

  /// A destructive confirmation: Freeze card, Close account, Cancel transfer.
  danger,
}

/// The rounded glass CTA. **At most one or two per screen.**
///
/// This is not the default button. Rows, list actions, dialog confirms and
/// settings toggles keep their existing controls; this is the single decisive
/// action, and its authority comes from being rare. A screen with four of
/// these has none.
///
/// ## Why it looks the way it does
///
/// The 2021 glass cliché is a foggy rectangle: crank the blur, drop white at
/// 20 percent, ship. It fails a banking register twice — a translucent body
/// cannot hold a 4.5:1 label, and a big blur radius reads as *soft*, which is
/// the last adjective a payment confirmation wants. So the depth here is built
/// at the rim, not in the body:
///
/// * a body that is 88–100 percent opaque and tinted from the palette (indigo
///   over night on Twilight, violet over iris on paper) rather than from
///   white, so it belongs to Example and not to a screenshot of a Mac;
/// * a one-pixel specular hairline along the top, inset to where the pill's
///   straight run begins, so the object reads as *lit* from above;
/// * a one-pixel night line along the bottom that grounds it, so it reads as
///   resting on the page rather than floating over it;
/// * a bounded blur that survives only in the 6–12 percent the body lets
///   through — enough that a violet glow behind the button warms it, never
///   enough to move a contrast number.
///
/// ## The two themes are different materials, not one material de-tinted
///
/// Twilight lifts: a violet gradient washes the top third of the body, which
/// on night still leaves pearl at 8.21:1. Pearl daylight does the opposite —
/// any white lift on paper would drop the white label to 3.83:1, so daylight
/// gets no body lift at all. It is lit purely by the violet-to-iris gradient
/// running top to bottom, and it is separated from the paper by a real
/// ambient shadow floor plus an [ExampleColors.lightIris] edge that is darker
/// than the fill it outlines. Measured white-on-fill: **5.36:1 at the lit top
/// stop, 6.24:1 at the grounded bottom** — both clear the 4.5:1 body floor.
///
/// ## States are designed, not dimmed
///
/// Pressed collapses the lift and deepens the body (Twilight) or flattens the
/// gradient to its dark stop (daylight): the *material* changes, not an
/// opacity. Loading swaps the label for a centred progress ring through
/// [ExampleStateSwitch] while the silhouette, width and position hold still,
/// and the glow underneath drops to the resting ambient — the button visibly
/// stops being ready. Disabled re-materialises as an inert surface step with
/// tertiary ink (**4.53:1 on daylight, 4.84:1 on Twilight**), which reads as
/// "not available yet" rather than "broken button".
///
/// ## Adopting it
///
/// It is a drop-in for a `FilledButton` inside a `SizedBox(width:
/// double.infinity)`: default height 54 matches the filled-button theme, and
/// every layer here forwards its constraints unchanged, so a tight incoming
/// width survives to the label row.
///
/// ```dart
/// SizedBox(
///   width: double.infinity,
///   child: ExampleGlassButton(
///     label: 'Sign in',
///     ground: ExampleGlassGround.atmosphere,
///     sheen: true,
///     onPressed: _submit,
///   ),
/// )
/// ```
class ExampleGlassButton extends StatefulWidget {
  const ExampleGlassButton({
    required this.label,
    required this.onPressed,
    this.tone = ExampleGlassButtonTone.primary,
    this.ground = ExampleGlassGround.surface,
    this.icon,
    this.leading,
    this.trailing,
    this.loading = false,
    this.sheen = true,
    this.expand = true,
    this.height = 54,
    this.radius = AppRadii.pill,
    this.padding,
    this.semanticsLabel,
    this.loadingSemanticsLabel,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The action, in the imperative. Two or three words: "Sign in", "Confirm
  /// payment". A CTA that needs a sentence is not a CTA.
  final String label;

  /// Null disables the button, exactly as on `FilledButton`, so an adopter can
  /// swap the widget without restructuring a form's enablement logic.
  final VoidCallback? onPressed;

  final ExampleGlassButtonTone tone;

  /// What is painted behind. See [ExampleGlassGround]; default [surface] is the
  /// variant that cannot disappear.
  final ExampleGlassGround ground;

  /// Sugar for a leading icon. [leading] wins if both are given.
  final IconData? icon;

  /// Arbitrary leading widget — a token glyph, a small avatar. Sized by the
  /// caller; keep it at or under 24 logical pixels.
  final Widget? leading;

  /// Trailing widget, usually a chevron on a "Continue" step.
  final Widget? trailing;

  /// Working. Blocks the tap, swaps the label for a progress ring in place,
  /// and drops the glow to resting so the button stops looking ready.
  final bool loading;

  /// The endless [ExampleSheen] running across the glass. **On by default.**
  ///
  /// This reverses the widget's original stance. It first shipped with the
  /// sheen off and pinned to a single arrival sweep, on the argument that a
  /// CTA greets you once rather than pulsing at you while you read a form.
  /// Naem overruled that: the glass is the brand's signature material and it
  /// should read as *lit*, continuously, the way a real specular highlight
  /// travels across a moving pane. It is a deliberate, owned decision, not a
  /// drift — so the reasoning is recorded here rather than quietly dropped.
  ///
  /// What keeps it from becoming noise is that the loop is the scope's, not
  /// the button's: `ExampleSheenScope` runs ONE ticker at a 7 s cadence and
  /// hands every host a different phase offset, so buttons, panels and cards
  /// on a screen sweep in sequence instead of flashing in unison. A screen
  /// with four glass CTAs costs four phases of one ticker, not four tickers.
  ///
  /// It stops completely — ticker and timer both — when the app backgrounds,
  /// when another route covers this one, when `TickerMode` is off, and when
  /// the viewer has asked for reduced motion. That last gate is why the loop
  /// is safe to ship: a single 600 ms sweep someone did not want is over
  /// almost before they notice, but a loop they did not want never ends.
  ///
  /// No-op without a `ExampleSheenScope` above. Pass false for a button that
  /// genuinely must sit still — a destructive confirm, or a control inside a
  /// surface that is already the screen's moving object.
  final bool sheen;

  /// Fill the incoming width. True is the bottom-CTA-bar case; false hugs the
  /// label for an inline CTA. With true, bound the width somewhere above —
  /// same rule as any `Row`.
  final bool expand;

  /// Resting height. Clamped up to the 44 pt target floor, and treated as a
  /// *minimum*: at large text scales the button grows instead of clipping.
  final double height;

  /// Corner radius. Defaults to a true pill, which is the point — a pill reads
  /// as a distinct object against the rectangular language of panels and rows,
  /// where another rounded rectangle would read as one more panel.
  final double radius;

  /// Defaults to 24 horizontal, 12 vertical.
  final EdgeInsetsGeometry? padding;

  /// Accessible name. Defaults to [label]; set it when the visible label is
  /// short enough to be ambiguous out of context ("Continue" -> "Continue to
  /// review").
  final String? semanticsLabel;

  /// Announced while [loading]. Defaults to "<label>, in progress".
  final String? loadingSemanticsLabel;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Blur sigma of the bounded backdrop, matching `ExampleGlassPanel`'s frost
  /// so the two frosted materials on one screen sample at the same rate.
  static const double blurSigma = 18;

  /// The 44 pt target floor from the accessibility laws.
  static const double minTouchTarget = 44;

  @override
  State<ExampleGlassButton> createState() => _ExampleGlassButtonState();
}

class _ExampleGlassButtonState extends State<ExampleGlassButton> {
  FocusNode? _internalNode;
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_internalNode ??= FocusNode());

  bool get _interactive => widget.onPressed != null && !widget.loading;

  @override
  void didUpdateWidget(ExampleGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Losing interactivity mid-press (a form invalidating, a request
    // starting) must not leave the material stuck in its pressed state.
    if (!_interactive && (_pressed || _hovered)) {
      _pressed = false;
      _hovered = false;
    }
  }

  @override
  void dispose() {
    _internalNode?.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Artwork stays night in both themes, so a button on it resolves against
    // Twilight and takes pearl ink — never the page's paper ink.
    final palette = widget.ground == ExampleGlassGround.artwork
        ? ExamplePalette.fromDesign(Brightness.dark, context.brandDesign)
        : ExamplePalette.of(context);

    final state = widget.onPressed == null && !widget.loading
        ? _GlassState.disabled
        : widget.loading
            ? _GlassState.loading
            : _pressed
                ? _GlassState.pressed
                : _hovered
                    ? _GlassState.hovered
                    : _GlassState.resting;

    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final material = _GlassMaterial.resolve(
      palette: palette,
      tone: widget.tone,
      ground: widget.ground,
      state: state,
      allowBlur: !highContrast,
    );

    final height = math.max(widget.height, ExampleGlassButton.minTouchTarget);
    final radius = context.brandDesign.isConfigured
        ? context.brandShape.radius(widget.radius)
        : widget.radius;
    final borderRadius = BorderRadius.circular(radius);
    // A pill's straight run starts half a height in from each edge, so the
    // specular hairline is inset to there; any further out and it would climb
    // the curve and read as a stray tick.
    final edgeInset = math.min(radius, height / 2);
    final duration = ExampleMotion.of(
      context,
      state == _GlassState.pressed ? ExampleMotion.press : ExampleMotion.state,
    );

    Widget body = AnimatedContainer(
      duration: duration,
      curve: ExampleMotion.arrive,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [material.bodyTop, material.bodyBottom],
        ),
        border: Border.all(color: material.edge),
      ),
      // The border lives inside the clip, as on ExampleGlassPanel: the clip
      // trims its antialiased outer half and what is left is a true hairline.
      foregroundDecoration: material.lift == null
          ? null
          : BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [material.lift!, material.lift!.withValues(alpha: 0)],
                stops: const [0, .62],
              ),
            ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        // heightFactor 1 keeps the button hugging its content instead of
        // stretching to a bounded parent, while ConstrainedBox holds the 44 pt
        // floor and lets large text scales grow it rather than clip it.
        // widthFactor mirrors `expand`: null fills a bounded width (the
        // full-bleed CTA bar), 1 shrink-wraps to the label — without it an
        // inline CTA silently stretched to whatever loose width it was given.
        child: Center(
          heightFactor: 1,
          widthFactor: widget.expand ? null : 1,
          child: Padding(
            padding: widget.padding ??
                const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
            child: _content(context, material),
          ),
        ),
      ),
    );

    body = Stack(
      // passthrough, not the default loose: this Stack is handed a tight width
      // by a full-bleed CTA bar and must forward it, or the button collapses
      // to its label. The same trap has shipped three times in this repo.
      fit: StackFit.passthrough,
      children: [
        body,
        Positioned(
          top: 0,
          left: edgeInset,
          right: edgeInset,
          height: 1,
          child: IgnorePointer(child: _EdgeLine(color: material.hairline)),
        ),
        Positioned(
          bottom: 0,
          left: edgeInset,
          right: edgeInset,
          height: 1,
          child: IgnorePointer(child: _EdgeLine(color: material.groundLine)),
        ),
      ],
    );

    if (material.blurs) {
      body = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: ExampleGlassButton.blurSigma,
          sigmaY: ExampleGlassButton.blurSigma,
        ),
        child: body,
      );
    }

    body = RepaintBoundary(
      child: ClipRRect(borderRadius: borderRadius, child: body),
    );

    if (widget.sheen) {
      // onFill is the only intensity whose peak leaves a label on a violet
      // fill legible (4.51:1 on daylight) — so the band can run forever
      // without ever costing the label its contrast floor, which is the whole
      // reason an endless sweep is admissible on a button that holds text.
      body = ExampleSheen(
        borderRadius: borderRadius,
        intensity: ExampleSheenIntensity.onFill,
        sweepOnArrival: true,
        idle: true,
        material:
            widget.ground == ExampleGlassGround.artwork ? Brightness.dark : null,
        child: body,
      );
    }

    // Shadow outside the clip, or the clip eats it.
    body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: material.shadow,
      ),
      child: body,
    );

    body = ExamplePressable(
      // Pure visual wrapper: no onTap, so it adds the .97 / 120 ms press and
      // nothing else — no second semantics node, no second focus stop, and no
      // iris focus ring, which is hard-coded dark and fails 3:1 on paper.
      enabled: _interactive,
      child: body,
    );

    // The ring is a foreground decoration, so focus never moves a pixel of
    // layout. Iris on Twilight, lightViolet on paper (4.97:1 on the paper
    // ground, clearing the 3:1 non-text floor that iris would miss at 1.9:1).
    body = AnimatedContainer(
      duration: ExampleMotion.of(context, ExampleMotion.state),
      curve: ExampleMotion.arrive,
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: _focused
              ? material.focusRing
              : material.focusRing.withValues(alpha: 0),
          width: 2,
        ),
      ),
      child: body,
    );

    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.loading
          ? (widget.loadingSemanticsLabel ?? '${widget.label}, in progress')
          : (widget.semanticsLabel ?? widget.label),
      liveRegion: widget.loading,
      excludeSemantics: true,
      onTap: _interactive ? widget.onPressed : null,
      child: FocusableActionDetector(
        focusNode: _node,
        autofocus: widget.autofocus,
        enabled: _interactive,
        mouseCursor:
            _interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) {
          if (_focused != value && mounted) setState(() => _focused = value);
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value && mounted) setState(() => _hovered = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_interactive) widget.onPressed!();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _interactive ? (_) => _setPressed(true) : null,
          onTapUp: _interactive ? (_) => _setPressed(false) : null,
          onTapCancel: _interactive ? () => _setPressed(false) : null,
          onTap: _interactive ? widget.onPressed : null,
          child: body,
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _GlassMaterial material) {
    final theme = Theme.of(context);
    final style = (theme.textTheme.labelLarge ??
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
        .copyWith(color: material.label, fontWeight: FontWeight.w600);

    final Widget resting = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leading != null)
          widget.leading!
        else if (widget.icon != null)
          Icon(widget.icon, size: 20, color: material.label),
        if (widget.leading != null || widget.icon != null)
          const SizedBox(width: AppSpacing.xs),
        // Flexible + one line: a CTA label that does not fit is a copy
        // problem, and an overflowing RenderFlex is a rendering problem. Only
        // one of those should reach a user.
        Flexible(
          child: Text(
            widget.label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconTheme.merge(
            data: IconThemeData(color: material.label, size: 20),
            child: widget.trailing!,
          ),
        ],
      ],
    );

    if (!widget.loading) {
      return ExampleStateSwitch(
          child: KeyedSubtree(key: const ValueKey('label'), child: resting));
    }

    final reduced = ExampleMotion.reduced(context);
    return ExampleStateSwitch(
      child: SizedBox(
        key: const ValueKey('loading'),
        width: 20,
        height: 20,
        child: context.brandDesign.isConfigured
            ? BrandLoader(
                size: 20,
                color: material.label,
                strokeWidth: 2,
                spin: !reduced,
              )
            : CircularProgressIndicator(
                // Reduced motion gets a still quarter-arc rather than a spinner:
                // "busy" still reads, nothing rotates. Flutter's indeterminate
                // indicator ignores disableAnimations, so this is the only way the
                // promise holds.
                value: reduced ? .25 : null,
                strokeWidth: 2,
                strokeCap: StrokeCap.round,
                color: material.label,
              ),
      ),
    );
  }
}

/// A one-pixel edge. Its own widget so the two hairlines stay `const`-cheap
/// and the Positioned children never rebuild the body.
class _EdgeLine extends StatelessWidget {
  const _EdgeLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          // Fading to nothing at both ends stops the line from terminating in
          // two visible nicks where it meets the curve.
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color,
              color.withValues(alpha: 0)
            ],
          ),
        ),
      );
}

enum _GlassState { resting, hovered, pressed, loading, disabled }

/// Every colour the button paints, resolved once for one (tone, ground, state,
/// brightness).
@immutable
class _GlassMaterial {
  const _GlassMaterial({
    required this.bodyTop,
    required this.bodyBottom,
    required this.lift,
    required this.hairline,
    required this.groundLine,
    required this.edge,
    required this.label,
    required this.focusRing,
    required this.shadow,
    required this.blurs,
  });

  /// Top stop of the body gradient.
  final Color bodyTop;

  /// Bottom stop of the body gradient.
  final Color bodyBottom;

  /// Twilight's violet wash over the top 62 percent. Null on paper, where any
  /// white or violet lift under the label costs more contrast than it buys.
  final Color? lift;

  /// The specular top edge.
  final Color hairline;

  /// The night line that sets the button on the page.
  final Color groundLine;

  final Color edge;
  final Color label;
  final Color focusRing;
  final List<BoxShadow> shadow;

  /// Whether a bounded backdrop blur is worth its cost — only where the ground
  /// has something behind it *and* the body is translucent enough to show it.
  final bool blurs;

  static _GlassMaterial resolve({
    required ExamplePalette palette,
    required ExampleGlassButtonTone tone,
    required ExampleGlassGround ground,
    required _GlassState state,
    required bool allowBlur,
  }) {
    final dark = palette.isDark;
    final flat = ground == ExampleGlassGround.surface;
    final pressed = state == _GlassState.pressed;
    final hovered = state == _GlassState.hovered;
    final busy = state == _GlassState.loading;

    final configured = palette.design.isConfigured;
    final focusRing = dark ? palette.accent : palette.fill;
    // The original material has a separate indigo body and night floor.
    // Configured brands derive those from their surface and ink roles.
    final primaryBase = configured ? palette.surfaceHigh : ExampleColors.indigo;
    final groundInk =
        configured ? (dark ? palette.paper : palette.ink) : ExampleColors.night;
    // Dark glass rests on the surface palette, even when its glow is bright.
    // Only the solid light material uses the primary fill's foreground.
    final filledLabel = configured
        ? (dark ? palette.ink : palette.onFill)
        : (dark ? ExampleColors.pearl : Colors.white);
    final highlight = dark ? palette.ink : palette.surface;
    final ambient = configured
        ? ExampleShadows.ambientLight
            .map((shadow) => shadow.copyWith(color: palette.shadowAmbient))
            .toList(growable: false)
        : ExampleShadows.ambientLight;

    if (state == _GlassState.disabled) {
      // Not a greyed-out button: a different, inert material. It steps down a
      // surface level, loses its glow entirely and keeps a faint hairline, so
      // it reads as an object that is not ready rather than a broken control.
      // Tertiary ink measures 4.84:1 on darkSurfaceSubtle and 4.53:1 on
      // lightSurfaceSubtle — body-grade in both, well past the 3:1 that a
      // disabled control is even asked for.
      return _GlassMaterial(
        bodyTop: dark ? palette.surfaceSubtle : palette.surface,
        bodyBottom: dark ? palette.surface : palette.surfaceSubtle,
        lift: null,
        hairline: dark
            ? highlight.withValues(alpha: .08)
            : highlight.withValues(alpha: .60),
        groundLine: groundInk.withValues(alpha: dark ? .30 : .07),
        edge: palette.borderSubtle,
        label: palette.textTertiary,
        focusRing: focusRing,
        shadow: dark ? ExampleShadows.none : ambient,
        blurs: false,
      );
    }

    // Depth budget. Twilight lights the object; daylight grounds it. Both drop
    // to the resting ambient while pressed or busy, which is what makes the
    // press feel like the button settling into the page.
    List<BoxShadow> glow(Color accent, double alpha) {
      if (pressed || busy) {
        return dark ? ExampleShadows.none : ambient;
      }
      final lit = hovered ? alpha + .08 : alpha;
      final bloom = ExampleShadows.glow(
        accent,
        alpha: lit,
        blur: 30,
        spread: -6,
        offset: const Offset(0, 12),
      );
      // On paper the bloom alone is a smudge; the ambient underneath is what
      // the benchmark called missing from light Example, so it goes first.
      return dark ? bloom : [...ambient, ...bloom];
    }

    switch (tone) {
      case ExampleGlassButtonTone.primary:
        if (dark) {
          // Indigo body, night floor, violet wash on top. Pearl measures
          // 8.21:1 at the lit top over the brightest atmosphere stop and
          // 11.06:1 at the grounded bottom; even under a sheen band at its
          // onFill peak the top holds 4.80:1. A flat violet slab — what every
          // competitor ships — could not: pearl on violet is 3.37:1 and white
          // on it 3.95:1, both failing.
          final base = pressed ? .94 : .88;
          return _GlassMaterial(
            bodyTop: _maybeFlat(
              primaryBase.withValues(alpha: base),
              palette.paper,
              flat,
            ),
            bodyBottom: _maybeFlat(
              groundInk.withValues(alpha: pressed ? .97 : .94),
              palette.paper,
              flat,
            ),
            lift: palette.fill.withValues(
              alpha: pressed
                  ? .10
                  : busy
                      ? .14
                      : hovered
                          ? .34
                          : .26,
            ),
            hairline: highlight.withValues(alpha: pressed ? .16 : .34),
            groundLine: groundInk.withValues(alpha: .55),
            edge: hovered
                ? palette.accent.withValues(alpha: .55)
                : palette.borderEmphasis,
            label: filledLabel,
            focusRing: focusRing,
            shadow: glow(palette.fill, .30),
            blurs: allowBlur && !flat,
          );
        }
        // Daylight is lit by its own gradient, not by an added highlight:
        // white on lightViolet is 5.36:1 and on lightIris 6.24:1, and a white
        // wash over the top would take the label to 3.83:1. The body stays
        // opaque so the sheen's onFill peak lands on exactly the surface it
        // was measured against (4.51:1).
        return _GlassMaterial(
          bodyTop: pressed ? palette.accent : palette.fill,
          bodyBottom: palette.accent,
          lift: null,
          hairline: highlight.withValues(
            alpha: pressed ? .22 : .55,
          ),
          groundLine: groundInk.withValues(alpha: .24),
          edge: palette.accent,
          label: filledLabel,
          focusRing: focusRing,
          shadow: glow(palette.fill, .34),
          blurs: false,
        );

      case ExampleGlassButtonTone.neutral:
        if (flat) {
          // Nothing behind to sample, so glass would be an invisible tint on
          // a panel. Same silhouette, same edges, same motion — an opaque
          // surface step instead. This is the fallback the laws ask for.
          return _GlassMaterial(
            bodyTop: dark ? palette.surfaceSubtle : palette.surface,
            bodyBottom: dark
                ? palette.surface
                : (pressed ? palette.surfaceHigh : palette.surfaceSubtle),
            lift: dark
                ? palette.fill.withValues(alpha: pressed ? .04 : .10)
                : null,
            hairline: dark
                ? highlight.withValues(alpha: pressed ? .12 : .24)
                : highlight.withValues(alpha: .85),
            groundLine: groundInk.withValues(alpha: dark ? .45 : .12),
            // The boundary of a control the user operates, per WCAG
            // 1.4.11: daylight draws it in tertiary ink (4.66:1 on paper)
            // because the structural lavender hairline is only 1.18:1.
            edge: dark ? palette.borderSubtle : palette.textTertiary,
            label: palette.ink,
            focusRing: focusRing,
            shadow: dark ? ExampleShadows.none : ambient,
            blurs: false,
          );
        }
        return _GlassMaterial(
          bodyTop: palette.glassTop,
          bodyBottom: palette.glassBottom,
          lift:
              dark ? palette.fill.withValues(alpha: pressed ? .04 : .10) : null,
          hairline: dark
              ? highlight.withValues(alpha: pressed ? .12 : .26)
              : highlight.withValues(alpha: .85),
          groundLine: groundInk.withValues(alpha: dark ? .45 : .12),
          // As above: tertiary ink carries the 3:1 control boundary on
          // paper; Twilight keeps the structural edge.
          edge: dark ? palette.borderSubtle : palette.textTertiary,
          label: palette.ink,
          focusRing: focusRing,
          shadow: dark ? ExampleShadows.none : ambient,
          blurs: allowBlur,
        );

      case ExampleGlassButtonTone.danger:
        if (dark) {
          // Restraint, not alarm: a dark red glass, not a red slab. Pearl
          // measures 8.26:1 at the lit top.
          return _GlassMaterial(
            bodyTop: _maybeFlat(
              palette.danger.withValues(alpha: pressed ? .32 : .26),
              palette.paper,
              flat,
            ),
            bodyBottom: _maybeFlat(
              groundInk.withValues(alpha: .94),
              palette.paper,
              flat,
            ),
            lift: palette.danger.withValues(alpha: pressed ? .06 : .14),
            hairline: palette.danger.withValues(alpha: pressed ? .22 : .40),
            groundLine: groundInk.withValues(alpha: .55),
            edge: palette.danger.withValues(alpha: hovered ? .70 : .55),
            label: filledLabel,
            focusRing: focusRing,
            shadow: glow(palette.danger, .24),
            blurs: allowBlur && !flat,
          );
        }
        // Daylight destructive: solid lightDanger lit to a night-deepened
        // bottom stop. White measures 5.05:1 at the top and 6.32:1 at the
        // bottom — both body-grade.
        final deep = Color.alphaBlend(
          palette.ink.withValues(alpha: .14),
          palette.danger,
        );
        return _GlassMaterial(
          bodyTop: pressed ? deep : palette.danger,
          bodyBottom: deep,
          lift: null,
          hairline: highlight.withValues(
            alpha: pressed ? .22 : .50,
          ),
          groundLine: groundInk.withValues(alpha: .28),
          edge: deep,
          label: filledLabel,
          focusRing: focusRing,
          shadow: glow(palette.danger, .26),
          blurs: false,
        );
    }
  }

  /// Collapse a translucent stop onto the page ground when there is no blur
  /// behind it, so the material keeps its measured colour instead of picking
  /// up whatever panel it happens to be sitting on.
  static Color _maybeFlat(Color color, Color ground, bool flat) =>
      flat ? Color.alphaBlend(color, ground) : color;
}

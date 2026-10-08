import 'package:flutter/material.dart';

import 'example_motion.dart';
import 'example_sheen.dart';
import 'example_tokens.dart';
import 'example_typography.dart' show ExampleAmountSize;
import 'example_ui.dart' show ExampleThemeContext;

/// Shape-matched loading placeholders for Twilight surfaces.
///
/// A skeleton is a promise about layout: the block occupies exactly the
/// space the real content will, so when data arrives nothing on the screen
/// moves. That is the whole design. There is no shimmer, no pulse and no
/// stagger; the only motion is one 200 ms fade-in when the placeholder is
/// first shown (instant under reduced motion). Example's single infinite
/// animation is the brand orbit loader, and it is reserved for full-screen
/// waits and route handoffs; inside a page, content that is loading looks
/// like this.
///
/// Presets, by the content they stand in for:
///
/// * [ExampleSkeleton.line]: one line of text. Pill-shaped, 12 px tall by
///   default, scales with the user's text size.
/// * [ExampleSkeleton.avatar]: a round avatar, flag or coin mark.
/// * [ExampleSkeleton.amount]: a `ExampleAmount` at the given size. Reserves
///   the amount's full line box and draws a cap-height block inside it.
/// * [ExampleSkeleton.row]: a list row (avatar, title, subtitle, trailing
///   amount) at 60 px, the height of a `ExampleRow`. Stack as many as the
///   list will show, with `AppSpacing.xs` between them.
/// * [ExampleSkeleton.card]: a panel or payment card placeholder.
/// * [ExampleSkeleton.new]: any other block.
///
/// Blocks take their tint from [tintOf], which reads `ExamplePalette` for the
/// active theme: `ExampleSurface.level2` at night and the lavender-tinted
/// `lightSkeletonBase` in daylight. Both sit about 1.2:1 off their ground, so
/// a loading screen carries the same weight whichever theme it is read in,
/// and daylight never falls back to the grey placeholder every other wallet
/// ships — a Example skeleton is lavender, in both themes, because the brand
/// is. Inside a level-2 element (or on a white panel) pass
/// `color: ExampleSkeleton.tintOf(context, elevated: true)` for the next step
/// up; [color] still accepts any explicit colour.
///
/// The block itself is a plain filled rectangle — no gradient baked in, no
/// shimmer of its own. Liveness comes from the alive layer instead: when a
/// [ExampleSheenScope] is in play above it, the skeleton wraps itself in a
/// soft [ExampleSheen], so one band of light crosses the placeholder on
/// arrival and every cadence after, on the same clock as the screen's other
/// sheen hosts. With no scope above it the widget is exactly what it was:
/// static blocks and one fade-in. Set [sheen] to false to opt out.
///
/// **A loading list is one host, not eight.** Every skeleton that registers
/// is a host, and the law caps a screen at two or three; a column of rows
/// that each sweep on their own stagger is the wallet shimmer this system
/// exists to avoid. Pass `sheen: false` to the rows and wrap the group once:
///
/// ```dart
/// ExampleSheen.text(
///   intensity: ExampleSheenIntensity.soft,
///   child: Column(
///     children: [for (var i = 0; i < 8; i++) const ExampleSkeleton.row(sheen: false)],
///   ),
/// )
/// ```
///
/// Every skeleton is one semantics node labelled "Loading"; give a whole
/// loading list a single `Semantics(label: ...)` and `ExcludeSemantics` if
/// eight rows announcing themselves is too much.
class ExampleSkeleton extends StatelessWidget {
  /// A free-form block. Pass [width] or [widthFactor]; with neither the
  /// block fills the available width, which is right inside a `Column` and
  /// an error inside an unbounded `Row`.
  const ExampleSkeleton({
    this.width,
    this.widthFactor,
    this.height = 16,
    this.radius = AppRadii.xs,
    this.color,
    this.fadeIn = true,
    this.sheen = true,
    this.semanticsLabel = 'Loading',
    super.key,
  })  : _kind = _Kind.block,
        amountSize = null,
        avatar = false,
        trailing = false,
        avatarSize = 0,
        padding = EdgeInsets.zero;

  /// One line of text. [height] is the block, not the line box; 12 px reads
  /// as a 14 px body line, 10 px as a 12 px caption.
  const ExampleSkeleton.line({
    this.width,
    this.widthFactor,
    this.height = 12,
    this.color,
    this.fadeIn = true,
    this.sheen = true,
    this.semanticsLabel = 'Loading',
    super.key,
  })  : _kind = _Kind.line,
        radius = AppRadii.pill,
        amountSize = null,
        avatar = false,
        trailing = false,
        avatarSize = 0,
        padding = EdgeInsets.zero;

  /// A round avatar. 32 px matches `ExampleCurrencyAvatar` in a row; pass 38
  /// for `ExampleAvatar`.
  const ExampleSkeleton.avatar({
    double size = 32,
    this.color,
    this.fadeIn = true,
    this.sheen = true,
    this.semanticsLabel = 'Loading',
    super.key,
  })  : _kind = _Kind.avatar,
        width = size,
        widthFactor = null,
        height = size,
        radius = AppRadii.pill,
        amountSize = null,
        avatar = false,
        trailing = false,
        avatarSize = size,
        padding = EdgeInsets.zero;

  /// A `ExampleAmount` placeholder. The outer box is the amount's line box at
  /// [amountSize] (so the balance panel keeps its height); the visible block
  /// is cap height. [width] defaults to about seven tabular digits.
  const ExampleSkeleton.amount({
    ExampleAmountSize size = ExampleAmountSize.large,
    this.width,
    this.color,
    this.fadeIn = true,
    this.sheen = true,
    this.semanticsLabel = 'Loading',
    super.key,
  })  : _kind = _Kind.amount,
        amountSize = size,
        widthFactor = null,
        height = 0,
        radius = AppRadii.xs,
        avatar = false,
        trailing = false,
        avatarSize = 0,
        padding = EdgeInsets.zero;

  /// A list row: leading avatar, a title and subtitle line, a trailing
  /// amount. [height] is a minimum; the row grows with the user's text size
  /// exactly as the real row does. [padding] should match the horizontal
  /// inset of the rows it stands in for.
  ///
  /// [sheen] defaults to **false** here, unlike every other constructor: a row
  /// never appears alone. Eight bare `ExampleSkeleton.row()`s inside a shell
  /// scope registered eight sheen hosts and forced eight `saveLayer`s a frame,
  /// which is both a frame budget nobody measured and a plain breach of the
  /// two-or-three hosts a screen is allowed. A loading list is ONE host: leave
  /// this false and wrap the column in a single
  /// `ExampleSheen.text(intensity: ExampleSheenIntensity.soft)`. Pass true only
  /// for a row that genuinely stands by itself.
  const ExampleSkeleton.row({
    this.height = 60,
    this.avatar = true,
    this.trailing = true,
    this.avatarSize = 32,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    this.color,
    this.fadeIn = true,
    this.sheen = false,
    this.semanticsLabel = 'Loading',
    super.key,
  })  : _kind = _Kind.row,
        width = null,
        widthFactor = null,
        radius = AppRadii.pill,
        amountSize = null;

  /// A panel or card placeholder at `AppRadii.lg`. Fills the width unless
  /// [width] is given.
  const ExampleSkeleton.card({
    this.height = 120,
    this.width,
    this.radius = AppRadii.lg,
    this.color,
    this.fadeIn = true,
    this.sheen = true,
    this.semanticsLabel = 'Loading',
    super.key,
  })  : _kind = _Kind.card,
        widthFactor = null,
        amountSize = null,
        avatar = false,
        trailing = false,
        avatarSize = 0,
        padding = EdgeInsets.zero;

  final _Kind _kind;

  /// Fixed width in logical pixels. Wins over [widthFactor].
  final double? width;

  /// Width as a fraction of the available width, for partial text lines
  /// (`.42` for a title, `.26` for a caption). Needs a bounded parent.
  final double? widthFactor;

  /// Block height ([ExampleSkeleton.new], [line], [card]) or minimum row
  /// height ([row]). Ignored by [avatar] and [amount].
  final double height;

  /// Corner radius of the block.
  final double radius;

  /// Block colour. Null resolves through [tintOf] for the current theme
  /// (`ExampleSurface.level2` at night, `lightSkeletonBase` in daylight); pass
  /// `ExampleSkeleton.tintOf(context, elevated: true)` on a level-2 or white
  /// surface, or any colour to override outright.
  final Color? color;

  /// One [ExampleMotion.state] fade-in when the skeleton first appears.
  /// Collapses to instant under reduced motion. Turn off when a parent
  /// already fades the whole loading state in.
  final bool fadeIn;

  /// Carry the alive layer's soft sheen when a [ExampleSheenScope] is above
  /// this skeleton. False keeps the block static even inside a scope — the
  /// right answer for every block of a loading list, whose group is wrapped
  /// in a single [ExampleSheen] instead. With no scope in the tree this
  /// changes nothing either way: the widget registers no host, starts no
  /// ticker and adds no layer.
  final bool sheen;

  /// Accessible label for the whole skeleton. Descendants are excluded.
  final String semanticsLabel;

  /// Size of the amount stood in for ([amount] only).
  final ExampleAmountSize? amountSize;

  /// Whether the row shows a leading avatar block ([row] only).
  final bool avatar;

  /// Whether the row shows a trailing amount block ([row] only).
  final bool trailing;

  /// Diameter of the avatar block ([avatar] and [row]).
  final double avatarSize;

  /// Horizontal inset of the row ([row] only).
  final EdgeInsetsGeometry padding;

  /// Title-line width as a fraction of the row's text column.
  static const double _rowTitleFactor = .42;

  /// Subtitle-line width as a fraction of the row's text column.
  static const double _rowSubtitleFactor = .26;

  /// Width of the trailing amount block in a row.
  static const double _rowTrailingWidth = 56;

  /// Cap height of Geist as a fraction of the font size; the visible block
  /// of an amount skeleton.
  static const double _capHeight = .72;

  /// Default amount width as a multiple of the font size (about seven
  /// tabular digits plus a symbol).
  static const double _amountWidthEm = 4.6;

  /// The block's corner radius as a [BorderRadius], so the alive layer can
  /// be handed the exact shape it must clip to:
  /// `ExampleSheen(borderRadius: skeleton.borderRadius, intensity: soft)`.
  BorderRadius get borderRadius => BorderRadius.all(Radius.circular(radius));

  /// The placeholder tint for the current theme.
  ///
  /// Example takes `ExamplePalette.skeletonBase` at rest (`ExampleSurface.level2`
  /// on dark, `lightSkeletonBase` on light) and `surfaceHigh` when [elevated]
  /// — the step to reach for on a level-2 element or a white panel, where the
  /// resting tint would sink into its ground. Both steps sit about 1.2:1 off
  /// what they lie on: present enough to read as reserved space, quiet enough
  /// never to be mistaken for content. A white-label tenant gets the
  /// equivalent `ColorScheme` containers instead of Example's surfaces.
  static Color tintOf(BuildContext context, {bool elevated = false}) {
    final theme = Theme.of(context);
    if (!context.isExampleTheme) {
      return elevated
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerHigh;
    }
    final palette = ExamplePalette.forBrightness(theme.brightness);
    return elevated ? palette.surfaceHigh : palette.skeletonBase;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final color = this.color ?? tintOf(context);
    Widget body = switch (_kind) {
      _Kind.block || _Kind.card => _Block(
          width: width,
          widthFactor: widthFactor,
          height: height,
          radius: radius,
          color: color,
        ),
      _Kind.line => _Block(
          width: width,
          widthFactor: widthFactor,
          height: scaler.scale(height),
          radius: radius,
          color: color,
        ),
      _Kind.avatar => _Block(
          width: avatarSize,
          height: avatarSize,
          radius: radius,
          color: color,
        ),
      _Kind.amount => _amount(scaler, color),
      _Kind.row => _row(scaler, color),
    };
    // The alive layer, only when a live scope is above us. `ExampleSheen`
    // would fall back to a permanently painted highlight without one, and a
    // placeholder wearing a fixed band is a placeholder that looks broken.
    if (sheen && ExampleSheenScope.maybeOf(context) != null) {
      body = switch (_kind) {
        // One block, one clip: the band is cut to the block's own radius.
        _Kind.block || _Kind.card || _Kind.line || _Kind.avatar => ExampleSheen(
            intensity: ExampleSheenIntensity.soft,
            borderRadius: borderRadius,
            child: body,
          ),
        // A composition: mask by the child's own alpha so the light lands on
        // the blocks and never on the gaps between them or on an amount's
        // empty line box.
        _Kind.amount || _Kind.row => ExampleSheen.text(
            intensity: ExampleSheenIntensity.soft,
            child: body,
          ),
      };
    }
    if (fadeIn) body = _FadeIn(child: body);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: body,
    );
  }

  Widget _amount(TextScaler scaler, Color color) {
    final size = amountSize!;
    final lineBox = scaler.scale(size.fontSize * size.height);
    return SizedBox(
      height: lineBox,
      width: width ?? scaler.scale(size.fontSize * _amountWidthEm),
      child: Center(
        child: _Block(
          height: scaler.scale(size.fontSize * _capHeight),
          radius: radius,
          color: color,
        ),
      ),
    );
  }

  Widget _row(TextScaler scaler, Color color) => Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Row(
            children: [
              if (avatar) ...[
                _Block(
                  width: avatarSize,
                  height: avatarSize,
                  radius: AppRadii.pill,
                  color: color,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Block(
                      widthFactor: _rowTitleFactor,
                      height: scaler.scale(12),
                      radius: AppRadii.pill,
                      color: color,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _Block(
                      widthFactor: _rowSubtitleFactor,
                      height: scaler.scale(10),
                      radius: AppRadii.pill,
                      color: color,
                    ),
                  ],
                ),
              ),
              if (trailing) ...[
                const SizedBox(width: AppSpacing.sm),
                _Block(
                  width: _rowTrailingWidth,
                  height: scaler.scale(12),
                  radius: AppRadii.pill,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      );
}

enum _Kind { block, line, avatar, amount, row, card }

/// A single flat block. Static by design: no gradient, no shimmer.
class _Block extends StatelessWidget {
  const _Block({
    required this.height,
    required this.radius,
    required this.color,
    this.width,
    this.widthFactor,
  });

  final double height;
  final double radius;
  final Color color;
  final double? width;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
      ),
    );
    if (width == null && widthFactor != null) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: AlignmentDirectional.centerStart,
        child: box,
      );
    }
    return box;
  }
}

/// One fade from transparent to opaque over [ExampleMotion.state] with
/// [ExampleMotion.arrive], run once on mount. `TweenAnimationBuilder` owns
/// and disposes its controller; the boundary keeps the 200 ms repaint off
/// the rest of the page.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: ExampleMotion.of(context, ExampleMotion.state),
          curve: ExampleMotion.arrive,
          child: child,
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
        ),
      );
}

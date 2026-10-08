import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import 'example_colors.dart';
import 'example_mark.dart';
import 'example_motion.dart';

/// Covers the outgoing route, displays customer loading artwork, then reveals
/// the next page. Reverse navigation fades out without a loader. Colors and
/// reduced-motion behavior follow the active customer theme.
class ExampleRouteTransition extends StatelessWidget {
  const ExampleRouteTransition({
    required this.animation,
    required this.child,
    super.key,
  });

  /// The route's primary animation (0 → 1 on push, 1 → 0 on pop).
  final Animation<double> animation;

  /// The incoming page.
  final Widget child;

  static const _pageFade = Interval(.40, 1, curve: Curves.easeOutCubic);
  static const _groundIn = Interval(0, .10, curve: Curves.easeOut);
  static const _overlayOut = Interval(.58, .92, curve: Curves.easeInCubic);
  static const _popFade = Interval(.62, 1, curve: Curves.easeOut);

  /// Ink of the daylight mark: the brand's deep `indigo`, never a new hex.
  static const _daylightInk = ExampleColors.indigo;

  @override
  Widget build(BuildContext context) {
    // Reduced motion: the handoff is decoration, so there is none of it. The
    // framework alone would not do this — `disableAnimations` only scales the
    // route controller to 5 % of its duration, so the whole choreography still
    // played, just in ~21 ms, and it reads the platform flag rather than the
    // `MediaQuery` a shell (or a test) sets. Folding the flag into the three
    // beat values below instead of returning `child` bare keeps the widget
    // tree identical to a settled route, so turning the setting on or off
    // never remounts the page underneath.
    final reduced = ExampleMotion.reduced(context);
    final palette = ExamplePalette.of(context);
    final dark = palette.isDark;
    final ground = ColoredBox(color: palette.paper);
    final design = context.brandDesign;
    final color = design.isConfigured
        ? design.color(palette.brightness, 'loader', fallback: palette.accent)
        : dark
            ? null
            : _daylightInk;
    final Widget mark = ExampleLoader.transition(color: color);

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, page) {
        final v = animation.value.clamp(0.0, 1.0);
        final status = animation.status;
        final forward = !reduced && status == AnimationStatus.forward;
        final groundIn = forward ? _groundIn.transform(v) : 0.0;
        final overlay =
            forward ? math.min(groundIn, 1 - _overlayOut.transform(v)) : 0.0;
        final pageOpacity = forward
            ? _pageFade.transform(v)
            : !reduced && status == AnimationStatus.reverse
                ? _popFade.transform(v)
                : 1.0;
        // Child order is fixed (ground, page, overlay) so the page keeps its
        // element — and every scroll position inside it — across all beats.
        // Opacity 0 skips painting entirely, so the settled route costs nothing.
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(opacity: groundIn, child: ground),
              ),
            ),
            Opacity(opacity: pageOpacity, child: page),
            if (overlay > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: overlay,
                    child: ColoredBox(
                      color: palette.paper,
                      child: Center(child: mark),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

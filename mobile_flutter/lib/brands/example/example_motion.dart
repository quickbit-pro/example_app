import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_theme_extensions.dart';
import 'example_colors.dart';

/// Example motion tokens.
///
/// Example is a product register: motion conveys state, never decoration, and
/// the user is in a task. Pick the token by what the motion is for, not by
/// how it looks:
///
/// * [press]: tactile feedback on pointer down. Only [ExamplePressable] should
///   need it directly.
/// * [state]: a component changing state in place (selected, expanded,
///   toggled, loaded). This is the default for `AnimatedContainer`,
///   `AnimatedOpacity`, `AnimatedSwitcher` and friends.
/// * [sheet]: a bottom sheet, drawer or menu travelling on or off screen.
/// * [route]: the page handoff. Owned by `ExampleRouteTransition`; do not
///   re-use it for anything inside a page.
///
/// Curves:
///
/// * [arrive]: elements entering or settling into a new state. Shared with
///   the brand loader and the web splash, so every arrival in the app
///   decelerates the same way.
/// * [exit]: elements leaving. Ease-in: they accelerate away, and at about
///   75 percent of the enter duration ([exitOf]).
/// * [out]: the release half of a press, and any micro-interaction that has
///   to feel instant at the start (ease-out-quint).
/// * [sheetCurve]: the iOS sheet curve, for [sheet] travel only.
///
/// Every duration read through [of] collapses to zero when the platform asks
/// for reduced motion, so implicit animations built on these tokens are
/// accessible by construction. Infinite loops are allowed for exactly one
/// element in the app, the brand orbit loader; nothing here should be used to
/// build a pulse, breathe or shimmer.
abstract final class ExampleMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration state = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 340);
  static const Duration route = Duration(milliseconds: 420);

  static const Curve arrive = Cubic(.2, .7, .2, 1);
  static const Curve exit = Cubic(.7, 0, .84, 0);
  static const Curve out = Cubic(.22, 1, .36, 1);
  static const Curve sheetCurve = Cubic(.32, .72, 0, 1);

  /// True when brand configuration disables motion or the platform asks for
  /// reduced motion (`prefers-reduced-motion` on web, "Reduce motion" on iOS,
  /// "Remove animations" on Android).
  static bool reduced(BuildContext context) =>
      !context.brandDesign.motionEnabled ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The configured multiple of [duration], or zero when motion is reduced.
  /// Pass the result straight into an implicit animation's `duration`.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context)
          ? Duration.zero
          : Duration(
              microseconds: (duration.inMicroseconds *
                      context.brandDesign.motionDurationScale)
                  .round(),
            );

  /// Exit duration for an element that entered over [enter]: three quarters
  /// of it, so leaving is always quicker than arriving.
  static Duration exitOf(Duration enter) =>
      Duration(microseconds: (enter.inMicroseconds * 3) ~/ 4);
}

/// Tactile press feedback for anything tappable that is not already a
/// Material button.
///
/// On pointer down the child scales to [pressedScale] over
/// [ExampleMotion.press] with [ExampleMotion.arrive]; on release or cancel it
/// returns over [ExampleMotion.state] with [ExampleMotion.out]. The scale is a
/// paint-time transform, so the child's layout bounds and its siblings never
/// move. Dragging further than the touch slop cancels the press, so a list
/// that starts scrolling does not leave a row squashed.
///
/// Two ways to use it:
///
/// * As the tap target. Pass [onTap] (and optionally [onLongPress],
///   [semanticsLabel]). The widget owns the gesture, announces itself as a
///   button, joins the keyboard tab order and draws an iris focus ring
///   (clipped to [borderRadius]) when focused from a keyboard.
/// * As a pure visual wrapper. Leave [onTap] and [onLongPress] null and wrap
///   any control with its own gesture (`FilledButton`, `InkWell`, a
///   `ExampleGlassPanel` with `onTap`). Pointer events pass straight through,
///   the child's callback fires as before, and only the scale is added.
///   No extra semantics node or focus stop is created, so a wrapped button
///   is still announced exactly once.
///
/// Under reduced motion the scale is disabled entirely; the child renders at
/// rest and taps still work. Keep the tappable area at least 44 x 44 pt; the
/// widget does not pad its child.
class ExamplePressable extends StatefulWidget {
  const ExamplePressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.pressedScale = .97,
    this.borderRadius,
    this.semanticsLabel,
    this.behavior = HitTestBehavior.translucent,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// When false, no press scale, no gesture, and semantics report disabled.
  final bool enabled;

  /// Scale at full press. .97 is the product default; go no lower than .94
  /// for large cards, and leave it at .97 for anything button-sized.
  final double pressedScale;

  /// Shape of the keyboard focus ring. Defaults to `AppRadii.md`.
  final BorderRadius? borderRadius;

  /// Accessible name when this widget owns the tap. When set it replaces
  /// the child's own semantics (the row reads "Open USD account", not the
  /// label followed by every line of text inside it); when null the child's
  /// text is announced. Ignored for a pure visual wrapper, where the child
  /// keeps its own semantics.
  final String? semanticsLabel;

  /// Hit-test behaviour of the pointer listener. Translucent by default so
  /// padding around a small child still registers as part of the target.
  final HitTestBehavior behavior;

  @override
  State<ExamplePressable> createState() => _ExamplePressableState();
}

class _ExamplePressableState extends State<ExamplePressable> {
  bool _pressed = false;
  bool _focused = false;
  Offset? _downPosition;

  bool get _ownsGesture => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _downPosition = event.position;
    _setPressed(true);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _downPosition;
    if (origin == null) return;
    if ((event.position - origin).distance > kTouchSlop) {
      _downPosition = null;
      _setPressed(false);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _downPosition = null;
    _setPressed(false);
  }

  void _activate() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = ExampleMotion.reduced(context);
    final pressed = _pressed && widget.enabled && !reduced;

    Widget result = AnimatedScale(
      scale: pressed ? widget.pressedScale : 1,
      duration: ExampleMotion.of(
          context, pressed ? ExampleMotion.press : ExampleMotion.state),
      curve: pressed ? ExampleMotion.arrive : ExampleMotion.out,
      child: widget.child,
    );

    if (_ownsGesture && _focused) {
      result = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ??
              BorderRadius.circular(context.brandShape.radius(AppRadii.md)),
          border: Border.all(color: ExamplePalette.of(context).accent, width: 2),
        ),
        child: result,
      );
    }

    result = Listener(
      behavior: widget.behavior,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: result,
    );

    if (!_ownsGesture) return result;

    final enabled = widget.enabled;
    return FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.semanticsLabel,
        excludeSemantics: widget.semanticsLabel != null,
        onTap: enabled ? widget.onTap : null,
        onLongPress: enabled ? widget.onLongPress : null,
        child: GestureDetector(
          behavior: widget.behavior,
          excludeFromSemantics: true,
          onTap: enabled ? widget.onTap : null,
          onLongPress: enabled ? widget.onLongPress : null,
          child: result,
        ),
      ),
    );
  }
}

/// `AnimatedSwitcher` preset for a component changing what it shows in place:
/// a label that becomes a spinner, a balance that finishes loading, a row
/// swapping its trailing icon for a check mark.
///
/// The incoming child fades in and rises 2 px over [ExampleMotion.state] with
/// [ExampleMotion.arrive]; the outgoing child fades out over three quarters
/// of that with [ExampleMotion.exit]. Under reduced motion the swap is
/// instant.
///
/// Give each distinct [child] its own `Key` (usually a `ValueKey` of the
/// state), exactly as with `AnimatedSwitcher`; children with equal keys and
/// types are treated as the same widget and are not animated.
///
/// Use this for state, not for lists: a screen of rows should never switch
/// each row through it on load.
class ExampleStateSwitch extends StatelessWidget {
  const ExampleStateSwitch({
    required this.child,
    this.duration,
    this.alignment = Alignment.center,
    super.key,
  });

  final Widget child;

  /// Enter duration. Defaults to [ExampleMotion.state].
  final Duration? duration;

  /// How the outgoing and incoming children are aligned while they overlap.
  final Alignment alignment;

  static const double _rise = 2;

  @override
  Widget build(BuildContext context) {
    final enter = ExampleMotion.of(context, duration ?? ExampleMotion.state);
    return AnimatedSwitcher(
      duration: enter,
      reverseDuration: ExampleMotion.exitOf(enter),
      switchInCurve: ExampleMotion.arrive,
      switchOutCurve: ExampleMotion.exit,
      transitionBuilder: _transition,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }

  static Widget _transition(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _rise * (1 - animation.value)),
            child: child,
          ),
        ),
      );
}

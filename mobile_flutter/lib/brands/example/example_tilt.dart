import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/branding/app_design.dart';
import '../../shared/theme/app_theme_extensions.dart';
import 'example_colors.dart';
import 'example_motion.dart';
import 'example_motion_stub.dart'
    if (dart.library.js_interop) 'example_motion_web.dart';

/// Tilts its child in 3D towards the pointer, with a soft sheen that follows
/// it, the way a card catches light in the hand. On a mouse the tilt follows
/// hover; on touch it engages after a short hold so a quick swipe still goes
/// to the page view, then follows the finger and springs back on release.
/// In the browser the card also follows the phone's attitude ([motion]):
/// the initial pose counts as flat. Once the phone stops moving, the card
/// returns fully flat within five seconds. A pointer always takes precedence.
class ExampleTiltCard extends StatefulWidget {
  const ExampleTiltCard({
    required this.child,
    this.maxAngle = 0.20,
    this.enabled = true,
    this.motion = true,
    this.debugMotionStream,
    super.key,
  });

  final Widget child;

  /// Maximum rotation around each axis, in radians (0.20 ≈ 11°).
  final double maxAngle;
  final bool enabled;

  /// Follow the device orientation sensor when the browser provides it.
  final bool motion;

  /// Supplies deterministic attitude readings without browser sensors in tests.
  @visibleForTesting
  final Stream<Offset>? debugMotionStream;

  @override
  State<ExampleTiltCard> createState() => _ExampleTiltCardState();
}

class _ExampleTiltCardState extends State<ExampleTiltCard>
    with SingleTickerProviderStateMixin {
  /// Degrees of device roll / pitch that give the full tilt.
  static const _motionRange = 22.0;

  /// Pointer position normalised to -1..1 on both axes; zero is flat.
  Offset _tilt = Offset.zero;
  bool _active = false;
  bool? _reducedMotion;
  bool _pointerReturning = false;
  Offset _pointerReturnTarget = Offset.zero;

  StreamSubscription<Offset>? _motion;
  Offset? _neutral;
  Offset? _latestAttitude;
  Offset? _motionAnchor;
  Offset _motionTilt = Offset.zero;

  // Compare against the last meaningful pose, not just the preceding sample:
  // this ignores stationary sensor jitter while still detecting a slow turn.
  static const _movementThresholdDegrees = .6;
  static const _stationaryDelay = Duration(milliseconds: 120);
  static const _returnDuration = Duration(seconds: 5);
  Timer? _stationaryTimer;
  Timer? _flatDeadline;
  late final AnimationController _recentre;
  Offset _returnFrom = Offset.zero;
  Offset _returnNeutral = Offset.zero;
  Offset _returnPose = Offset.zero;

  @override
  void initState() {
    super.initState();
    _recentre = AnimationController(
      vsync: this,
      duration: _returnDuration - _stationaryDelay,
    )..addListener(_animateRecentering);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = ExampleMotion.reduced(context);
    _recentre.duration =
        ExampleMotion.of(context, _returnDuration - _stationaryDelay);
    if (_reducedMotion != reduced) {
      _reducedMotion = reduced;
      _motion?.cancel();
      _motion = null;
      _stopRecentering();
      _startMotion();
    }
  }

  @override
  void didUpdateWidget(ExampleTiltCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled ||
        widget.motion != oldWidget.motion ||
        widget.debugMotionStream != oldWidget.debugMotionStream) {
      _motion?.cancel();
      _motion = null;
      _stopRecentering();
      _startMotion();
    }
  }

  @override
  void dispose() {
    _motion?.cancel();
    _stopRecentering();
    _recentre.dispose();
    super.dispose();
  }

  void _startMotion() {
    final wanted = (kIsWeb || widget.debugMotionStream != null) &&
        widget.enabled &&
        widget.motion &&
        _reducedMotion == false;
    _neutral = null;
    _latestAttitude = null;
    _motionAnchor = null;
    _motionTilt = Offset.zero;
    _pointerReturning = false;
    _pointerReturnTarget = Offset.zero;
    if (!widget.enabled || _reducedMotion != false) {
      _active = false;
      _tilt = Offset.zero;
    }
    if (!wanted || _motion != null) return;
    // Listen before asking: the browser gates delivery on permission. This
    // also picks up grants made by another card or retained by the PWA.
    _motion =
        (widget.debugMotionStream ?? deviceTiltStream()).listen(_onMotion);
  }

  void _stopRecentering() {
    _stationaryTimer?.cancel();
    _stationaryTimer = null;
    _flatDeadline?.cancel();
    _flatDeadline = null;
    _recentre.stop();
  }

  void _onMotion(Offset attitude) {
    if (_reducedMotion != false ||
        !attitude.dx.isFinite ||
        !attitude.dy.isFinite) {
      return;
    }
    _latestAttitude = attitude;
    if (_neutral == null) {
      _neutral = attitude;
      _motionAnchor = attitude;
      return;
    }
    if ((attitude - _motionAnchor!).distance < _movementThresholdDegrees) {
      return;
    }

    _stopRecentering();
    _motionAnchor = attitude;
    final target = Offset(
      ((attitude.dx - _neutral!.dx) / _motionRange).clamp(-1.0, 1.0),
      ((attitude.dy - _neutral!.dy) / _motionRange).clamp(-1.0, 1.0),
    );
    setState(() => _motionTilt += (target - _motionTilt) * .3);
    _stationaryTimer =
        Timer(ExampleMotion.of(context, _stationaryDelay), _beginRecentering);
    // Sensor events may stop completely when the device settles. This timer
    // guarantees a real zero at five seconds even without another sample or
    // when animation frames were suspended while the app was backgrounded.
    _flatDeadline =
        Timer(ExampleMotion.of(context, _returnDuration), _finishRecentering);
  }

  void _beginRecentering() {
    _stationaryTimer = null;
    if (!mounted) return;
    _returnFrom = _motionTilt;
    _returnNeutral = _neutral!;
    _returnPose = _latestAttitude!;
    _recentre.forward(from: 0);
  }

  void _animateRecentering() {
    if (!mounted) return;
    final progress = Curves.easeOutCubic.transform(_recentre.value);
    setState(() {
      _motionTilt = _returnFrom * (1 - progress);
      _neutral = Offset.lerp(_returnNeutral, _returnPose, progress);
    });
  }

  void _finishRecentering() {
    _stopRecentering();
    if (!mounted) return;
    setState(() {
      _motionTilt = Offset.zero;
      // A pointer release that was heading toward an old sensor pose must
      // not leave that stale pose visible beyond the motion deadline.
      if (!_active && _pointerReturnTarget != Offset.zero) {
        _pointerReturning = false;
        _pointerReturnTarget = Offset.zero;
      }
      _neutral = _latestAttitude;
      _motionAnchor = _latestAttitude;
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    _stopRecentering();
    _neutral = null;
    _latestAttitude = null;
    _motionAnchor = null;
    _motionTilt = Offset.zero;
    _pointerReturning = false;
    _pointerReturnTarget = Offset.zero;
  }

  void _ensureMotionPermission() {
    if (!kIsWeb || !widget.motion || !motionNeedsPermission) return;
    unawaited(requestMotionPermission());
  }

  void _update(Offset local, Size size) {
    if (size.isEmpty) return;
    final dx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() {
      _tilt = Offset(dx, dy);
      _active = true;
      _pointerReturning = false;
    });
  }

  void _release() {
    if (!_active && _tilt == Offset.zero) return;
    setState(() {
      // Releasing exactly at the target creates no implicit animation, so
      // there would be no onEnd callback to hand control back to the sensor.
      _pointerReturning = _tilt != _motionTilt;
      _pointerReturnTarget = _motionTilt;
      _tilt = Offset.zero;
      _active = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || ExampleMotion.reduced(context)) return widget.child;
    final sheen = context.brandDesign.isConfigured
        ? ExamplePalette.of(context).sheenPeak
        : ExampleColors.pearl;
    final borderRadius = BorderRadius.circular(context.brandShape.radius(18));
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return MouseRegion(
          onHover: (event) => _update(event.localPosition, size),
          onExit: (_) => _release(),
          // A raw release listener also runs when a card's InkWell wins the
          // tap gesture, and does not steal taps from navigation controls.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            // Touch-down is too early for Safari's transient user activation.
            // Request synchronously from touch-up, before any await.
            onPointerUp: (_) => _ensureMotionPermission(),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (details) {
                HapticFeedback.selectionClick();
                _update(details.localPosition, size);
              },
              onLongPressMoveUpdate: (details) =>
                  _update(details.localPosition, size),
              onLongPressEnd: (_) => _release(),
              onLongPressCancel: _release,
              child: TweenAnimationBuilder<Offset>(
                tween: Tween(
                  end: _active
                      ? _tilt
                      : _pointerReturning
                          ? _pointerReturnTarget
                          : _motionTilt,
                ),
                // The motion controller already eases to a strict five-second
                // deadline; an extra implicit tween would keep lagging behind.
                // Pointer tracking and its release spring keep their timings.
                duration: ExampleMotion.of(
                    context,
                    _active
                        ? const Duration(milliseconds: 90)
                        : _pointerReturning
                            ? (_pointerReturnTarget == Offset.zero
                                ? const Duration(milliseconds: 520)
                                : const Duration(milliseconds: 120))
                            : Duration.zero),
                curve: _active || _pointerReturnTarget != Offset.zero
                    ? Curves.easeOut
                    : Curves.easeOutBack,
                onEnd: () {
                  if (_pointerReturning && mounted) {
                    setState(() => _pointerReturning = false);
                  }
                },
                builder: (context, tilt, child) {
                  final strength = math.min(1.0, tilt.distance);
                  // The near edge of a rotated face projects past its box and
                  // parents clip it; shrink a little as the tilt grows so it
                  // always stays inside.
                  final shrink = 1 - strength * widget.maxAngle * .45;
                  final transform = Matrix4.identity()
                    ..setEntry(3, 2, .0016)
                    ..rotateX(-tilt.dy * widget.maxAngle)
                    ..rotateY(tilt.dx * widget.maxAngle)
                    ..scaleByDouble(shrink, shrink, 1, 1);
                  return Transform(
                    alignment: Alignment.center,
                    transform: transform,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        child!,
                        // Light sheen that slides opposite to the tilt.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius: borderRadius,
                              child: Opacity(
                                opacity: strength * .55,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment(tilt.dx, tilt.dy),
                                      radius: 1.1,
                                      colors: [
                                        sheen.withValues(alpha: .28),
                                        sheen.withValues(alpha: .0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/branding/app_design.dart';
import 'example_colors.dart';
import 'example_motion.dart';

/// Golden-ratio conjugate. Phases spaced by this never fall into a repeating
/// pattern, so a screen full of sheen hosts never sweeps in unison.
const double _goldenConjugate = 0.6180339887498949;

/// Shortest and longest a single sweep may take (the law: 1.2 to 1.6 s).
const int _sweepMinMs = 1200;
const int _sweepSpanMs = 400;

/// Delay between a host mounting (and its route settling) and its arrival
/// sweep. Long enough that the sweep reads as a second beat after the page,
/// short enough to still belong to the arrival.
const Duration _arrivalDelay = Duration(milliseconds: 250);

/// Band width as a fraction of the host's width.
const double _bandFactor = .35;

/// Where the band centre sits at rest, as a fraction of the host's width,
/// when there is no ticker (reduced motion, or no scope).
const double _staticCenterFactor = .30;

/// Travel of the band, as a multiple of the host's width: a band that rests
/// centred on the host is translated from -1.2w to +1.2w, so it starts and
/// ends fully off-canvas and never pops.
const double _travel = 1.2;

/// Peak alpha of the band, before [ExampleSheenIntensity] halves it.
///
/// Dark is pearl, light is [ExampleColors.lightIris]. A white band on paper is
/// mathematically inert — white over #FFFFFF is 1.00:1, over the skeleton base
/// 1.07:1 — so on daylight the band is a tint that crosses a pale surface, the
/// way a specular sweep actually reads on matte material, and only a saturated
/// fill gets the white variant.
const double _peakAlphaDark = .14;
const double _peakAlphaLight = .20;

/// Peak alpha for [ExampleSheenIntensity.onFill]. Solved, not chosen: a white
/// band over [ExampleColors.lightViolet] may not exceed .092 alpha without
/// pushing a white label under 4.5:1, and pearl over dark violet may not
/// exceed ~.05 without deepening an already tight 3.95:1.
const double _peakAlphaOnFillDark = .05;
const double _peakAlphaOnFillLight = .09;

/// How hard the band reads at its peak.
///
/// * [normal]: the default. Pearl at .14 on dark, lightIris at .20 on light.
/// * [soft]: half of that. Use it when the host is already bright (a skeleton
///   block on a light page) or when two hosts sit next to each other and one
///   has to recede.
/// * [onFill]: the band sits on a saturated fill that carries a label — a
///   primary CTA, the active nav indicator. The band paints *above* the child,
///   so on a filled button it composites over the glyphs too; at [normal] a
///   white label on lightViolet drops to 2.78:1 and at [soft] to 3.83:1. This
///   peak is the largest one that leaves the label legible (light 4.51:1), and
///   it is white rather than a tint because a violet fill is the one host a
///   white band can actually lift.
///
/// The static highlight drawn under reduced motion uses the [soft] peak for
/// [soft] and [normal] hosts — a permanent band should never be as loud as one
/// that passes — and the [onFill] peak for [onFill] hosts, because there the
/// contrast ceiling, not the loudness, is what sets the budget.
enum ExampleSheenIntensity { soft, normal, onFill }

double _peakAlpha(Brightness brightness, ExampleSheenIntensity intensity) {
  final dark = brightness == Brightness.dark;
  switch (intensity) {
    case ExampleSheenIntensity.onFill:
      return dark ? _peakAlphaOnFillDark : _peakAlphaOnFillLight;
    case ExampleSheenIntensity.soft:
      return (dark ? _peakAlphaDark : _peakAlphaLight) / 2;
    case ExampleSheenIntensity.normal:
      return dark ? _peakAlphaDark : _peakAlphaLight;
  }
}

Color _peakColor(BuildContext context, Brightness brightness,
    ExampleSheenIntensity intensity) {
  final design = context.brandDesign;
  if (design.isConfigured) {
    final palette = ExamplePalette.fromDesign(brightness, design);
    return design.color(brightness, 'sheenPeak',
        fallback: intensity == ExampleSheenIntensity.onFill
            ? palette.onFill
            : palette.isDark
                ? palette.ink
                : palette.accent);
  }
  if (brightness == Brightness.dark) return ExampleColors.pearl;
  return intensity == ExampleSheenIntensity.onFill
      ? Colors.white
      : ExampleColors.lightIris;
}

/// The peak a host paints when nothing is ticking (reduced motion, or no
/// scope). Softens everything except [ExampleSheenIntensity.onFill], which is
/// already at its contrast ceiling and must not be raised.
ExampleSheenIntensity _restIntensity(ExampleSheenIntensity intensity) =>
    intensity == ExampleSheenIntensity.onFill
        ? intensity
        : ExampleSheenIntensity.soft;

/// The clock behind every [ExampleSheen] under one [ExampleSheenScope].
///
/// One [Ticker] serves the whole screen, and it only runs while a sweep is in
/// flight: between sweeps the scope holds a [Timer] per host and the engine is
/// left alone. Each host gets a phase from the golden-ratio sequence, so their
/// idle sweeps stay permanently out of step.
///
/// Obtain it with [ExampleSheenScope.maybeOf]. Screens do not normally touch
/// it; it is public so a screen can check whether a scope already exists
/// before adding another, and so tests can inspect the schedule.
class ExampleSheenController {
  ExampleSheenController._({
    required TickerProvider vsync,
    required Duration cadence,
    required bool enabled,
    required bool resumed,
  })  : _cadence = cadence,
        _enabled = enabled,
        _resumed = resumed {
    _ticker = vsync.createTicker(_onTick);
    _running = _gatesOpen;
  }

  late final Ticker _ticker;
  final List<ExampleSheenHandle> _hosts = <ExampleSheenHandle>[];

  /// Elapsed time reported by the last tick. The ticker restarts from zero
  /// every time it wakes, so this is the only clock a sweep measures against.
  Duration _elapsed = Duration.zero;

  Duration _cadence;
  double _durationScale = 1;
  int _nextIndex = 0;
  bool _enabled;
  bool _resumed;
  bool _routeCurrent = true;
  bool _tickerMode = true;
  bool _running = true;
  bool _disposed = false;

  /// How often each host sweeps once it has arrived.
  Duration get cadence => _cadence;

  /// Whether sweeps are being scheduled at all. False while the scope's route
  /// is covered, the app is not resumed, `TickerMode` is off, or the scope was
  /// built with `enabled: false`.
  bool get isRunning => _running;

  /// Whether the shared ticker is currently burning frames. Only true while at
  /// least one host is mid-sweep.
  bool get isTicking => _ticker.isActive;

  /// Hosts currently registered, in registration order.
  List<ExampleSheenHandle> get hosts => List<ExampleSheenHandle>.unmodifiable(
        _hosts,
      );

  bool get _gatesOpen => _enabled && _resumed && _routeCurrent && _tickerMode;

  /// Registers a host and hands back its per-host clock. Call from
  /// `didChangeDependencies`, and pass the handle to [detach] in `dispose`.
  ExampleSheenHandle attach({bool idle = true}) {
    assert(!_disposed, 'ExampleSheenController used after dispose.');
    final handle = ExampleSheenHandle._(
      controller: this,
      index: _nextIndex++,
      idle: idle,
    );
    _hosts.add(handle);
    if (_running) handle._scheduleIdle(first: true);
    return handle;
  }

  /// Unregisters and disposes [handle]. Safe to call twice.
  void detach(ExampleSheenHandle handle) {
    if (!_hosts.remove(handle)) return;
    handle._teardown();
    if (_hosts.every((host) => !host._sweeping) && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _setGates({
    bool? enabled,
    bool? resumed,
    bool? routeCurrent,
    bool? tickerMode,
  }) {
    if (_disposed) return;
    _enabled = enabled ?? _enabled;
    _resumed = resumed ?? _resumed;
    _routeCurrent = routeCurrent ?? _routeCurrent;
    _tickerMode = tickerMode ?? _tickerMode;
    final next = _gatesOpen;
    if (next == _running) return;
    _running = next;
    if (next) {
      for (final host in _hosts) {
        host._scheduleIdle(first: false);
        host._flushArrival();
      }
    } else {
      for (final host in _hosts) {
        host._pause();
      }
      if (_ticker.isActive) _ticker.stop();
    }
  }

  void _setTiming(Duration cadence, double durationScale) {
    if (_cadence == cadence && _durationScale == durationScale) return;
    _cadence = cadence;
    _durationScale = durationScale;
    if (!_running) return;
    for (final host in _hosts) {
      host._scheduleIdle(first: false);
    }
  }

  void _beginSweep(ExampleSheenHandle host) {
    if (!_running || _disposed) return;
    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _ticker.start();
    }
    host._start = _elapsed;
    host._sweeping = true;
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    var active = false;
    for (var i = 0; i < _hosts.length; i++) {
      final host = _hosts[i];
      if (!host._sweeping) continue;
      final span = host.sweepDuration.inMicroseconds;
      final raw = (elapsed - host._start).inMicroseconds / span;
      if (raw >= 1) {
        host._settle();
      } else {
        host._set(ExampleMotion.out.transform(raw < 0 ? 0 : raw));
        active = true;
      }
    }
    if (!active && _ticker.isActive) _ticker.stop();
  }

  /// Stops the ticker, cancels every pending sweep and disposes every handle
  /// that a host has not already detached.
  void dispose() {
    _disposed = true;
    _running = false;
    _ticker.dispose();
    for (final host in List<ExampleSheenHandle>.of(_hosts)) {
      host._teardown();
    }
    _hosts.clear();
  }
}

/// One host's slot in a [ExampleSheenScope].
///
/// The value is the eased position of the band, 0 at rest and running 0 to 1
/// across a sweep; the overlay listens to it directly so a sweep repaints one
/// layer and never rebuilds the host's subtree.
class ExampleSheenHandle extends ChangeNotifier
    implements ValueListenable<double> {
  ExampleSheenHandle._({
    required ExampleSheenController controller,
    required int index,
    required this.idle,
  })  : _controller = controller,
        phase = (index * _goldenConjugate) % 1.0;

  final ExampleSheenController _controller;

  /// Whether this host sweeps again after arrival.
  final bool idle;

  /// This host's offset in the cadence, 0 to 1, spaced from every other host
  /// by the golden-ratio conjugate.
  final double phase;

  double _value = 0;
  bool _sweeping = false;
  bool _wantsArrival = false;
  bool _dead = false;
  Duration _start = Duration.zero;
  Timer? _idleTimer;

  @override
  double get value => _value;

  /// True while the band is crossing the host.
  bool get isSweeping => _sweeping;

  /// Length of this host's sweep, 1.2 s to 1.6 s, derived from [phase] so two
  /// hosts that do start together still finish apart.
  Duration get sweepDuration => Duration(
        microseconds: ((_sweepMinMs + (phase * _sweepSpanMs).round()) *
                Duration.microsecondsPerMillisecond *
                _controller._durationScale)
            .round(),
      );

  /// Delay until this host's first idle sweep: a full cadence plus its phase,
  /// so the screen never fires two bands on the same frame.
  Duration get firstIdleDelay =>
      _controller.cadence + _controller.cadence * phase;

  /// Asks for the arrival sweep. Runs now when the scope is live, and is held
  /// until the route is current and the app is resumed when it is not.
  void requestArrival() {
    if (_dead) return;
    _wantsArrival = true;
    _flushArrival();
  }

  void _flushArrival() {
    if (_dead || !_wantsArrival || !_controller._running) return;
    _wantsArrival = false;
    _controller._beginSweep(this);
  }

  void _scheduleIdle({required bool first}) {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_dead || !idle || !_controller._running) return;
    _idleTimer = Timer(first ? firstIdleDelay : _controller.cadence, _onIdle);
  }

  void _onIdle() {
    _idleTimer = null;
    if (_dead || !_controller._running) return;
    _controller._beginSweep(this);
    _scheduleIdle(first: false);
  }

  void _set(double value) {
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }

  void _settle() {
    _sweeping = false;
    _set(0);
  }

  void _pause() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _sweeping = false;
    _set(0);
  }

  void _teardown() {
    _dead = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _sweeping = false;
    _value = 0;
    dispose();
  }
}

/// The one ticker a Example screen is allowed to keep.
///
/// Wrap a screen's body in a scope and every [ExampleSheen] inside it shares a
/// single [Ticker], a single schedule and a single set of pause rules. Put it
/// once, high: around the `Scaffold` body of a page, or around a sheet's
/// content. Two scopes on one screen means two tickers and two unrelated
/// rhythms, so check [maybeOf] before adding another.
///
/// The scope stops entirely — ticker and timers — whenever the sheen would be
/// wasted work or a distraction:
///
/// * the enclosing `ModalRoute` is no longer current (another page covers it),
/// * the app is not `resumed` (backgrounded, hidden, or an inactive browser
///   tab),
/// * `TickerMode` is off (an off-screen tab of a `TabBarView`, a page kept
///   alive under a `Navigator`),
/// * [enabled] is false.
///
/// While it is stopped, `maybeOf` returns null for `enabled: false`, so hosts
/// fall back to the same static highlight they draw under reduced motion. It
/// is a kill switch a screen can flip without any host knowing.
class ExampleSheenScope extends StatefulWidget {
  const ExampleSheenScope({
    required this.child,
    this.cadence = const Duration(seconds: 7),
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// How often each host sweeps after arrival. The law's range is 6 to 8 s;
  /// 7 s is the product default and hosts are staggered inside it by phase.
  final Duration cadence;

  /// Master switch. False renders every descendant [ExampleSheen] as its static
  /// highlight and never starts a ticker.
  final bool enabled;

  /// The controller for the nearest enclosing scope, or null when there is no
  /// scope above [context] or the nearest one is disabled.
  ///
  /// Establishes a dependency: a widget that calls this rebuilds when the
  /// scope appears, disappears or is disabled.
  static ExampleSheenController? maybeOf(BuildContext context) {
    final binding =
        context.dependOnInheritedWidgetOfExactType<_ExampleSheenBinding>();
    if (binding == null || !binding.enabled) return null;
    return binding.controller;
  }

  /// Whether a scope exists above [context] at all, switched on or off.
  ///
  /// [maybeOf] deliberately returns null for a disabled scope so hosts fall
  /// back to the static highlight — which makes it the wrong question for
  /// "should I add a scope here?". A shell that asked [maybeOf] would nest a
  /// second, enabled scope underneath a deliberately disabled one and defeat
  /// the kill switch. Ask this instead before wrapping a subtree.
  static bool existsAbove(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ExampleSheenBinding>() != null;

  @override
  State<ExampleSheenScope> createState() => _ExampleSheenScopeState();
}

class _ExampleSheenScopeState extends State<ExampleSheenScope>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final ExampleSheenController _controller;
  ValueListenable<TickerModeData>? _tickerMode;

  /// Mirrors `MediaQuery.disableAnimations`, folded into the scope's own
  /// `enabled` so a reduced-motion viewer gets no sheen at all rather than a
  /// faster one. This matters far more since the sheen became an endless idle
  /// loop: a single arrival sweep someone did not want is over in 600 ms, but
  /// a loop they did not want never stops. When this is true the binding
  /// publishes `enabled: false`, `maybeOf` returns null, and every host paints
  /// its child plain — no ticker, no timer, no band.
  bool _reducedMotion = false;

  bool get _effectiveEnabled => widget.enabled && !_reducedMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _controller = ExampleSheenController._(
      vsync: this,
      cadence: widget.cadence,
      enabled: widget.enabled,
      resumed: lifecycle == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (notifier != _tickerMode) {
      _tickerMode?.removeListener(_onTickerMode);
      _tickerMode = notifier..addListener(_onTickerMode);
    }
    // Reading it here (not in initState, where there is no MediaQuery yet)
    // also establishes the dependency, so flipping the OS setting re-runs this
    // and the loop stops without a restart.
    _reducedMotion = ExampleMotion.reduced(context);
    _updateTiming();
    _controller._setGates(
      enabled: _effectiveEnabled,
      tickerMode: notifier.value.enabled,
      // ModalRoute.of establishes a dependency on the route's status, so this
      // runs again the moment another page covers or uncovers this one.
      routeCurrent: ModalRoute.of(context)?.isCurrent ?? true,
    );
  }

  @override
  void didUpdateWidget(ExampleSheenScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cadence != oldWidget.cadence) {
      _updateTiming();
    }
    if (widget.enabled != oldWidget.enabled) {
      _controller._setGates(enabled: _effectiveEnabled);
    }
  }

  void _updateTiming() => _controller._setTiming(
        ExampleMotion.of(context, widget.cadence),
        ExampleMotion.of(context, const Duration(seconds: 1)).inMicroseconds /
            Duration.microsecondsPerSecond,
      );

  void _onTickerMode() =>
      _controller._setGates(tickerMode: _tickerMode?.value.enabled ?? true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller._setGates(resumed: state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onTickerMode);
    _tickerMode = null;
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ExampleSheenBinding(
        controller: _controller,
        enabled: _effectiveEnabled,
        child: widget.child,
      );
}

class _ExampleSheenBinding extends InheritedWidget {
  const _ExampleSheenBinding({
    required this.controller,
    required this.enabled,
    required super.child,
  });

  final ExampleSheenController controller;
  final bool enabled;

  @override
  bool updateShouldNotify(_ExampleSheenBinding oldWidget) =>
      controller != oldWidget.controller || enabled != oldWidget.enabled;
}

/// A band of light that crosses [child] once on arrival and then every
/// cadence, so a still screen still feels powered.
///
/// The band is 35 percent of the host's width, tilted [angleDegrees], and
/// travels from fully off one edge to fully off the other over 1.2 to 1.6 s on
/// [ExampleMotion.out]. It is painted above the child inside a `ClipRRect`, an
/// `IgnorePointer` and a `RepaintBoundary`, and it is driven by a listenable
/// the painter subscribes to: a sweep repaints one layer and never rebuilds
/// the child.
///
/// **Allowed hosts, and nothing else.** The sheen is the brand's one liveness
/// signal; spend it on material, never on content:
///
/// * a progress or step bar,
/// * the screen's primary CTA,
/// * the top hairline of a panel,
/// * the edge of the card artwork,
/// * a `ExampleSkeleton` block while data loads,
/// * the active navigation indicator,
/// * exactly one headline or wordmark per screen, via [ExampleSheen.text].
///
/// Never on body text, list rows, table cells, icons or amounts. A balance
/// that shines is a balance nobody trusts.
///
/// **Frequency gate.** Anything the user meets hundreds of times a day does
/// not animate past the 120 ms press, so a sheen host must be a surface the
/// user looks at, not one they operate. Keep it to two or three hosts per
/// screen: they share one ticker, but they also share the user's attention.
///
/// **When it goes still.** With reduced motion on, with no
/// [ExampleSheenScope] above it, or with both [sweepOnArrival] and [idle] off,
/// the widget paints a fixed soft highlight 30 percent across the host and
/// starts no ticker at all. The material still reads; nothing moves.
class ExampleSheen extends StatelessWidget {
  const ExampleSheen({
    required this.child,
    this.borderRadius,
    this.intensity = ExampleSheenIntensity.normal,
    this.sweepOnArrival = true,
    this.idle = true,
    this.angleDegrees = 20,
    this.material,
    super.key,
  })  : _asText = false,
        assert(
          angleDegrees >= 18 && angleDegrees <= 24,
          'Example sheen tilts 18 to 24 degrees.',
        );

  /// A sheen that only touches glyphs.
  ///
  /// Masks the band with the child's own alpha through
  /// `ShaderMask(blendMode: BlendMode.srcATop)`, so a headline shines and the
  /// space around it stays flat. One per screen, on a headline or the
  /// wordmark; never on a paragraph, a label or an amount.
  ///
  /// [borderRadius] is ignored here: the glyphs are the clip.
  const ExampleSheen.text({
    required this.child,
    this.borderRadius,
    this.intensity = ExampleSheenIntensity.normal,
    this.sweepOnArrival = true,
    this.idle = true,
    this.angleDegrees = 20,
    this.material,
    super.key,
  })  : _asText = true,
        assert(
          angleDegrees >= 18 && angleDegrees <= 24,
          'Example sheen tilts 18 to 24 degrees.',
        );

  final Widget child;

  /// Shape of the clip the band is cut to. Match the host's own radius, or
  /// leave null for a square host. Ignored by [ExampleSheen.text].
  final BorderRadius? borderRadius;

  /// Peak strength of the band. See [ExampleSheenIntensity].
  final ExampleSheenIntensity intensity;

  /// One sweep 250 ms after the host mounts and the route animation has
  /// finished. Nothing runs during the 420 ms route transition.
  final bool sweepOnArrival;

  /// Keep sweeping every `ExampleSheenScope.cadence` afterwards. Turn it off
  /// for a host that should only greet the user once.
  final bool idle;

  /// Tilt of the band in degrees, 18 to 24. 20 is the product default.
  final double angleDegrees;

  /// Brightness of the material the band lands on, when that is not the page's
  /// brightness. Null — the default — follows the theme.
  ///
  /// The one host this exists for is the card artwork, which stays night in
  /// both themes: on pearl daylight the theme would hand it the paper band (a
  /// violet tint), which darkens a dark card instead of lighting it. Pass
  /// `Brightness.dark` and the card keeps its pearl glint on a white page.
  final Brightness? material;

  final bool _asText;

  @override
  Widget build(BuildContext context) {
    final controller = ExampleSheenScope.maybeOf(context);
    final brightness = material ?? Theme.of(context).brightness;
    final live = controller != null &&
        !ExampleMotion.reduced(context) &&
        (sweepOnArrival || idle);
    if (!live) {
      final rest = _restIntensity(intensity);
      return _SheenOverlay(
        progress: null,
        peak: _peakColor(context, brightness, rest)
            .withValues(alpha: _peakAlpha(brightness, rest)),
        angleDegrees: angleDegrees,
        borderRadius: borderRadius,
        asText: _asText,
        child: child,
      );
    }
    return _LiveSheen(
      controller: controller,
      peak: _peakColor(context, brightness, intensity)
          .withValues(alpha: _peakAlpha(brightness, intensity)),
      angleDegrees: angleDegrees,
      borderRadius: borderRadius,
      sweepOnArrival: sweepOnArrival,
      idle: idle,
      asText: _asText,
      child: child,
    );
  }
}

/// Owns one [ExampleSheenHandle], the route gate and the arrival timer. Only
/// built when a live scope is in play, so reduced motion never reaches a
/// ticker.
class _LiveSheen extends StatefulWidget {
  const _LiveSheen({
    required this.controller,
    required this.peak,
    required this.angleDegrees,
    required this.borderRadius,
    required this.sweepOnArrival,
    required this.idle,
    required this.asText,
    required this.child,
  });

  final ExampleSheenController controller;
  final Color peak;
  final double angleDegrees;
  final BorderRadius? borderRadius;
  final bool sweepOnArrival;
  final bool idle;
  final bool asText;
  final Widget child;

  @override
  State<_LiveSheen> createState() => _LiveSheenState();
}

class _LiveSheenState extends State<_LiveSheen> {
  ExampleSheenHandle? _handle;
  ModalRoute<dynamic>? _route;
  Animation<double>? _waitingOn;
  Timer? _arrivalTimer;
  bool _arrived = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindHandle();
    // ModalRoute.of establishes a dependency on the route's status, so this
    // re-reads the route whenever it is covered, uncovered or replaced.
    _route = ModalRoute.of(context);
    _startArrivalCountdown();
  }

  @override
  void didUpdateWidget(_LiveSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.idle != oldWidget.idle) {
      _bindHandle(force: true);
    }
  }

  void _bindHandle({bool force = false}) {
    if (!force && _handle != null) return;
    final previous = _handle;
    if (previous != null) {
      _handle = null;
      previous._controller.detach(previous);
    }
    _handle = widget.controller.attach(idle: widget.idle);
  }

  void _startArrivalCountdown() {
    if (!widget.sweepOnArrival || _arrived) return;
    if (_arrivalTimer != null || _waitingOn != null) return;
    _arrivalTimer =
        Timer(ExampleMotion.of(context, _arrivalDelay), _onArrivalDue);
  }

  /// 250 ms after the host mounted. The route is only trustworthy this late:
  /// while a page is still being installed its animation reports itself
  /// complete, so the handoff is checked here, not at mount.
  void _onArrivalDue() {
    _arrivalTimer = null;
    if (_arrived || !mounted) return;
    final animation = _route?.animation;
    if (animation == null ||
        animation.status == AnimationStatus.completed ||
        animation.value >= 1) {
      _arrived = true;
      _stopWaiting();
      _handle?.requestArrival();
      return;
    }
    // Mid-handoff: nothing may run during the 420 ms route transition, so
    // wait for it and start the 250 ms again from there.
    if (!identical(_waitingOn, animation)) {
      _stopWaiting();
      _waitingOn = animation..addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _stopWaiting();
    if (_arrived || !mounted) return;
    _arrivalTimer?.cancel();
    _arrivalTimer =
        Timer(ExampleMotion.of(context, _arrivalDelay), _onArrivalDue);
  }

  void _stopWaiting() {
    _waitingOn?.removeStatusListener(_onRouteStatus);
    _waitingOn = null;
  }

  @override
  void dispose() {
    _arrivalTimer?.cancel();
    _arrivalTimer = null;
    _stopWaiting();
    _route = null;
    final handle = _handle;
    _handle = null;
    if (handle != null) handle._controller.detach(handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheenOverlay(
        progress: _handle,
        peak: widget.peak,
        angleDegrees: widget.angleDegrees,
        borderRadius: widget.borderRadius,
        asText: widget.asText,
        child: widget.child,
      );
}

/// Paints the band over [child]. [progress] null means "no ticker": the band
/// is drawn once, at rest, 30 percent across.
class _SheenOverlay extends StatelessWidget {
  const _SheenOverlay({
    required this.progress,
    required this.peak,
    required this.angleDegrees,
    required this.borderRadius,
    required this.asText,
    required this.child,
  });

  final ValueListenable<double>? progress;
  final Color peak;
  final double angleDegrees;
  final BorderRadius? borderRadius;
  final bool asText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (asText) return _text();
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Stack(
          // passthrough forwards the incoming constraints unchanged, so a
          // tight width stays tight. The default (StackFit.loose) relaxed it
          // and every wrapped FilledButton collapsed to its label width — a
          // full-bleed "Sign in" measured 339 px before the sheen and 68 px
          // after. Loose parents are unaffected: passthrough leaves them loose.
          fit: StackFit.passthrough,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                // The boundary is what keeps a sweep to one layer: the painter
                // repaints on its listenable, the child never does.
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: ExampleSheenPainter(
                      progress: progress,
                      peak: peak,
                      angleDegrees: angleDegrees,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _text() {
    final listenable = progress;
    if (listenable == null) {
      return RepaintBoundary(
        child: ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => exampleSheenShader(
            bounds: bounds,
            progress: exampleSheenStaticProgress,
            peak: peak,
            angleDegrees: angleDegrees,
          ),
          child: child,
        ),
      );
    }
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: listenable,
        child: child,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => exampleSheenShader(
            bounds: bounds,
            progress: listenable.value,
            peak: peak,
            angleDegrees: angleDegrees,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Progress at which the band centre sits [_staticCenterFactor] across the
/// host: the resting position used when there is no ticker.
const double exampleSheenStaticProgress =
    (_staticCenterFactor - .5 + _travel) / (2 * _travel);

/// The band itself: a transparent to [peak] to transparent stripe, 35 percent
/// of [bounds] wide, rotated [angleDegrees], with its centre at [progress]
/// along the -1.2w to +1.2w travel.
///
/// `TileMode.clamp` on a rotated linear gradient extends the two transparent
/// ends forever, so one shader covers the host and only the stripe shows.
Shader exampleSheenShader({
  required Rect bounds,
  required double progress,
  required Color peak,
  required double angleDegrees,
}) {
  final width = bounds.width <= 0 ? 1.0 : bounds.width;
  final centerX = bounds.left + width * (.5 - _travel + progress * 2 * _travel);
  final band = Rect.fromCenter(
    center: Offset(centerX, bounds.center.dy),
    width: width * _bandFactor,
    height: bounds.height <= 0 ? 1 : bounds.height,
  );
  final transparent = peak.withValues(alpha: 0);
  return LinearGradient(
    colors: [transparent, peak, transparent],
    stops: const [0, .5, 1],
    transform: GradientRotation(angleDegrees * math.pi / 180),
  ).createShader(band);
}

/// Draws the Example sheen band. Public so a test can read the band's position
/// and peak without going through pixels.
class ExampleSheenPainter extends CustomPainter {
  ExampleSheenPainter({
    required this.progress,
    required this.peak,
    required this.angleDegrees,
  }) : super(repaint: progress);

  /// The sweep clock, or null when the band is static.
  final ValueListenable<double>? progress;

  /// Band colour at its peak, alpha included.
  final Color peak;

  /// Tilt of the band in degrees.
  final double angleDegrees;

  /// True when no ticker drives this painter.
  bool get isStatic => progress == null;

  /// Current position of the band along its travel, 0 to 1.
  double get value => progress?.value ?? exampleSheenStaticProgress;

  /// Where the band centre sits, as a fraction of the host's width. 0 is the
  /// left edge, 1 the right; outside 0..1 the band is off-canvas.
  double get centerFactor => .5 - _travel + value * 2 * _travel;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = value;
    // Off-canvas at both ends of the travel: nothing to draw, and nothing to
    // pop when a sweep starts or finishes.
    if (t <= 0 || t >= 1) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = exampleSheenShader(
          bounds: bounds,
          progress: t,
          peak: peak,
          angleDegrees: angleDegrees,
        ),
    );
  }

  @override
  bool shouldRepaint(ExampleSheenPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.peak != peak ||
      oldDelegate.angleDegrees != angleDegrees;
}

/// Adds one [ExampleSheenScope] to a subtree, but only if nothing above it has
/// already provided one.
///
/// Every looping surface in the app rides a scope rather than owning one, so
/// that a screen full of sheens costs one ticker instead of a dozen. That only
/// holds if each host asks the same question the same way, and the question is
/// [ExampleSheenScope.existsAbove] — never `maybeOf`, which returns null for a
/// scope that is switched *off* and would therefore answer "no scope here" to
/// a host standing directly under a deliberately disabled one, nesting an
/// enabled scope inside it and defeating the kill switch.
///
/// This existed twice as a private copy — once in the shell, once in Rewards —
/// and the two drifted apart, with one of them carrying exactly that bug. One
/// widget, in the vocabulary, so there is nothing left to drift.
class ExampleAliveLayer extends StatelessWidget {
  const ExampleAliveLayer({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// False leaves the subtree without a scope of its own. A screen that has
  /// nothing to animate says so here rather than mounting a clock it will
  /// never read.
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      !enabled || ExampleSheenScope.existsAbove(context)
          ? child
          : ExampleSheenScope(child: child);
}

import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../brands/example/example_sheen.dart';
import '../../../../brands/example/example_tokens.dart';
import '../../../../brands/example/example_typography.dart';
import '../../../../brands/example/example_ui.dart';
import '../../../../core/branding/app_design.dart';
import '../../../../core/models/banking_models.dart';
import '../../domain/dashboard_models.dart';

/// A cent. Money is compared against this, never against zero: a balance
/// walked backwards through a list of doubles does not come back bit
/// identical, and a chart that treats 1e-14 as movement draws a trend that is
/// not there.
const double _cent = 0.005;

/// One plotted position: the balance standing after a movement, the movement
/// that produced it, and what the axis calls this position.
///
/// The point carries its own change and label because the tooltip answers
/// three questions at once — what happened, what it left you with, and when —
/// and a chart that only stores `List<double>` can answer one.
@immutable
class ExampleBalancePoint {
  const ExampleBalancePoint({
    required this.balance,
    required this.change,
    required this.label,
  });

  /// The balance standing at this position.
  final double balance;

  /// The movement that produced it. Zero on the opening point, whose prior
  /// movement happened before the window and is not knowable from inside it.
  final double change;

  /// Axis label: a date in the daily window, the transaction's own time label
  /// in the transaction walk.
  final String label;

  /// True on a point whose movement is unknown — the first one in the window.
  /// The tooltip says "Opening" there rather than printing a fabricated
  /// zero-value transaction.
  bool get isOpening => change.abs() < _cent;

  /// The same position, to the cent. Used to decide whether an incoming series
  /// is the old one with a point appended; exact equality would fail on the
  /// float noise of re-walking a balance from a new total.
  bool matches(ExampleBalancePoint other) =>
      label == other.label &&
      (balance - other.balance).abs() < _cent &&
      (change - other.change).abs() < _cent;

  @override
  bool operator ==(Object other) =>
      other is ExampleBalancePoint &&
      other.balance == balance &&
      other.change == change &&
      other.label == label;

  @override
  int get hashCode => Object.hash(balance, change, label);
}

/// The balance history behind Home's hero chart, with the unit it is measured
/// in. A chart without a stated unit is a shape, so the series carries its own
/// axis labels rather than letting the widget guess them.
@immutable
class ExampleBalanceSeries {
  const ExampleBalanceSeries({
    required this.points,
    required this.title,
    required this.startLabel,
    required this.endLabel,
    this.middleLabel,
    this.description,
  });

  /// Reconstructs 30 daily intervals ending at the current balance.
  /// Internal conversions are neutral. Without a valuation for every movement,
  /// the API cannot support a reconstructed history in this unit.
  factory ExampleBalanceSeries.fromActivities(
    double? total,
    List<HoppaActivity> activities, {
    String currency = 'USD',
    DateTime? asOf,
    Map<String, double> valuationRates = const {},
  }) {
    if (total == null) return empty;
    final now = (asOf ?? DateTime.now()).toLocal();
    final start = now.subtract(const Duration(days: 30));
    const dayMicros = Duration.microsecondsPerDay;
    final changes = List<double>.filled(30, 0);
    final seen = <String>{};
    for (final activity in activities) {
      if (activity.id.isNotEmpty && !seen.add(activity.id)) continue;
      final date = activity.bookedAt;
      if (date != null && (!date.isAfter(start) || date.isAfter(now))) continue;
      final change =
          activity.balanceChangeIn(currency, valuationRates: valuationRates);
      if (change == null || !change.isFinite || (date == null && change != 0)) {
        return ExampleBalanceSeries(
          points: const [],
          title: 'Last month',
          startLabel: '',
          endLabel: '',
          description: 'Balance history unavailable: some transactions have no '
              '${date == null ? 'date' : '${currency.toUpperCase()} value'}.',
        );
      }
      if (date == null) continue;
      final age = now.difference(date).inMicroseconds ~/ dayMicros;
      changes[age] += change;
    }
    var running = total;
    final backwards = <ExampleBalancePoint>[];
    for (var age = 0; age < 30; age++) {
      backwards.add(ExampleBalancePoint(
        balance: running,
        change: changes[age],
        label: age == 0 ? 'Now' : _shortDate(now.subtract(Duration(days: age))),
      ));
      running -= changes[age];
    }
    backwards.add(ExampleBalancePoint(
        balance: running, change: 0, label: _shortDate(start)));
    return ExampleBalanceSeries(
      points: backwards.reversed.toList(growable: false),
      title: 'Last month',
      startLabel: _shortDate(start),
      middleLabel: _shortDate(now.subtract(const Duration(days: 15))),
      endLabel: 'Now',
    );
  }

  static const ExampleBalanceSeries empty = ExampleBalanceSeries(
    points: [],
    title: '',
    startLabel: '',
    endLabel: '',
  );

  final List<ExampleBalancePoint> points;

  /// What the horizontal axis measures: the past month.
  final String title;
  final String startLabel;
  final String endLabel;
  final String? middleLabel;
  final String? description;

  /// A single point is a reading, not a trend: there is no line to draw and
  /// no delta to state, so Home prints its caption instead.
  bool get isEmpty => points.length < 2;

  double get first => points.first.balance;
  double get last => points.last.balance;
  double get low => points.fold(first, (v, p) => math.min(v, p.balance));
  double get high => points.fold(first, (v, p) => math.max(v, p.balance));
  double get delta => last - first;

  /// First-to-last change as a percentage of the opening balance, or null
  /// when the series did not move, opened at zero, or moved by less than a
  /// rounded tenth of a percent.
  ///
  /// Nothing here is decorative: a hard-coded percentage on a live chart is a
  /// lie, an opening balance of zero has no percentage (the division is never
  /// attempted), and a movement that rounds away to "+0.0%" prints a sign on a
  /// number that is not there, which on a balance reads as a defect.
  double? get percentChange {
    if (isEmpty) return null;
    if (first.abs() < _cent || delta.abs() < _cent) return null;
    final percent = delta / first.abs() * 100;
    return percent.abs() < .05 ? null : percent;
  }

  /// True when this series is [older] with exactly one more position on the
  /// end.
  ///
  /// A data diff, never a timer: a real provider pushing a new transaction
  /// produces exactly this shape, and nothing else in the widget may claim a
  /// point arrived. Positions match on their label and their balance to the
  /// cent, because re-walking a history from a new total does not reproduce
  /// the old doubles bit for bit.
  bool isAppendOf(ExampleBalanceSeries older) {
    if (older.points.isEmpty) return false;
    if (points.length != older.points.length + 1) return false;
    for (var index = 0; index < older.points.length; index++) {
      if (!points[index].matches(older.points[index])) return false;
    }
    return true;
  }
}

/// Home's balance trend: the one object on the screen worth looking at twice.
///
/// It is a chart because it has a zero, a scale and a time axis — a floor rule
/// at the window's low, the low and high stated in the customer's own
/// currency, and the window's real dates under it. Everything on top of that
/// is there to make the data legible, not to decorate it:
///
/// * the stroke carries a bloom that falls off outward, so the line reads as
///   lit rather than as a coloured wire;
/// * the area under it is brightest against the stroke and dies into the
///   panel at the floor, so it reads as volume rather than as a block;
/// * a slow light travels Oldest to Now, like charge moving through the line;
/// * the newest point breathes;
/// * hover and drag both scrub, with a tracking rule, a dot pinned to a real
///   sample, and a tooltip that never leaves the chart's own bounds.
///
/// ## Theme
///
/// The chart is theme-aware, unlike the card artwork beside it. Artwork is a
/// physical object and stays night in daylight; this is *data on the page*,
/// and a violet bloom tuned for a near-black ground turns to grey mud on
/// paper. Daylight scales the bloom to 45 percent — the factor
/// `ExampleShadows.glowOf` already uses to keep a glow from smudging on white —
/// and takes the deepened `ExampleColors.lightViolet` stroke, which measures
/// 4.72:1 on `lightPaper` and 5.10:1 on `lightSurface`, well clear of the 3:1
/// non-text floor a 2.4 px line has to hold.
///
/// ## Motion
///
/// The draw-on is not a second moment. It rides [arrived] — the same flag the
/// hero balance settles on — so Home still has exactly one arrival, seen on
/// two surfaces at once.
///
/// The two loops (the travelling light, the breathing halo) are the one
/// amendment to the loops-are-for-sheen law, and they carry its conditions:
/// they run only while the chart is really on screen, the route is current,
/// the app is foregrounded, motion is not reduced, and the alive layer is
/// present. Outside all five the ticker is stopped, not merely unpainted — a
/// chart animating on a background route is a battery leak.
///
/// Under reduced motion the chart is complete, illuminated and fully
/// interactive on its first frame.
class ExampleBalanceChart extends StatefulWidget {
  const ExampleBalanceChart({
    required this.series,
    required this.currency,
    this.height = 96,
    this.arrived = true,
    this.animate = true,
    super.key,
  });

  final ExampleBalanceSeries series;

  /// The unit every number on the chart is stated in.
  final String currency;

  /// Plot height. The insets that carry the floor rule and the two scale
  /// labels follow the label's own scaled height, so a taller box spends all
  /// of its extra height on the data band rather than on padding.
  final double height;

  /// True once the screen's arrival moment has been armed. Home passes the
  /// same flag its hero balance settles on, so the line draws itself while the
  /// number settles instead of competing with it.
  final bool arrived;

  /// Renders the settled chart without motion when disabled.
  final bool animate;

  /// The scrub readout, so a test can assert both what it says and that it
  /// stayed inside the chart's own bounds. Nothing in the app reads it.
  static const Key tooltipKey = Key('example-balance-chart-tooltip');

  @override
  State<ExampleBalanceChart> createState() => _ExampleBalanceChartState();
}

class _ExampleBalanceChartState extends State<ExampleBalanceChart>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The line reveals itself over this. Long enough to read as drawing, short
  /// enough that a customer who came to check a balance is not waiting on it.
  /// How long the line takes to draw itself in.
  ///
  /// Home is the most-returned-to screen in the app and this replays on every
  /// arrival, so the draw is priced as a frequent motion, not as a one-off
  /// title sequence. It used to run .8 s, which put the delta badge — the
  /// figure that says whether the balance is up or down — past 1.6 s from
  /// arrival once the illuminate was added on top. Beautiful once; a wait by
  /// the fifth visit.
  static const double _drawOnSeconds = .62;

  /// Where in the draw-on the badge lights.
  ///
  /// Not at 1. The last tenth of the draw is the line easing into its final
  /// pixels, and a badge that waits for the very end arrives after the motion
  /// has visibly stopped, which reads as a second, later event. Lighting just
  /// before the end lands the bloom inside the same gesture.
  static const double _litAt = .88;

  /// A newly appended segment, and the ripple at the point it landed on.
  static const double _segmentSeconds = .42;
  static const double _rippleSeconds = .62;

  /// One turn of the travelling light and one breath of the halo.
  static const double _loopSeconds = 3.5;

  late final Ticker _ticker = createTicker(_onTick);
  final _ChartClock _clock = _ChartClock();
  final ValueNotifier<int?> _scrub = ValueNotifier<int?>(null);

  Duration _last = Duration.zero;
  double _drawOnT = 0;
  double _segmentT = 1;
  double _rippleT = 1;
  double _loopT = 0;

  /// Flipped once, when the line lands. The badge's illumination is the only
  /// part of the moment that is a widget rather than a painted layer, so it
  /// is the only part that costs a rebuild — one, not one per frame.
  bool _lit = false;

  bool _reduced = false;
  bool _alive = false;
  bool _routeCurrent = true;
  bool _appVisible = true;
  bool _onScreen = false;
  bool _checkScheduled = false;

  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = !widget.animate || ExampleMotion.reduced(context);
    // The alive-layer gate is the house rule for a loop, not an extra one:
    // `ExampleSheenScope` is what marks a subtree as running inside the shell.
    // Mounted on its own — a widget test, a gallery card — the chart renders
    // its resting pixels and starts no ticker, exactly as every other looping
    // surface in the vocabulary behaves.
    _alive = ExampleSheenScope.existsAbove(context);
    _routeCurrent = TickerMode.valuesOf(context).enabled;
    if (_reduced) {
      // Reduced motion has no arrival and no loop: the chart is finished,
      // illuminated and scrubbable on frame one.
      _drawOnT = 1;
      _segmentT = 1;
      _rippleT = 1;
      _lit = true;
    }
    _attachScroll();
    _scheduleVisibilityCheck();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ExampleBalanceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reduced = !widget.animate || ExampleMotion.reduced(context);
    if (_reduced) {
      _drawOnT = 1;
      _segmentT = 1;
      _rippleT = 1;
      _lit = true;
    }
    if (!_reduced && widget.series.isAppendOf(oldWidget.series)) {
      // A point really arrived. Only the new segment draws, and one short
      // ripple marks where it landed.
      _segmentT = 0;
      _rippleT = 0;
    } else if (widget.series.points.length != oldWidget.series.points.length) {
      // Any other reshaping of the series — a different window, a refresh that
      // re-valued every point — is not an arrival and gets no moment.
      _segmentT = 1;
      _rippleT = 1;
    }
    if (widget.height != oldWidget.height) _scheduleVisibilityCheck();
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (visible == _appVisible) return;
    _appVisible = visible;
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_onScroll);
    _position = null;
    _ticker.dispose();
    _clock.dispose();
    _scrub.dispose();
    super.dispose();
  }

  // --- visibility ----------------------------------------------------------

  void _attachScroll() {
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) return;
    _position?.removeListener(_onScroll);
    _position = position;
    _position?.addListener(_onScroll);
  }

  void _onScroll() => _scheduleVisibilityCheck();

  /// Coalesces every visibility question raised during a frame into one
  /// geometry read after it. Scrolling asks on every scroll notification;
  /// without this the chart would walk its transform several times a frame.
  void _scheduleVisibilityCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final onScreen = _computeOnScreen();
      if (onScreen == _onScreen) return;
      _onScreen = onScreen;
      _syncTicker();
    });
  }

  bool _computeOnScreen() {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return false;
    }
    final rect = render.localToGlobal(Offset.zero) & render.size;
    if (rect.isEmpty) return false;
    final viewport = _position?.context.storageContext.findRenderObject();
    final bounds =
        viewport is RenderBox && viewport.attached && viewport.hasSize
            ? viewport.localToGlobal(Offset.zero) & viewport.size
            : Offset.zero & MediaQuery.sizeOf(context);
    return rect.overlaps(bounds);
  }

  // --- the one ticker ------------------------------------------------------

  /// One gate for every timed thing the chart does: it has to be on screen,
  /// on the current route, in a visible app, and free of reduced motion. A
  /// background route is the law's own condition — nothing runs during the
  /// route transition, and an arrival moment starts when you arrive.
  bool get _motionAllowed =>
      _onScreen && _routeCurrent && _appVisible && !_reduced;

  /// The loops' gate: the shared conditions plus the screen's alive layer.
  bool get _loopsAllowed => _motionAllowed && _alive;

  bool get _drawOnAllowed => _motionAllowed && widget.arrived;

  bool get _wantsTicker =>
      _loopsAllowed ||
      (_drawOnAllowed && _drawOnT < 1) ||
      (_motionAllowed && (_segmentT < 1 || _rippleT < 1));

  void _syncTicker() {
    final wants = _wantsTicker;
    if (wants == _ticker.isActive) {
      _publish();
      return;
    }
    if (wants) {
      _last = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
      // Whatever was mid-flight when the gate closed finishes instantly, so a
      // chart scrolled away and back is complete rather than half drawn — and
      // a line that has finished lights its badge, whichever way it finished.
      if (_drawOnT > 0) {
        _drawOnT = 1;
        _light();
      }
      _segmentT = 1;
      _rippleT = 1;
      _loopT = 0;
    }
    _publish();
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    if (dt <= 0) return;
    if (_drawOnAllowed && _drawOnT < 1) {
      _drawOnT = math.min(1, _drawOnT + dt / _drawOnSeconds);
    }
    if (_segmentT < 1) {
      _segmentT = math.min(1, _segmentT + dt / _segmentSeconds);
    }
    if (_rippleT < 1) {
      _rippleT = math.min(1, _rippleT + dt / _rippleSeconds);
    }
    if (_loopsAllowed) _loopT = (_loopT + dt / _loopSeconds) % 1;
    _publish();
    if (_drawOnT >= _litAt) _light();
    if (!_wantsTicker) _syncTicker();
  }

  /// Lights the badge, once, from wherever the line landed.
  ///
  /// The draw-on ends two ways — a tick that completes it, or a gate that
  /// closes mid-flight and snaps it home — and the badge has to follow both.
  /// It used to follow only the tick, so a chart scrolled off screen while it
  /// was still drawing came back complete with a delta pinned at zero opacity
  /// for the life of the screen: the one number on the panel that says whether
  /// the balance is up or down, invisible, with nothing on screen to explain
  /// why.
  ///
  /// The rebuild is requested only from outside a build. `_syncTicker` runs
  /// from dependency, lifecycle and visibility changes as well as from the
  /// tick, and the first of those already has a frame in flight.
  void _light() {
    if (_lit) return;
    _lit = true;
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Writes the frame into the clock the painter repaints on. One object, no
  /// allocation, one notification per tick, and no widget rebuild.
  void _publish() => _clock.write(
        drawOn: _drawOnT,
        segment: _segmentT,
        ripple: _rippleT,
        loop: _loopT,
        looping: _loopsAllowed,
      );

  // --- scrubbing -----------------------------------------------------------

  void _scrubAt(Offset local, _Plot plot) {
    final index = plot.nearestIndex(local.dx);
    if (_scrub.value != index) _scrub.value = index;
  }

  void _clearScrub() {
    if (_scrub.value != null) _scrub.value = null;
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    if (series.isEmpty) return const SizedBox.shrink();
    final palette = ExamplePalette.of(context);
    final ink = _ChartInk.of(palette);
    final labelSize = MediaQuery.textScalerOf(context).scale(
      _Plot.labelSize * context.brandDesign.typographyScale,
    );
    final percent = series.percentChange;

    return Semantics(
      label: _semanticsLabel(series, percent),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(series.title),
                  // Transaction-based labels are longer than the customer's
                  // daily-window label. Let the title wrap as text scales;
                  // the delta keeps its own readable space beside it.
                  style: ExampleTextStyles.label(context),
                ),
              ),
              if (percent != null) ...[
                const SizedBox(width: 8),
                _DeltaBadge(percent: percent, lit: _lit),
              ],
            ],
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
                final plot = _Plot.of(
                  Size(width, widget.height),
                  series.points,
                  labelSize,
                );
                return _ScrubTarget(
                  onScrub: (local) => _scrubAt(local, plot),
                  onClear: _clearScrub,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _BalanceChartPainter(
                              plot: plot,
                              clock: _clock,
                              scrub: _scrub,
                              ink: ink,
                              baseline: palette.borderSubtle,
                              // The two scale labels are the chart's units, so
                              // they take secondary rather than tertiary ink.
                              labelInk: palette.textSecondary,
                              lowLabel: _money(widget.currency, series.low),
                              highLabel: _money(widget.currency, series.high),
                              fontFamily: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.fontFamily ??
                                  ExampleFonts.sans,
                              labelSize: labelSize,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<int?>(
                            valueListenable: _scrub,
                            builder: (context, index, _) {
                              if (index == null ||
                                  index >= plot.offsets.length) {
                                return const SizedBox.shrink();
                              }
                              return CustomSingleChildLayout(
                                delegate: _TooltipLayout(plot.offsets[index]),
                                child: _ScrubTooltip(
                                  key: ExampleBalanceChart.tooltipKey,
                                  point: series.points[index],
                                  currency: widget.currency,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  series.startLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _axisStyle(palette),
                ),
              ),
              if (series.middleLabel != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    series.middleLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _axisStyle(palette),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr(series.endLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: _axisStyle(palette),
                ),
              ),
            ],
          ),
          if (series.description != null) ...[
            const SizedBox(height: 6),
            Text(series.description!, style: _axisStyle(palette)),
          ],
        ],
      ),
    );
  }

  /// The window's dates. Secondary ink, not tertiary: these are the chart's
  /// time axis, and an axis is a caption a customer has to read. Tertiary
  /// measures 4.45:1 on the Twilight hero panel, a rounding error under the
  /// 4.5:1 caption floor; secondary measures 7.07:1 there and 7.18:1 on the
  /// daylight one. The chart's three type volumes still read as three — they
  /// are separated by weight and tracking now (the title is semibold at
  /// +0.06 em) rather than by spending a contrast grade on hierarchy.
  TextStyle _axisStyle(ExamplePalette palette) => TextStyle(
        fontSize: 10.5 * context.brandDesign.typographyScale,
        color: palette.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// A screen reader gets nothing from a `CustomPaint`, so the whole chart is
  /// one label: the unit, the range in money, and the delta in words.
  String _semanticsLabel(ExampleBalanceSeries series, double? percent) {
    final currency = widget.currency;
    final movement = percent == null
        ? 'No meaningful change over the period.'
        : '${percent > 0 ? 'Up' : 'Down'} '
            '${percent.abs().toStringAsFixed(1)} percent over the period.';
    return 'Balance chart. ${series.title}. '
        'Low ${_money(currency, series.low)}, '
        'high ${_money(currency, series.high)}, '
        'now ${_money(currency, series.last)}. $movement';
  }
}

/// One frame of the chart's animation, written by the single ticker and read
/// by the painter. A `ChangeNotifier` rather than four `ValueNotifier`s so a
/// tick is one notification and one repaint, and so the painter can take it
/// directly as its `repaint` listenable — an animation frame never rebuilds a
/// widget.
class _ChartClock extends ChangeNotifier {
  double drawOn = 0;
  double segment = 1;
  double ripple = 1;
  double loop = 0;
  bool looping = false;

  void write({
    required double drawOn,
    required double segment,
    required double ripple,
    required double loop,
    required bool looping,
  }) {
    if (this.drawOn == drawOn &&
        this.segment == segment &&
        this.ripple == ripple &&
        this.loop == loop &&
        this.looping == looping) {
      return;
    }
    this.drawOn = drawOn;
    this.segment = segment;
    this.ripple = ripple;
    this.loop = loop;
    this.looping = looping;
    notifyListeners();
  }
}

/// The hues the one chart on Home is drawn in.
///
/// Twilight strokes violet on night with a bloom under it, which is what makes
/// the line read as lit rather than as a coloured wire. Daylight keeps the
/// bloom — a chart with no light on it is the flattest object on the page —
/// but scales it to [daylightGlow], the same fraction `ExampleShadows.glowOf`
/// keeps of a glow on paper, and deepens the stroke to the palette's daylight
/// fill, which holds 4.72:1 on `lightPaper` where Twilight's violet would
/// smudge.
@immutable
class _ChartInk {
  const _ChartInk({
    required this.line,
    required this.marker,
    required this.glow,
    required this.strokeWidth,
  });

  factory _ChartInk.of(ExamplePalette palette) => _ChartInk(
        line: palette.fill,
        marker: palette.accent,
        glow: palette.isLight ? daylightGlow : 1,
        // A deepened stroke on paper needs the extra fifth of a pixel to carry
        // the weight the bloom carries on night.
        strokeWidth: palette.isLight ? 2.4 : 2.2,
      );

  /// How much of the bloom survives on paper. Mirrors `ExampleShadows.glowOf`'s
  /// daylight scale, so the chart's light and the panel's light fall off
  /// together instead of disagreeing by theme.
  static const double daylightGlow = .45;

  /// Stroke and area wash of the balance trend.
  final Color line;

  /// The newest point, the scrub dot and the travelling light.
  final Color marker;

  /// Multiplier on every blurred pass.
  final double glow;

  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is _ChartInk &&
      other.line == line &&
      other.marker == marker &&
      other.glow == glow &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(line, marker, glow, strokeWidth);
}

/// The chart's geometry, resolved once per size and dataset and shared by the
/// painter and the tooltip so the two can never disagree about where a point
/// is.
class _Plot {
  _Plot._(
      this.offsets, this.top, this.bottom, this.line, this.fill, this.metric);

  factory _Plot.of(
    Size size,
    List<ExampleBalancePoint> points,
    double labelSize,
  ) {
    // The insets follow the label's own scaled height, so nothing truncates or
    // collides at a text scale of 1.3 — the band pays for the labels, not the
    // labels for the band.
    final top = math.max(15.0, labelSize + 5);
    final bottom = math.max(top + 1, size.height - top);
    final span = points.length - 1;
    var low = points.first.balance;
    var high = points.first.balance;
    for (final point in points) {
      low = math.min(low, point.balance);
      high = math.max(high, point.balance);
    }
    final range = high - low;
    // A genuinely flat window sits on the floor rather than pretending to a
    // midpoint it never occupied. The guard is also what keeps a flat series
    // from dividing by zero.
    final flat = range < 1e-6;
    final width = math.max(0.0, size.width - sideInset * 2);
    final offsets = <Offset>[
      for (var index = 0; index < points.length; index++)
        Offset(
          // A single point has no span to divide by; it stands where the axis
          // starts.
          sideInset + (span == 0 ? 0 : width * index / span),
          bottom -
              (flat ? 0 : (points[index].balance - low) / range) *
                  (bottom - top),
        ),
    ];

    final line = Path();
    Path? fill;
    ui.PathMetric? metric;
    if (offsets.length >= 2 && width > 0) {
      line.moveTo(offsets.first.dx, offsets.first.dy);
      for (var index = 1; index < offsets.length; index++) {
        final previous = offsets[index - 1];
        final current = offsets[index];
        final controlX = (previous.dx + current.dx) / 2;
        line.cubicTo(
          controlX,
          previous.dy,
          controlX,
          current.dy,
          current.dx,
          current.dy,
        );
      }
      fill = Path.from(line)
        ..lineTo(offsets.last.dx, bottom)
        ..lineTo(offsets.first.dx, bottom)
        ..close();
      // Computed once with the geometry: the travelling light asks this for a
      // position on every frame, and recomputing metrics per frame is the kind
      // of work that turns an ambience into a battery cost.
      final metrics = line.computeMetrics().iterator;
      if (metrics.moveNext()) metric = metrics.current;
    }

    return _Plot._(offsets, top, bottom, line, fill, metric);
  }

  /// Room the axis labels need, before text scaling.
  static const double labelSize = 10;

  /// Breathing room at the ends so the newest point's halo is not clipped by
  /// the box.
  static const double sideInset = 4;

  final List<Offset> offsets;
  final double top;
  final double bottom;
  final Path line;
  final Path? fill;
  final ui.PathMetric? metric;

  bool get drawable => offsets.length >= 2 && fill != null;

  double get leftX => offsets.first.dx;
  double get rightX => offsets.last.dx;

  /// The real data point nearest [x]. The scrub never lands between points: a
  /// tooltip pinned to an interpolated position would state a balance that
  /// never existed.
  int nearestIndex(double x) {
    if (offsets.length < 2) return 0;
    final span = rightX - leftX;
    if (span <= 0) return 0;
    final ratio = ((x - leftX) / span).clamp(0.0, 1.0);
    return (ratio * (offsets.length - 1)).round();
  }
}

/// Pointer and touch scrubbing over the plot.
///
/// Hover scrubs directly. Touch scrubs on tap, on a horizontal drag and on a
/// long press — never on a plain vertical drag, which belongs to the page
/// under the chart. A chart that eats the scroll gesture is a chart the
/// customer has to fight to get past.
class _ScrubTarget extends StatelessWidget {
  const _ScrubTarget({
    required this.onScrub,
    required this.onClear,
    required this.child,
  });

  final void Function(Offset local) onScrub;
  final VoidCallback onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onHover: (event) => onScrub(event.localPosition),
        onExit: (_) => onClear(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => onScrub(details.localPosition),
          onTapUp: (_) => onClear(),
          onTapCancel: onClear,
          onHorizontalDragStart: (details) => onScrub(details.localPosition),
          onHorizontalDragUpdate: (details) => onScrub(details.localPosition),
          onHorizontalDragEnd: (_) => onClear(),
          onHorizontalDragCancel: onClear,
          onLongPressStart: (details) => onScrub(details.localPosition),
          onLongPressMoveUpdate: (details) => onScrub(details.localPosition),
          onLongPressEnd: (_) => onClear(),
          onLongPressCancel: onClear,
          child: child,
        ),
      );
}

/// Keeps the tooltip inside the chart's own bounds at any width.
///
/// The child is constrained to the plot before it is measured, then centred on
/// the tracked point and clamped, so near either edge it flips from centred to
/// flush rather than hanging outside the box. It prefers to sit above the
/// point and drops below when the point is high.
class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout(this.anchor);

  final Offset anchor;

  static const double _gap = 10;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(0.0, size.width - childSize.width);
    final maxY = math.max(0.0, size.height - childSize.height);
    final x = (anchor.dx - childSize.width / 2).clamp(0.0, maxX);
    var y = anchor.dy - childSize.height - _gap;
    if (y < 0) y = anchor.dy + _gap;
    return Offset(x, y.clamp(0.0, maxY));
  }

  @override
  bool shouldRelayout(_TooltipLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// What happened, what it left you with, and when.
///
/// Opaque, on the highest surface with a hairline and the sheet shadow, so its
/// type is measured against its own ground rather than against whatever part
/// of the chart it happens to cover: primary ink reads 13.0:1 on Twilight and
/// 15.8:1 on paper, the label's secondary ink 6.76:1 and 7.05:1.
class _ScrubTooltip extends StatelessWidget {
  const _ScrubTooltip({
    required this.point,
    required this.currency,
    super.key,
  });

  final ExampleBalancePoint point;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final positive = point.change > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: ExampleShadows.sheetOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExampleAmount(
              amount: point.balance,
              currency: currency,
              size: ExampleAmountSize.inline,
              code: ExampleAmountCode.never,
              // The tooltip follows the pointer; numerals that crossfaded on
              // every sample would be a strobe, not a readout.
              animate: false,
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    point.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5 * context.brandDesign.typographyScale,
                      color: palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  point.isOpening
                      ? context.tr('Opening')
                      : '${positive ? '+' : ''}'
                          '${_money(currency, point.change)}',
                  maxLines: 1,
                  style: ExampleTextStyles.amount(
                    context,
                    size: ExampleAmountSize.inline,
                  ).copyWith(
                    fontSize: 11.5 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w600,
                    color: point.isOpening
                        ? palette.textSecondary
                        : (positive ? palette.success : palette.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The real first-to-last change, illuminated once when the line lands.
///
/// The percentage is computed from the series, never written down: a
/// hard-coded delta on a live chart is a lie. The badge lights up rather than
/// sliding or popping — the number does not move, only the light on it — and
/// the bloom returns to nothing, because a badge that stays lit is a badge
/// that has stopped meaning anything.
class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.percent, required this.lit});

  final double percent;

  /// True once the draw-on has landed.
  final bool lit;

  /// The bloom's length. Short: it is a 11 pt pill, not a headline, and it is
  /// the last beat of an arrival that has to be over before the eye moves on.
  static const Duration _illuminate = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final positive = percent > 0;
    final tone = positive ? ExampleColors.success : ExampleColors.danger;
    final glow = ExamplePalette.of(context).isLight ? _ChartInk.daylightGlow : 1;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: lit ? 1 : 0),
      duration: ExampleMotion.of(context, _illuminate),
      child: ExamplePill(
        label: '${positive ? '+' : '-'}${percent.abs().toStringAsFixed(1)}%',
        color: tone,
        fontSize: 11,
      ),
      builder: (context, t, child) {
        // Up and back down. sin() is zero at both ends, so a chart that never
        // animates — reduced motion arrives at t = 1 on its first build —
        // renders no bloom at all.
        final bloom = math.sin(math.pi * t);
        return Opacity(
          opacity: Curves.easeOut.transform(math.min(1, t * 2.5)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              boxShadow: bloom < .01
                  ? const []
                  : ExampleShadows.glow(
                      ExampleInk.accent(context, tone),
                      alpha: .34 * bloom * glow,
                      blur: 14,
                      spread: -2,
                    ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Paints the whole object against a stated floor.
///
/// Everything that moves is driven by [clock] and [scrub] through `repaint`,
/// so an animation frame repaints without rebuilding a widget or re-running
/// layout. Every `Paint`, `Path`, shader and `TextPainter` is built once and
/// reused; a frame mutates colours, stroke widths and clips only.
class _BalanceChartPainter extends CustomPainter {
  _BalanceChartPainter({
    required this.plot,
    required this.clock,
    required this.scrub,
    required this.ink,
    required this.baseline,
    required this.labelInk,
    required this.lowLabel,
    required this.highLabel,
    required this.fontFamily,
    required this.labelSize,
  }) : super(repaint: Listenable.merge([clock, scrub]));

  final _Plot plot;
  final _ChartClock clock;
  final ValueListenable<int?> scrub;
  final _ChartInk ink;
  final Color baseline;
  final Color labelInk;
  final String lowLabel;
  final String highLabel;

  /// Named explicitly. A `TextPainter` does not inherit the app theme, so a
  /// label left without a family falls to the engine default — which on web is
  /// whatever the platform happens to have, and is how a missing glyph becomes
  /// a box.
  final String fontFamily;
  final double labelSize;

  /// Fraction of a loop the travelling light spends moving. The rest of the
  /// turn is dark, which is what keeps it ambience rather than a metronome.
  static const double _travel = .46;

  // Built once per painter, mutated per frame. Nothing below is allocated in
  // paint().
  final Paint _rulePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _fillPaint = Paint();
  final Paint _washPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
  final Paint _bloomPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _softPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final Paint _solidPaint = Paint();
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;

  ui.Shader? _fillShader;
  Size? _shaderFor;
  TextPainter? _low;
  TextPainter? _high;
  double? _laidOutFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!plot.drawable) return;
    _ensureShader(size);

    // The floor. Everything above it is measured from here, which is the one
    // thing a decorative sparkline never has.
    canvas.drawLine(
      Offset(0, plot.bottom),
      Offset(size.width, plot.bottom),
      _rulePaint..color = baseline,
    );

    final drawOn = clock.drawOn.clamp(0.0, 1.0);
    final segment = clock.segment.clamp(0.0, 1.0);
    // One reveal for two jobs: the arrival draws from the left edge, an
    // appended point draws only from the point before it. Both are a clip,
    // never a re-extracted sub-path — extracting a Path per frame is exactly
    // the allocation this chart is not allowed to do.
    final double reveal;
    if (drawOn < 1) {
      reveal = ui.lerpDouble(plot.leftX, size.width, drawOn)!;
    } else if (segment < 1) {
      reveal = ui.lerpDouble(
        plot.offsets[plot.offsets.length - 2].dx,
        size.width,
        segment,
      )!;
    } else {
      reveal = size.width;
    }

    canvas.save();
    if (reveal < size.width) {
      canvas.clipRect(Rect.fromLTRB(0, 0, reveal, size.height));
    }
    _paintArea(canvas);
    _paintLine(canvas);
    _paintTravellingLight(canvas);
    _paintLatest(canvas);
    canvas.restore();

    _paintRipple(canvas);
    _paintScrub(canvas);
    _paintLabels(canvas, size);
  }

  /// The area: a cached vertical gradient dying into the panel at the floor,
  /// plus a blurred wash hugging the stroke and clipped to the area, which is
  /// what makes it brighter near the line. The wash breathes with the loop, so
  /// the gradient is animated without a shader ever being rebuilt.
  void _paintArea(Canvas canvas) {
    final fill = plot.fill!;
    canvas.drawPath(fill, _fillPaint..shader = _fillShader);
    canvas.save();
    canvas.clipPath(fill);
    final swell = clock.looping
        ? .5 + .5 * math.sin(2 * math.pi * clock.loop + math.pi / 3)
        : .5;
    canvas.drawPath(
      plot.line,
      _washPaint
        ..strokeWidth = 18 + 12 * swell
        ..color = ink.line.withValues(alpha: (.16 + .07 * swell) * ink.glow),
    );
    canvas.restore();
  }

  /// The stroke and its bloom: three blurred passes falling off outward, then
  /// the crisp line on top. Daylight keeps the same three passes at 45 percent,
  /// so the object is lit in both themes without smudging on paper.
  void _paintLine(Canvas canvas) {
    _bloomPaint
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..strokeWidth = 12
      ..color = ink.line.withValues(alpha: .16 * ink.glow);
    canvas.drawPath(plot.line, _bloomPaint);
    _bloomPaint
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
      ..strokeWidth = 7
      ..color = ink.line.withValues(alpha: .28 * ink.glow);
    canvas.drawPath(plot.line, _bloomPaint);
    _bloomPaint
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..strokeWidth = 3.4
      ..color = ink.line.withValues(alpha: .42 * ink.glow);
    canvas.drawPath(plot.line, _bloomPaint);
    canvas.drawPath(
      plot.line,
      _strokePaint
        ..strokeWidth = ink.strokeWidth
        ..color = ink.line,
    );
  }

  /// Charge moving through the line: a soft head with two dimmer trailing
  /// samples, fading in and out over its run so it never pops at the ends.
  void _paintTravellingLight(Canvas canvas) {
    if (!clock.looping) return;
    final metric = plot.metric;
    if (metric == null || metric.length <= 0) return;
    final phase = clock.loop;
    if (phase >= _travel) return;
    final t = phase / _travel;
    final head = Curves.easeInOutSine.transform(t);
    final fade = math.sin(math.pi * t);
    if (fade <= .01) return;
    for (var trail = 0; trail < 3; trail++) {
      final at = head - trail * .035;
      if (at < 0) break;
      final tangent = metric.getTangentForOffset(metric.length * at);
      if (tangent == null) continue;
      final decay = fade * (1 - trail * .32);
      canvas.drawCircle(
        tangent.position,
        7 - trail * 1.6,
        _softPaint
          ..color = ink.marker.withValues(alpha: .30 * decay * ink.glow),
      );
      if (trail == 0) {
        canvas.drawCircle(
          tangent.position,
          2.2,
          _solidPaint..color = ink.marker.withValues(alpha: .85 * decay),
        );
      }
    }
  }

  /// The newest point: a drop to the floor so the line ends on the axis rather
  /// than in mid-air, a slow breathing halo, and a solid core. The halo
  /// breathes only while the loop gate is open; at rest it is a steady halo,
  /// never a blinking cursor.
  void _paintLatest(Canvas canvas) {
    final end = plot.offsets.last;
    canvas.drawLine(
      Offset(end.dx, end.dy + 3),
      Offset(end.dx, plot.bottom),
      _rulePaint..color = ink.marker.withValues(alpha: .40),
    );
    final breathe =
        clock.looping ? .5 + .5 * math.sin(2 * math.pi * clock.loop) : 0.0;
    canvas.drawCircle(
      end,
      8 + 2.6 * breathe,
      _softPaint
        ..color =
            ink.marker.withValues(alpha: (.16 + .10 * breathe) * ink.glow),
    );
    canvas.drawCircle(end, 4, _solidPaint..color = ink.marker);
  }

  /// One short ring where a point just landed.
  void _paintRipple(Canvas canvas) {
    final t = clock.ripple;
    if (t >= 1) return;
    final eased = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    canvas.drawCircle(
      plot.offsets.last,
      5 + 17 * eased,
      _ringPaint
        ..strokeWidth = 2 * (1 - eased) + .6
        ..color = ink.marker.withValues(alpha: .45 * (1 - eased)),
    );
  }

  /// The tracking rule and the pinned dot. The dot sits on a real sample, so
  /// what the tooltip states is what the series holds.
  void _paintScrub(Canvas canvas) {
    final index = scrub.value;
    if (index == null || index < 0 || index >= plot.offsets.length) return;
    final point = plot.offsets[index];
    canvas.drawLine(
      Offset(point.dx, plot.top - 5),
      Offset(point.dx, plot.bottom),
      _rulePaint..color = ink.marker.withValues(alpha: .38),
    );
    canvas.drawCircle(
      point,
      11,
      _softPaint..color = ink.marker.withValues(alpha: .22 * ink.glow),
    );
    canvas.drawCircle(
      point,
      6.5,
      _ringPaint
        ..strokeWidth = 1.4
        ..color = ink.marker.withValues(alpha: .55),
    );
    canvas.drawCircle(point, 4, _solidPaint..color = ink.marker);
  }

  void _paintLabels(Canvas canvas, Size size) {
    final maxWidth = math.max(24.0, size.width * .62);
    _high ??= _painterFor(highLabel);
    _low ??= _painterFor(lowLabel);
    if (_laidOutFor != maxWidth) {
      _laidOutFor = maxWidth;
      _high!.layout(maxWidth: maxWidth);
      _low!.layout(maxWidth: maxWidth);
    }
    _high!.paint(canvas, Offset.zero);
    _low!.paint(canvas, Offset(0, plot.bottom + 3));
  }

  TextPainter _painterFor(String text) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: fontFamily,
            color: labelInk,
            fontSize: labelSize,
            height: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );

  void _ensureShader(Size size) {
    if (_shaderFor == size && _fillShader != null) return;
    _shaderFor = size;
    _fillShader = ui.Gradient.linear(
      Offset(0, plot.top),
      Offset(0, plot.bottom),
      [
        ink.line.withValues(alpha: .26 * (ink.glow < 1 ? .8 : 1)),
        ink.line.withValues(alpha: 0),
      ],
    );
  }

  @override
  bool shouldRepaint(covariant _BalanceChartPainter oldDelegate) =>
      oldDelegate.plot != plot ||
      oldDelegate.ink != ink ||
      oldDelegate.baseline != baseline ||
      oldDelegate.labelInk != labelInk ||
      oldDelegate.lowLabel != lowLabel ||
      oldDelegate.highLabel != highLabel ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.labelSize != labelSize;
}

/// Every number on the chart goes through `Money.formatAmount`, the single
/// path that decides decimals, grouping, symbols and Private Mode masking.
/// A movement under a cent is printed as a flat zero rather than as a
/// vanishing fraction.
String _money(String currency, double amount) =>
    Money.formatAmount(currency, amount.abs() < _cent ? 0 : amount);

const List<String> _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(DateTime date) =>
    '${date.day} ${_monthAbbreviations[date.month - 1]}';

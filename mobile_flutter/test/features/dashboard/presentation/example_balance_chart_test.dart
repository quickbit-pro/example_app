import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_sheen.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/presentation/widgets/example_balance_chart.dart';
import 'package:mobile_flutter/flavors.dart';

/// Phone and desktop, as the laws name them.
const Size _phone = Size(375, 812);
const Size _desktop = Size(1440, 900);

void main() {
  group('ExampleBalanceSeries', () {
    final now = DateTime(2026, 9, 7, 13);
    var id = 0;
    HoppaActivity ledgerActivity(Map<String, dynamic> values) {
      final ledger = LedgerTransaction.fromJson({
        'id': 'movement-${id++}',
        'type': 'transfer_in',
        'status': 'completed',
        'transactionDate': '2026-09-07T12:00:00',
        ...values,
      });
      return HoppaActivity(
        id: ledger.id,
        title: ledger.title,
        subtitle: ledger.subtitle,
        amount: ledger.displayAmount.decimalAmount,
        currency: ledger.displayAmount.currency,
        kind: HoppaActivityKind.transfer,
        timeLabel: '',
        statusLabel: ledger.status,
        transaction: ledger,
        bookedAt: ledger.hasBookedAt ? ledger.bookedAt : null,
      );
    }

    ExampleBalanceSeries month(double total, List<HoppaActivity> rows,
            {Map<String, double> rates = const {}}) =>
        ExampleBalanceSeries.fromActivities(total, rows,
            asOf: now, valuationRates: rates);

    test('month includes more than eight movements and buckets by day', () {
      final rows = [
        for (var i = 0; i < 25; i++)
          _activity(
              id: '$i',
              amount: -1,
              bookedAt: now.subtract(Duration(days: i, minutes: 1))),
        _activity(
            id: 'old',
            amount: 5000,
            bookedAt: now.subtract(const Duration(days: 31))),
        _activity(
            id: 'boundary',
            amount: 5000,
            bookedAt: now.subtract(const Duration(days: 30))),
        _activity(
            id: 'future',
            amount: 5000,
            bookedAt: now.add(const Duration(minutes: 1))),
      ];
      final series = month(100, rows.reversed.toList());
      expect(series.points, hasLength(31));
      expect(series.first, 125);
      expect(series.last, 100);
      expect(series.delta, -25);
      expect(series.startLabel, '8 Aug');
      expect(series.middleLabel, '23 Aug');
      expect(series.endLabel, 'Now');
      expect(series.title, 'Last month');
      expect(series.description, isNull);
      expect(series.points.last.change, -1);
    });

    test(
        'daily aggregation keeps deposits and carries balances through quiet days',
        () {
      final deposit = _activity(
          id: 'deposit',
          amount: 20,
          bookedAt: now.subtract(const Duration(days: 2, hours: 1)));
      final series = month(100, [
        deposit,
        deposit,
        _activity(id: 'payment', amount: -5, bookedAt: deposit.bookedAt),
      ]);
      expect(series.delta, 15);
      expect(series.first, 85);
      expect(series.points.where((p) => p.change != 0).single.change, 15);
      expect(series.points.skip(28).map((p) => p.balance), everyElement(100));
    });

    test(
        'Hoppa Equals conversions stay neutral while external deposits and fees count',
        () {
      final series = month(129.63, [
        ledgerActivity(
            {'type': 'fx_trade', 'currency': 'AED', 'amount': 42.15}),
        ledgerActivity({
          'type': 'deposit',
          'currency': 'AED',
          'amount': 42.15,
          'metadata': {'provider': 'equalsmoney', 'source': 'exchange'}
        }),
        ledgerActivity({
          'type': 'withdrawal',
          'currency': 'EUR',
          'amount': 10,
          'metadata': {'provider': 'equalsmoney', 'source': 'exchange'}
        }),
        ledgerActivity(
            {'type': 'exchange', 'currency': 'AED', 'amount': 42.15}),
        ledgerActivity({
          'type': 'deposit',
          'currency': 'EUR',
          'amount': 2,
          'metadata': {'provider': 'equalsmoney', 'source': 'external_credit'}
        }),
        ledgerActivity(
            {'type': 'exchange_fee', 'currency': 'USD', 'amount': -0.20}),
      ], rates: {
        'EUR': 1.16
      });
      expect(series.delta, closeTo(2.12, .0001));
      expect(series.description, isNull);
    });

    test(
        'Rok USDC withdrawals stay in the month and use the agreed USD estimate',
        () {
      final series = month(.10, [
        ledgerActivity({
          'type': 'crypto_withdrawal',
          'currency': 'USDC',
          'amount': 603,
          'transactionDate': '2026-08-28T12:45:32',
          'status': 'complete'
        }),
        ledgerActivity({
          'type': 'crypto_withdrawal',
          'currency': 'USDC',
          'amount': 2770,
          'transactionDate': '2026-08-19T13:09:55',
          'status': 'closed'
        }),
        ledgerActivity({
          'type': 'quantum_to_crypto_exchange',
          'currency': 'USD',
          'amount': 603
        }),
        ledgerActivity(
            {'type': 'transfer_to_master', 'currency': 'USD', 'amount': .03}),
      ]);
      expect(series.isEmpty, isFalse);
      expect(series.delta, closeTo(-3373.03, .0001));
      expect(series.description, isNull);
    });

    test('actual settlements win and failed movements do not affect the month',
        () {
      final series = month(90, [
        ledgerActivity({
          'type': 'card_payment',
          'currency': 'USD',
          'amount': -10,
          'transactionCurrency': 'AED',
          'transactionAmount': -36.73
        }),
        for (final status in ['failed', 'fail', 'created'])
          ledgerActivity({
            'type': 'crypto_withdrawal',
            'currency': 'USDT',
            'amount': 100,
            'status': status
          }),
      ]);
      expect(series.delta, -10);
    });

    test('unknown dates or valuations do not manufacture monthly balances', () {
      expect(
          month(100, [
            ledgerActivity({'currency': 'EUR', 'amount': 2})
          ]).isEmpty,
          isTrue);
      expect(month(100, [_activity(id: 'no-date', amount: 2)]).isEmpty, isTrue);
      final old = ledgerActivity({
        'currency': 'EUR',
        'amount': 2,
        'transactionDate': '2026-01-01T12:00:00'
      });
      expect(month(100, [old]).isEmpty, isFalse);
    });

    test('a quiet month shows a flat line through Now without a caption', () {
      final series = month(100, []);
      expect(series.points, hasLength(31));
      expect(series.points.map((p) => p.balance), everyElement(100));
      expect(series.percentChange, isNull);
      expect(series.description, isNull);
      expect(
          ExampleBalanceSeries.fromActivities(null, const []).isEmpty, isTrue);
    });

    test('percentChange is the real change, or nothing at all', () {
      expect(_series([100, 110]).percentChange, closeTo(10, 0.0001));
      expect(_series([110, 100]).percentChange, closeTo(-9.0909, 0.0001));
      // Flat: no division, no "+0.0%".
      expect(_series([100, 100]).percentChange, isNull);
      // An opening balance of zero has no percentage.
      expect(_series([0, 50]).percentChange, isNull);
      // Below a rounded tenth of a percent the chart says nothing.
      expect(_series([100000, 100000.02]).percentChange, isNull);
      // Negative balances still produce a signed percentage of the opening
      // magnitude, and a rise out of debt reads as a rise.
      expect(_series([-200, -100]).percentChange, closeTo(50, 0.0001));
      expect(_series([-100, -200]).percentChange, closeTo(-100, 0.0001));
    });

    test('isAppendOf recognises one new point and nothing else', () {
      final before = _series([100, 110, 120]);
      expect(_series([100, 110, 120, 130]).isAppendOf(before), isTrue);
      // Float noise from re-walking a balance is not a different series.
      expect(
        _series([100.0001, 110.0001, 120.0001, 130]).isAppendOf(before),
        isTrue,
      );
      expect(_series([100, 110, 120]).isAppendOf(before), isFalse);
      expect(_series([100, 110, 999, 130]).isAppendOf(before), isFalse);
      expect(_series([100, 110, 120, 130, 140]).isAppendOf(before), isFalse);
      expect(before.isAppendOf(ExampleBalanceSeries.empty), isFalse);
    });
  });

  group('ExampleBalanceChart renders', () {
    for (final size in <Size>[_phone, _desktop]) {
      for (final brightness in Brightness.values) {
        final label = '${size.width.toInt()} ${brightness.name}';
        testWidgets('$label: the chart, its units and its real delta',
            (tester) async {
          await _surface(tester, size);
          await tester.pumpWidget(
            _host(
              series: _dated(),
              brightness: brightness,
              width: size.width,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(ExampleBalanceChart), findsOneWidget);
          expect(find.text('Last month'), findsOneWidget);
          expect(find.text('Now'), findsOneWidget);
          expect(find.text('1 Jan'), findsOneWidget);
          // The delta is computed, never written down: 1000 from 920.
          expect(find.text('+8.7%'), findsOneWidget);
          expect(tester.takeException(), isNull);
          _expectNoTruncation(tester);
        });
      }
    }

    testWidgets('a falling series signs its badge the other way',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _series([110, 100])));
      await tester.pumpAndSettle();
      expect(find.text('-9.1%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flat series prints no badge at all', (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _series([100, 100, 100])));
      await tester.pumpAndSettle();
      expect(find.byType(ExamplePill), findsNothing);
      expect(find.byType(ExampleBalanceChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single point is a reading, not a trend, and renders nothing',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _series([100])));
      await tester.pumpAndSettle();
      // Stretched by the column, but zero tall: nothing is drawn.
      expect(tester.getSize(find.byType(ExampleBalanceChart)).height, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('negative balances plot without crashing', (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _series([-500, -320, -80, 45])));
      await tester.pumpAndSettle();
      expect(find.byType(ExampleBalanceChart), findsOneWidget);
      // The scale labels are painted onto the canvas, so the screen-reader
      // label is where the numbers can be read back: low -500, high 45, and
      // a rise out of debt reported as a rise.
      final handle = tester.ensureSemantics();
      final label = tester.getSemantics(find.byType(ExampleBalanceChart)).label;
      expect(label, contains('500'));
      expect(label, contains('Up 109.0 percent'));
      handle.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chart under 200 px wide still renders', (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _dated(), width: 160));
      await tester.pumpAndSettle();
      expect(find.byType(ExampleBalanceChart), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      // No RenderFlex overflow: the header gives by ellipsis, not by
      // painting outside its box. 160 px is below every supported viewport,
      // so the no-truncation floor is asserted at 375 and 1440, not here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing truncates at a text scale of 1.3 on a 375 phone',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _dated(), textScale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectNoTruncation(tester);
    });
  });

  group('ExampleBalanceChart motion', () {
    testWidgets('no alive layer, no loop: the ticker never starts',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _dated()));
      // pumpAndSettle would time out against a loop; that it returns is the
      // assertion. The count proves nothing is left ticking.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion arrives complete, lit and scrubbable',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(
        _host(series: _dated(), alive: true, reduced: true),
      );
      await tester.pump();

      // No ticker on the first frame and none after it.
      expect(tester.binding.transientCallbackCount, 0);
      // The badge is fully present on frame one rather than fading in.
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(ExamplePill),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1.0);
      expect(tester.binding.transientCallbackCount, 0);

      // Scrubbing still works with motion off.
      await _hoverAt(tester, await _mouse(tester), 0.5);
      expect(find.byKey(ExampleBalanceChart.tooltipKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('animate false keeps the chart settled inside the alive layer',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(
        _host(series: _dated(), alive: true, animate: false),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.text('+8.7%'), findsOneWidget);
      await _hoverAt(tester, await _mouse(tester), 0.5);
      expect(find.byKey(ExampleBalanceChart.tooltipKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the loop runs under the alive layer and stops off route',
        (tester) async {
      await _surface(tester, _phone);

      // The alive layer on its own, so the chart's own ticker is what the
      // later counts measure.
      await tester.pumpWidget(_host(series: null, alive: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final baseline = tester.binding.transientCallbackCount;

      await tester.pumpWidget(_host(series: _dated(), alive: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.binding.transientCallbackCount,
        greaterThan(baseline),
        reason: 'the chart should be ticking while it is visible and current',
      );

      // Route no longer current: the ticker is stopped, not merely unpainted.
      await tester.pumpWidget(
        _host(series: _dated(), alive: true, routeCurrent: false),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.binding.transientCallbackCount,
        baseline,
        reason: 'a chart on a background route must stop its ticker',
      );
    });

    testWidgets('appending a point is a data diff and settles', (tester) async {
      await _surface(tester, _phone);
      final before = _series([100, 110, 120]);
      await tester.pumpWidget(_host(series: before));
      await tester.pumpAndSettle();
      expect(find.text('+20.0%'), findsOneWidget);

      await tester.pumpWidget(_host(series: _series([100, 110, 120, 150])));
      await tester.pumpAndSettle();
      expect(find.text('+50.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('ExampleBalanceChart scrubbing', () {
    testWidgets('the tooltip states the movement, the balance and the date',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(
        _host(
          series: ExampleBalanceSeries.fromActivities(
            100,
            [
              _activity(
                  id: 'a', amount: -10, bookedAt: DateTime(2026, 1, 31, 12)),
              _activity(
                  id: 'b', amount: 25, bookedAt: DateTime(2026, 1, 30, 12)),
            ],
            asOf: DateTime(2026, 1, 31, 13),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The newest point, at the right-hand end.
      final mouse = await _mouse(tester);
      await _hoverAt(tester, mouse, 0.99);
      final tooltip = find.byKey(ExampleBalanceChart.tooltipKey);
      expect(tooltip, findsOneWidget);
      expect(
        find.descendant(of: tooltip, matching: find.text('Now')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tooltip, matching: find.text('-\$10.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tooltip, matching: find.text(r'$100.00')),
        findsOneWidget,
      );

      // The opening point has no known movement and does not invent one.
      await _hoverAt(tester, mouse, 0.01);
      expect(
        find.descendant(of: tooltip, matching: find.text('Opening')),
        findsAtLeastNWidgets(1),
      );
      expect(tester.takeException(), isNull);
    });

    for (final at in <double>[0.01, 0.5, 0.99]) {
      testWidgets('the tooltip stays inside the chart at 375, x=$at',
          (tester) async {
        await _surface(tester, _phone);
        await tester.pumpWidget(_host(series: _dated()));
        await tester.pumpAndSettle();
        await _hoverAt(tester, await _mouse(tester), at);

        final plot = _plotRect(tester);
        final tooltip = tester.getRect(
          find.byKey(ExampleBalanceChart.tooltipKey),
        );
        expect(tooltip.left, greaterThanOrEqualTo(plot.left - 0.01));
        expect(tooltip.right, lessThanOrEqualTo(plot.right + 0.01));
        expect(tooltip.top, greaterThanOrEqualTo(plot.top - 0.01));
        expect(tooltip.bottom, lessThanOrEqualTo(plot.bottom + 0.01));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the readout clears when the pointer leaves', (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _dated()));
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final plot = _plotRect(tester);
      await gesture.moveTo(plot.center);
      await tester.pump();
      expect(find.byKey(ExampleBalanceChart.tooltipKey), findsOneWidget);

      await gesture.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(find.byKey(ExampleBalanceChart.tooltipKey), findsNothing);
    });

    testWidgets('a horizontal drag scrubs and a vertical one is left alone',
        (tester) async {
      await _surface(tester, _phone);
      await tester.pumpWidget(_host(series: _dated()));
      await tester.pumpAndSettle();
      final plot = _plotRect(tester);

      final drag =
          await tester.startGesture(plot.centerLeft + const Offset(8, 0));
      await drag.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(ExampleBalanceChart.tooltipKey), findsOneWidget);
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byKey(ExampleBalanceChart.tooltipKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

// --- harness ----------------------------------------------------------------

Future<void> _surface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// The chart on a Example theme, with only the gates a test needs to move.
///
/// A null [series] mounts the surroundings without the chart, which is how the
/// ticker tests get a baseline for whatever else on the page is animating.
/// Built once. A fresh `ThemeData` per pump makes `MaterialApp`'s
/// `AnimatedTheme` animate, which would show up in the ticker counts below as
/// motion the chart never asked for.
final _themes = buildAppThemes(_branding);

Widget _host({
  required ExampleBalanceSeries? series,
  Brightness brightness = Brightness.dark,
  double width = 335,
  double textScale = 1,
  bool reduced = false,
  bool alive = false,
  bool routeCurrent = true,
  bool animate = true,
}) {
  final theme = brightness == Brightness.dark ? _themes.dark : _themes.light;
  Widget chart = series == null
      ? const SizedBox(height: 96)
      : ExampleBalanceChart(series: series, currency: 'USD', animate: animate);
  if (!routeCurrent) chart = TickerMode(enabled: false, child: chart);
  if (alive) chart = ExampleSheenScope(child: chart);
  return MaterialApp(
    theme: theme,
    darkTheme: theme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: chart)),
        ),
      ),
    ),
  );
}

/// The chart's own paint box, never whatever `CustomPaint` the app chrome
/// happens to put first in the tree.
Rect _plotRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(ExampleBalanceChart),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

/// Hovers a fraction of the way across the plot with a real mouse pointer.
/// One mouse per test, added once and removed at the end. Adding a second
/// pointer for the same device before the first is removed trips an assert
/// inside `MouseTracker`, so a test that hovers twice reuses this.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

Future<void> _hoverAt(
  WidgetTester tester,
  TestGesture mouse,
  double fraction,
) async {
  final plot = _plotRect(tester);
  await mouse.moveTo(
    Offset(plot.left + plot.width * fraction, plot.center.dy),
  );
  await tester.pump();
}

/// Every laid-out paragraph fits the box it was given. An ellipsis on a
/// balance, a date or a unit is a wrong answer, not a tidy one.
void _expectNoTruncation(WidgetTester tester) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'truncated: ${paragraph.text.toPlainText()}',
    );
  }
}

ExampleBalanceSeries _series(List<double> values) => ExampleBalanceSeries(
      points: [
        for (var index = 0; index < values.length; index++)
          ExampleBalancePoint(
            balance: values[index],
            change: index == 0 ? 0 : values[index] - values[index - 1],
            label: index == 0 ? 'Opening' : 'Point $index',
          ),
      ],
      title: 'Last ${values.length} transactions',
      startLabel: 'Oldest',
      endLabel: 'Now',
    );

/// The current 1000 balance, walked backwards through two dated activities.
ExampleBalanceSeries _dated() => ExampleBalanceSeries.fromActivities(
      1000,
      [
        _activity(id: 'a', amount: -40, bookedAt: DateTime(2026, 1, 30)),
        _activity(id: 'b', amount: 120, bookedAt: DateTime(2026, 1, 20)),
      ],
      asOf: DateTime(2026, 1, 31),
    );

HoppaActivity _activity({
  required String id,
  required double amount,
  String timeLabel = '',
  DateTime? bookedAt,
}) =>
    HoppaActivity(
      id: id,
      title: 'Movement $id',
      subtitle: 'Test',
      amount: amount,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: timeLabel,
      statusLabel: 'Completed',
      bookedAt: bookedAt,
    );

const _branding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

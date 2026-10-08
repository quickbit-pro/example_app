// Tests for the Example alive layer: ExampleSheenScope, ExampleSheen and the
// band painter.
//
// Everything renders at the 375 x 812 design viewport with a device pixel
// ratio of 1. flutter_test does not load pubspec fonts, so these tests assert
// registration, scheduling, tokens and structure, never pixels.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/brands/example/example_sheen.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';

// The sheen reads exactly one thing from the theme, `brightness`, so these
// tests build the two brightnesses directly instead of pulling in the whole
// brand theme.
final ThemeData _dark = ThemeData(brightness: Brightness.dark);
final ThemeData _light = ThemeData(brightness: Brightness.light);

/// The controller of the most recently built scope, captured through
/// [ExampleSheenScope.maybeOf] from inside the scope.
ExampleSheenController? _captured;

/// Pumps [child] inside a Example theme at 375 x 812.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? _dark : _light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

/// A scope that publishes its controller into [_captured].
Widget _scope({
  required Widget child,
  Duration cadence = const Duration(seconds: 7),
  bool enabled = true,
}) =>
    ExampleSheenScope(
      cadence: cadence,
      enabled: enabled,
      child: Builder(
        builder: (context) {
          _captured = ExampleSheenScope.maybeOf(context);
          return child;
        },
      ),
    );

Widget _host({
  BorderRadius? borderRadius,
  ExampleSheenIntensity intensity = ExampleSheenIntensity.normal,
  bool sweepOnArrival = true,
  bool idle = true,
}) =>
    ExampleSheen(
      borderRadius: borderRadius,
      intensity: intensity,
      sweepOnArrival: sweepOnArrival,
      idle: idle,
      child: const SizedBox(width: 200, height: 48),
    );

Finder _sheenPaint() => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ExampleSheenPainter,
    );

ExampleSheenPainter _painterOf(WidgetTester tester) =>
    tester.widget<CustomPaint>(_sheenPaint().first).painter!
        as ExampleSheenPainter;

/// Rasterises the painter on its own and returns the alpha of every pixel on
/// the middle row, so the band's shape can be checked without a golden.
Future<List<int>> _bandRow({
  double? progress,
  double angleDegrees = 20,
  int width = 200,
  int height = 40,
}) async {
  final clock = progress == null ? null : ValueNotifier<double>(progress);
  addTearDown(() => clock?.dispose());
  final recorder = ui.PictureRecorder();
  ExampleSheenPainter(
    progress: clock,
    peak: ExampleColors.pearl.withValues(alpha: .14),
    angleDegrees: angleDegrees,
  ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(width, height);
  addTearDown(image.dispose);
  final bytes = (await image.toByteData())!;
  final row = height ~/ 2;
  return [
    for (var x = 0; x < width; x++) bytes.getUint8((row * width + x) * 4 + 3),
  ];
}

/// Unmounts the tree so no scope timer outlives the test.
Future<void> _teardown(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  setUp(() => _captured = null);

  group('ExampleSheenScope registration', () {
    testWidgets('a host registers on mount and unregisters on dispose',
        (tester) async {
      await _pump(
        tester,
        _scope(
          child: Center(child: _host()),
        ),
      );
      final controller = _captured!;
      expect(controller.hosts, hasLength(1));

      await _pump(tester, _scope(child: const SizedBox.shrink()));
      expect(controller.hosts, isEmpty);

      await _teardown(tester);
    });

    testWidgets('two hosts get different golden-ratio phases', (tester) async {
      await _pump(
        tester,
        _scope(
          child: Column(
            children: [_host(), _host()],
          ),
        ),
      );
      final hosts = _captured!.hosts;
      expect(hosts, hasLength(2));
      expect(hosts[0].phase, 0);
      expect(hosts[1].phase, closeTo(0.6180339887498949, 1e-12));
      expect(hosts[0].phase, isNot(hosts[1].phase));

      // Different phases also give different sweep lengths, all inside the
      // 1.2 to 1.6 s law.
      for (final host in hosts) {
        expect(host.sweepDuration.inMilliseconds, inInclusiveRange(1200, 1600));
      }
      expect(hosts[0].sweepDuration, isNot(hosts[1].sweepDuration));

      // First idle sweeps are staggered by phase, so they never coincide.
      expect(hosts[0].firstIdleDelay, isNot(hosts[1].firstIdleDelay));

      await _teardown(tester);
    });

    testWidgets('the scope is idle until a sweep is due', (tester) async {
      await _pump(tester, _scope(child: Center(child: _host())));
      expect(_captured!.isRunning, isTrue);
      expect(_captured!.isTicking, isFalse);
      await _teardown(tester);
    });
  });

  group('reduced motion', () {
    testWidgets('registers no host and starts no ticker', (tester) async {
      await _pump(
        tester,
        _scope(child: Center(child: _host())),
        reduceMotion: true,
      );
      // The guarantee is harder than "no host attaches": a reduced-motion
      // scope publishes no controller at all, so nothing downstream can even
      // ask for a sweep. `maybeOf` returning null IS the kill switch — which
      // is also why a widget deciding whether to ADD a scope must ask
      // `existsAbove`, or it would nest an enabled scope under this one and
      // reopen everything this test closes.
      expect(_captured, isNull);

      // Well past arrival and the first idle sweep.
      await tester.pump(const Duration(seconds: 20));
      expect(tester.takeException(), isNull);

      await _teardown(tester);
    });

    testWidgets('paints a static soft highlight 30 percent across',
        (tester) async {
      await _pump(
        tester,
        _scope(child: Center(child: _host())),
        reduceMotion: true,
      );
      final painter = _painterOf(tester);
      expect(painter.isStatic, isTrue);
      expect(painter.progress, isNull);
      expect(painter.centerFactor, closeTo(.30, 1e-9));
      expect(
        painter.peak,
        ExampleColors.pearl.withValues(alpha: .07),
        reason: 'the static highlight uses the soft peak, half of .14',
      );
      await _teardown(tester);
    });

    testWidgets('a host with no scope above it is static too', (tester) async {
      await _pump(tester, Center(child: _host()));
      expect(_painterOf(tester).isStatic, isTrue);
      await _teardown(tester);
    });

    testWidgets('a disabled scope is static too', (tester) async {
      await _pump(
        tester,
        _scope(enabled: false, child: Center(child: _host())),
      );
      expect(_captured, isNull);
      expect(_painterOf(tester).isStatic, isTrue);
      await _teardown(tester);
    });
  });

  group('sweeps', () {
    testWidgets('arrival runs 250 ms after mount, then the ticker stops',
        (tester) async {
      await _pump(tester, _scope(child: Center(child: _host())));
      final controller = _captured!;
      final host = controller.hosts.single;
      expect(host.isSweeping, isFalse);

      await tester.pump(const Duration(milliseconds: 240));
      expect(host.isSweeping, isFalse, reason: 'nothing before 250 ms');
      expect(controller.isTicking, isFalse);

      await tester.pump(const Duration(milliseconds: 20));
      expect(host.isSweeping, isTrue);
      expect(controller.isTicking, isTrue);

      await tester.pump(const Duration(milliseconds: 600));
      expect(host.value, greaterThan(0));
      expect(host.value, lessThan(1));
      expect(_painterOf(tester).value, host.value);

      await tester.pump(host.sweepDuration);
      expect(host.isSweeping, isFalse);
      expect(host.value, 0);
      expect(controller.isTicking, isFalse, reason: 'no ticker between sweeps');

      await _teardown(tester);
    });

    testWidgets('idle sweeps again after the cadence', (tester) async {
      await _pump(
        tester,
        _scope(
          cadence: const Duration(seconds: 3),
          child: Center(child: _host()),
        ),
      );
      final controller = _captured!;
      final host = controller.hosts.single;

      await tester.pump(const Duration(milliseconds: 300));
      expect(host.isSweeping, isTrue);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(host.isSweeping, isFalse);

      await tester.pump(const Duration(milliseconds: 1500));
      expect(host.isSweeping, isTrue, reason: 'idle sweep at the cadence');

      await _teardown(tester);
    });

    testWidgets('idle: false arrives once and never sweeps again',
        (tester) async {
      await _pump(
        tester,
        _scope(
          cadence: const Duration(seconds: 3),
          child: Center(child: _host(idle: false)),
        ),
      );
      final host = _captured!.hosts.single;

      await tester.pump(const Duration(milliseconds: 300));
      expect(host.isSweeping, isTrue);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(host.isSweeping, isFalse);

      await tester.pump(const Duration(seconds: 10));
      expect(host.isSweeping, isFalse);
      expect(_captured!.isTicking, isFalse);

      await _teardown(tester);
    });

    testWidgets('sweepOnArrival: false and idle: false never registers',
        (tester) async {
      await _pump(
        tester,
        _scope(child: Center(child: _host(sweepOnArrival: false, idle: false))),
      );
      expect(_captured!.hosts, isEmpty);
      expect(_painterOf(tester).isStatic, isTrue);
      await _teardown(tester);
    });

    testWidgets('nothing runs during the route transition', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _dark,
          navigatorKey: navigator,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      navigator.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: ExampleMotion.route,
          reverseTransitionDuration: ExampleMotion.route,
          pageBuilder: (context, animation, secondary) => Scaffold(
            body: _scope(child: Center(child: _host())),
          ),
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      await tester.pump();
      // 300 ms into the 420 ms handoff: past the arrival delay, but the route
      // is still travelling, so nothing may have started.
      await tester.pump(const Duration(milliseconds: 300));
      final host = _captured!.hosts.single;
      expect(host.isSweeping, isFalse);
      expect(_captured!.isTicking, isFalse);

      // Route settles, then the 250 ms arrival delay runs from there.
      await tester.pump(const Duration(milliseconds: 200));
      expect(host.isSweeping, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.isSweeping, isTrue);

      await _teardown(tester);
    });

    testWidgets('a covered route pauses the scope', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _dark,
          navigatorKey: navigator,
          home: Scaffold(
            body: _scope(
              cadence: const Duration(seconds: 3),
              child: Center(child: _host()),
            ),
          ),
        ),
      );
      final controller = _captured!;
      expect(controller.isRunning, isTrue);

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isRunning, isFalse);
      expect(controller.isTicking, isFalse);

      await tester.pump(const Duration(seconds: 10));
      expect(controller.isTicking, isFalse, reason: 'covered pages stay still');
      expect(controller.hosts.single.isSweeping, isFalse);

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isRunning, isTrue);

      await _teardown(tester);
    });

    testWidgets('an unresumed app pauses the scope', (tester) async {
      await _pump(
        tester,
        _scope(
          cadence: const Duration(seconds: 3),
          child: Center(child: _host()),
        ),
      );
      final controller = _captured!;
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isTicking, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(controller.isRunning, isFalse);
      expect(controller.isTicking, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(controller.isTicking, isFalse, reason: 'a hidden app is still');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.isRunning, isTrue);

      await _teardown(tester);
    });

    testWidgets('TickerMode off pauses the scope', (tester) async {
      Widget tree({required bool ticking}) => TickerMode(
            enabled: ticking,
            child: _scope(
              cadence: const Duration(seconds: 3),
              child: Center(child: _host()),
            ),
          );

      await _pump(tester, tree(ticking: true));
      final controller = _captured!;
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isTicking, isTrue);

      await _pump(tester, tree(ticking: false));
      expect(controller.isRunning, isFalse);
      expect(controller.isTicking, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(controller.isTicking, isFalse);

      await _teardown(tester);
    });
  });

  group('band', () {
    testWidgets('peak is pearl .14 on dark', (tester) async {
      await _pump(tester, _scope(child: Center(child: _host())));
      expect(
        _painterOf(tester).peak,
        ExampleColors.pearl.withValues(alpha: .14),
      );
      await _teardown(tester);
    });

    testWidgets('peak is lightIris .20 on light', (tester) async {
      // Not white. A white band on paper is mathematically inert — white over
      // #FFFFFF is 1.00:1 and over the skeleton base 1.07:1 — so every light
      // host but a saturated fill got no band at all. Daylight therefore
      // tints: lightIris at .20 lifts a pale surface the way a specular sweep
      // actually reads on matte material.
      await _pump(
        tester,
        _scope(child: Center(child: _host())),
        brightness: Brightness.light,
      );
      expect(
        _painterOf(tester).peak,
        ExampleColors.lightIris.withValues(alpha: .20),
      );
      await _teardown(tester);
    });

    testWidgets('onFill is white .09 on light and pearl .05 on dark',
        (tester) async {
      // The contrast ceiling, not the loudness, sets this budget: the band
      // paints above the child, so on a filled button it composites over the
      // label too. .09 is the largest white alpha over lightViolet that still
      // leaves a white label at 4.5:1; .05 is the dark equivalent over an
      // already tight 3.95:1.
      await _pump(
        tester,
        _scope(
          child: Center(child: _host(intensity: ExampleSheenIntensity.onFill)),
        ),
        brightness: Brightness.light,
      );
      expect(
        _painterOf(tester).peak,
        const Color(0xFFFFFFFF).withValues(alpha: .09),
      );
      await _teardown(tester);

      await _pump(
        tester,
        _scope(
          child: Center(child: _host(intensity: ExampleSheenIntensity.onFill)),
        ),
      );
      expect(
        _painterOf(tester).peak,
        ExampleColors.pearl.withValues(alpha: .05),
      );
      await _teardown(tester);
    });

    testWidgets('soft halves the peak', (tester) async {
      await _pump(
        tester,
        _scope(
          child: Center(child: _host(intensity: ExampleSheenIntensity.soft)),
        ),
      );
      expect(
        _painterOf(tester).peak,
        ExampleColors.pearl.withValues(alpha: .07),
      );
      await _teardown(tester);
    });

    testWidgets('the band is off-canvas at both ends of the travel',
        (tester) async {
      await _pump(tester, _scope(child: Center(child: _host())));
      final host = _captured!.hosts.single;
      final painter = _painterOf(tester);
      expect(painter.value, 0);
      expect(painter.centerFactor, closeTo(-.7, 1e-9));
      expect(host.value, 0);
      await _teardown(tester);
    });

    testWidgets('the overlay is clipped, ignores pointers and is boundaried',
        (tester) async {
      await _pump(
        tester,
        _scope(
          child: Center(
            child: _host(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
      final overlay = find.ancestor(
        of: _sheenPaint(),
        matching: find.byType(IgnorePointer),
      );
      expect(overlay, findsWidgets);
      expect(
        tester.widget<IgnorePointer>(overlay.first).ignoring,
        isTrue,
        reason: 'the band never takes a tap meant for the host',
      );
      expect(
        find.ancestor(
            of: _sheenPaint(), matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(of: _sheenPaint(), matching: find.byType(ClipRRect))
            .first,
      );
      expect(clip.borderRadius, BorderRadius.circular(20));
      expect(
        tester.getSize(_sheenPaint().first),
        const Size(200, 48),
        reason: 'the band fills the host, and the host keeps its own size',
      );
      await _teardown(tester);
    });
  });

  group('band geometry', () {
    test('the static band peaks 30 percent across the host', () async {
      final row = await _bandRow();
      var peakX = 0;
      for (var x = 1; x < row.length; x++) {
        if (row[x] > row[peakX]) peakX = x;
      }
      expect(peakX / row.length, closeTo(.30, .04));
      expect(row[peakX], greaterThan(24), reason: 'pearl .14 is about 36/255');
      expect(row[peakX], lessThan(48));
      expect(row.first, 0, reason: 'the band fades out well before the edge');
      expect(row.last, 0);
    });

    test('the band is about 35 percent of the host wide', () async {
      final row = await _bandRow();
      final lit = row.where((alpha) => alpha > 0).length;
      // The band is 35 percent wide measured along its own axis; the 20 degree
      // tilt widens its footprint on a horizontal slice.
      expect(lit / row.length, closeTo(.35, .08));
    });

    test('nothing is painted at either end of the travel', () async {
      expect(await _bandRow(progress: 0), everyElement(0));
      expect(await _bandRow(progress: 1), everyElement(0));
    });

    test('the band travels left to right', () async {
      int peakOf(List<int> row) {
        var peak = 0;
        for (var x = 1; x < row.length; x++) {
          if (row[x] > row[peak]) peak = x;
        }
        return peak;
      }

      final early = peakOf(await _bandRow(progress: .35));
      final late = peakOf(await _bandRow(progress: .65));
      expect(early, lessThan(late));
    });
  });

  group('ExampleSheen.text', () {
    testWidgets('masks the band onto the glyphs with srcATop', (tester) async {
      await _pump(
        tester,
        _scope(
          child: const Center(
            child: ExampleSheen.text(child: Text('Welcome back')),
          ),
        ),
      );
      final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(mask.blendMode, BlendMode.srcATop);
      expect(_sheenPaint(), findsNothing, reason: 'no overlay band for text');
      expect(_captured!.hosts, hasLength(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_captured!.hosts.single.isSweeping, isTrue);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });

    testWidgets('is static under reduced motion', (tester) async {
      await _pump(
        tester,
        _scope(
          child: const Center(
            child: ExampleSheen.text(child: Text('Welcome back')),
          ),
        ),
        reduceMotion: true,
      );
      expect(find.byType(ShaderMask), findsOneWidget);
      // No controller published, so the mask paints its static highlight and
      // nothing ever animates it.
      expect(_captured, isNull);
      await _teardown(tester);
    });
  });

  group('layout', () {
    for (final brightness in Brightness.values) {
      testWidgets('a screen of hosts pumps at 375 x 812 (${brightness.name})',
          (tester) async {
        await _pump(
          tester,
          _scope(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ExampleSheen.text(child: Text('Good evening')),
                const SizedBox(height: 16),
                ExampleSheen(
                  borderRadius: BorderRadius.circular(16),
                  child:
                      Container(height: 120, color: ExampleColors.darkSurface),
                ),
                const SizedBox(height: 16),
                ExampleSheen(
                  intensity: ExampleSheenIntensity.soft,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(height: 6, color: ExampleColors.darkSurface),
                ),
                const SizedBox(height: 16),
                ExampleSheen(
                  angleDegrees: 24,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(height: 52, color: ExampleColors.darkSurface),
                ),
              ],
            ),
          ),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        expect(_captured!.hosts, hasLength(4));

        // Arrival, a full sweep and one idle round, at the design viewport.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 8));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        await _teardown(tester);
      });
    }
  });

  // The wave shipped the same Stack trap twice — once in the sheen overlay,
  // once in ExampleGlassPanel's frosted branch — and both collapsed every
  // primary CTA to its label width, in both themes, because a Stack's default
  // StackFit.loose relaxes a tight incoming width. Neither wrapper had a
  // layout contract test, which is why the second one landed at all. These
  // are that contract: whatever a Example wrapper is handed, its child gets.
  group('constraint transparency', () {
    const parentWidth = 340.0;

    Future<double> widthOfButtonUnder(
      WidgetTester tester,
      Widget Function(Widget child) wrap, {
      Brightness brightness = Brightness.dark,
    }) async {
      await _pump(
        tester,
        Center(
          child: SizedBox(
            width: parentWidth,
            child: wrap(
              FilledButton(onPressed: () {}, child: const Text('Continue')),
            ),
          ),
        ),
        brightness: brightness,
      );
      final width = tester.getSize(find.byType(FilledButton)).width;
      await _teardown(tester);
      return width;
    }

    for (final brightness in Brightness.values) {
      final name = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('ExampleSheen passes a tight width through on $name',
          (tester) async {
        expect(
          await widthOfButtonUnder(
            tester,
            (child) => ExampleSheen(
              intensity: ExampleSheenIntensity.onFill,
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
            brightness: brightness,
          ),
          parentWidth,
        );
      });

      testWidgets('ExampleSheen.text passes a tight width through on $name',
          (tester) async {
        expect(
          await widthOfButtonUnder(
            tester,
            (child) => ExampleSheen.text(
              intensity: ExampleSheenIntensity.soft,
              child: child,
            ),
            brightness: brightness,
          ),
          parentWidth,
        );
      });

      testWidgets('a frosted ExampleGlassPanel passes it through on $name',
          (tester) async {
        expect(
          await widthOfButtonUnder(
            tester,
            (child) => ExampleGlassPanel(
              padding: EdgeInsets.zero,
              material: ExampleGlassMaterial.frosted,
              child: child,
            ),
            brightness: brightness,
          ),
          parentWidth,
        );
      });

      testWidgets('a matte ExampleGlassPanel passes it through on $name',
          (tester) async {
        // Matte draws its edge as a 1 px inset border, so the body is
        // parentWidth - 2. Anything narrower is the loose-Stack collapse.
        expect(
          await widthOfButtonUnder(
            tester,
            (child) => ExampleGlassPanel(padding: EdgeInsets.zero, child: child),
            brightness: brightness,
          ),
          greaterThanOrEqualTo(parentWidth - 2),
        );
      });
    }

    testWidgets('a loose parent stays loose under ExampleSheen', (tester) async {
      // Transparency runs both ways: a wrapper must not tighten either.
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: ExampleSheen(
            borderRadius: BorderRadius.circular(14),
            child: FilledButton(onPressed: () {}, child: const Text('Go')),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(FilledButton)).width,
        lessThan(parentWidth),
      );
      await _teardown(tester);
    });
  });
}

// Tests for the Example route handoff (`ExampleRouteTransition`).
//
// The handoff used to hard-code `ExampleColors.appBackground` for both of its
// fills, so pearl daylight strobed a near-black panel over a paper-white app on
// every navigation. Both fills now read `ExamplePalette.of(context).paper`.
//
// The safety argument for that change is a single equality — the dark palette
// carries the historical constants, so `ExamplePalette.dark.paper` *is*
// `ExampleColors.appBackground` — and it is asserted first, below.
//
// Everything renders at a device pixel ratio of 1, at both 375 x 812 and
// 1440 x 900, in both brightnesses. flutter_test does not load pubspec fonts,
// so these tests assert structure, tokens, measured contrast and behaviour,
// never pixels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';

const _routeDuration = Duration(milliseconds: 420);

/// Marks the transition under test. `MaterialApp.home` is itself a route, so
/// the Example page-transitions theme wraps every one of these tests in a
/// second, already-settled `ExampleRouteTransition`; the key keeps the finders
/// on the one the test drives.
const _subjectKey = ValueKey<String>('transition-under-test');

AppBranding _branding({
  String brandId = 'example',
  String appName = 'EXAMPLE',
}) =>
    AppBranding(
      appName: appName,
      brandId: brandId,
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: 'dark',
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.com',
      supportPhone: '',
      legalEntity: '',
    );

/// WCAG 2.1 contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Contrast of [ink] painted at [alpha] over [ground], composited first.
double _ratioAt(Color ink, double alpha, Color ground) =>
    _ratio(Color.alphaBlend(ink.withValues(alpha: alpha), ground), ground);

/// Mounts the transition with an animation the test drives itself, so the
/// widget's own reduced-motion handling is what is under test rather than the
/// framework's 5 % duration scaling (which reads the platform flag, not this
/// `MediaQuery`).
Future<AnimationController> _mount(
  WidgetTester tester, {
  required Brightness brightness,
  Size size = const Size(375, 812),
  bool reduceMotion = false,
  double textScale = 1,
  Widget page = const Center(child: Text('page')),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final themes = buildAppThemes(_branding());
  final controller =
      AnimationController(vsync: const TestVSync(), duration: _routeDuration);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: app!,
      ),
      home: ExampleRouteTransition(
        key: _subjectKey,
        animation: controller,
        child: page,
      ),
    ),
  );
  return controller;
}

/// Drives [controller] forward and settles on the frame [elapsed] in.
///
/// [freeze] parks the ticker on that frame afterwards. The transition is a pure
/// function of `animation.value`, so the frame under test stays exactly where
/// it is, and no ticker outlives the test.
Future<void> _pushTo(
  WidgetTester tester,
  AnimationController controller,
  Duration elapsed, {
  bool freeze = true,
}) async {
  controller.forward();
  await tester.pump();
  await tester.pump(elapsed);
  if (freeze) controller.stop();
}

Finder _fills() => find.descendant(
      of: find.byKey(_subjectKey),
      matching: find.byType(ColoredBox),
    );

Finder _opacities() => find.descendant(
      of: find.byKey(_subjectKey),
      matching: find.byType(Opacity),
    );

Finder _stageTransforms() => find.descendant(
      of: find.byKey(_subjectKey),
      matching: find.byType(Transform),
    );

Finder _marks() => find.descendant(
      of: find.byKey(_subjectKey),
      matching: find.byType(ExampleLoader),
    );

ExampleLoader _loader(WidgetTester tester) =>
    tester.widget<ExampleLoader>(_marks());

void main() {
  group('palette equality — the safety argument for the change', () {
    test('the dark palette IS the historical constant the fills hard-coded',
        () {
      expect(ExamplePalette.dark.paper, ExampleColors.appBackground);
      expect(ExamplePalette.dark.paper.toARGB32(),
          ExampleColors.appBackground.toARGB32());
      expect(ExamplePalette.forBrightness(Brightness.dark).paper,
          ExampleColors.appBackground);
    });

    test('daylight is a different ground, which is the whole bug', () {
      expect(ExamplePalette.light.paper, ExampleColors.lightPaper);
      expect(ExamplePalette.light.paper, isNot(ExampleColors.appBackground));
    });

    test('white-label tenants never reach this widget at all', () {
      final example = buildAppThemes(_branding());
      final tenant = buildAppThemes(
        _branding(brandId: 'hoppa', appName: 'Hoppa'),
      );
      for (final theme in [example.light, example.dark]) {
        expect(
          theme.pageTransitionsTheme.builders.values,
          everyElement(isA<ExampleFadeTransitionsBuilder>()),
        );
      }
      for (final theme in [tenant.light, tenant.dark]) {
        expect(
          theme.pageTransitionsTheme.builders.values,
          isNot(anyElement(isA<ExampleFadeTransitionsBuilder>())),
          reason: 'a tenant keeps the Material transitions, byte-identical',
        );
      }
    });
  });

  group('ground and scrim follow the theme', () {
    for (final size in const [Size(375, 812), Size(1440, 900)]) {
      testWidgets('dark stays on #050713 at ${size.width.toInt()}',
          (tester) async {
        final controller =
            await _mount(tester, brightness: Brightness.dark, size: size);
        await _pushTo(tester, controller, const Duration(milliseconds: 120));

        final fills = tester.widgetList<ColoredBox>(_fills()).toList();
        expect(fills, hasLength(2), reason: 'ground + scrim');
        for (final fill in fills) {
          expect(fill.color, ExampleColors.appBackground);
        }
      });

      testWidgets('light lands on paper at ${size.width.toInt()}',
          (tester) async {
        final controller =
            await _mount(tester, brightness: Brightness.light, size: size);
        await _pushTo(tester, controller, const Duration(milliseconds: 120));

        final fills = tester.widgetList<ColoredBox>(_fills()).toList();
        expect(fills, hasLength(2), reason: 'ground + scrim');
        for (final fill in fills) {
          expect(fill.color, ExampleColors.lightPaper);
          expect(fill.color, isNot(ExampleColors.appBackground),
              reason: 'the near-black panel Naem filmed');
        }
      });
    }

    testWidgets('the settled route paints no ground at all', (tester) async {
      final controller = await _mount(tester, brightness: Brightness.light);
      await _pushTo(tester, controller, _routeDuration);
      await tester.pumpAndSettle();

      expect(_marks(), findsNothing);
      for (final opacity in tester.widgetList<Opacity>(_opacities())) {
        expect(opacity.opacity, anyOf(0.0, 1.0));
      }
    });

    testWidgets('a pop never raises the ground or the mark', (tester) async {
      final controller = await _mount(tester, brightness: Brightness.light);
      controller.value = 1;
      controller.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_marks(), findsNothing);
      for (final fill in tester.widgetList<ColoredBox>(_fills())) {
        expect(fill.color, ExampleColors.lightPaper);
      }
      // The one ground that exists is not painted; only the page fades.
      expect(
        tester.widgetList<Opacity>(_opacities()).map((o) => o.opacity),
        contains(0.0),
      );
      controller.stop();
    });
  });

  group('the mark follows the ground', () {
    testWidgets('dark uses stationary customer loading artwork', (tester) async {
      final controller = await _mount(tester, brightness: Brightness.dark);
      await _pushTo(tester, controller, const Duration(milliseconds: 120));

      final loader = _loader(tester);
      expect(loader.color, isNull, reason: 'the loader resolves the customer theme color');
      expect(loader.size, 96);
      expect(tester.widgetList<Transform>(_stageTransforms())
          .every((widget) => widget.transform.isIdentity()), isTrue,
          reason: 'the customer artwork remains stationary');
    });

    testWidgets('daylight goes monochrome in the brand indigo', (tester) async {
      final controller = await _mount(tester, brightness: Brightness.light);
      await _pushTo(tester, controller, const Duration(milliseconds: 120));

      final loader = _loader(tester);
      expect(loader.color, ExampleColors.indigo);
      expect(loader.size, 96, reason: 'same stage as ExampleLoader.transition');
      expect(loader.semanticsLabel, 'Loading');
    });

    testWidgets('daylight takes the same constructor, arrival and all',
        (tester) async {
      final controller = await _mount(tester, brightness: Brightness.light);
      await _pushTo(tester, controller, const Duration(milliseconds: 60),
          freeze: false);

      expect(tester.widgetList<Transform>(_stageTransforms())
          .every((widget) => widget.transform.isIdentity()), isTrue,
          reason: 'the customer artwork remains stationary');
      expect(_loader(tester).color, ExampleColors.indigo);

      await tester.pump(const Duration(milliseconds: 220));
      expect(_marks(), findsOneWidget);
      controller.stop();
    });

    testWidgets('the handoff mark never turns', (tester) async {
      // A route transition holds the customer artwork still.
      for (final brightness in Brightness.values) {
        final controller = await _mount(tester, brightness: brightness);
        await _pushTo(tester, controller, const Duration(milliseconds: 120));
        expect(_loader(tester).spin, isFalse,
            reason: '${brightness.name} handoff artwork must remain stationary');
        controller.stop();
      }
    });
  });

  test('handoff ink remains readable on daylight surfaces', () {
    for (final ground in const [ExampleColors.lightPaper,
      ExampleColors.lightSurface, ExampleColors.lightSurfaceSubtle,
      ExampleColors.lightSurfaceHigh]) {
      expect(_ratio(ExampleColors.indigo, ground), greaterThanOrEqualTo(3));
      expect(_ratioAt(ExampleColors.indigo, .65, ground), greaterThanOrEqualTo(3));
    }
  });

  group('reduced motion reaches the final state instantly', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: no mark, no scrim, no partial page',
          (tester) async {
        final controller = await _mount(
          tester,
          brightness: brightness,
          reduceMotion: true,
        );
        controller.forward();
        await tester.pump();
        for (final at in const [0, 21, 120, 300, 420]) {
          await tester.pump(Duration(milliseconds: at));
          expect(_marks(), findsNothing, reason: 'no orbit loader at ${at}ms');
          expect(_fills(), findsOneWidget,
              reason: 'the ground element stays, so nothing remounts');
          for (final opacity in tester.widgetList<Opacity>(_opacities())) {
            expect(opacity.opacity, anyOf(0.0, 1.0),
                reason: 'instant, not merely faster, at ${at}ms');
          }
          expect(find.text('page'), findsOneWidget);
        }
        controller.stop();
      });
    }

    testWidgets('control: the same frame does play the handoff without it',
        (tester) async {
      final controller = await _mount(tester, brightness: Brightness.light);
      // 300 ms, not 120: at 120 the choreography really is all-or-nothing —
      // the ground finished its ramp at 42 ms, the page does not start fading
      // until 40 % (168 ms) and the scrim does not start lifting until 58 %
      // (244 ms). This used to read partial at 120 ms only because daylight
      // wrapped the mark in an Opacity of its own to replay an arrival the
      // loader now owns, so the control was measuring the wrapper rather than
      // the handoff. At 300 ms both the page fade and the scrim lift are
      // genuinely mid-flight.
      await _pushTo(tester, controller, const Duration(milliseconds: 300));
      expect(_marks(), findsOneWidget);
      expect(
        tester.widgetList<Opacity>(_opacities()).map((o) => o.opacity),
        anyElement(allOf(greaterThan(0.0), lessThan(1.0))),
      );
    });
  });

  group('layout', () {
    for (final size in const [Size(375, 812), Size(1440, 900)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            '${brightness.name} at ${size.width.toInt()} survives a push at '
            'textScale 1.3', (tester) async {
          final controller = await _mount(
            tester,
            brightness: brightness,
            size: size,
            textScale: 1.3,
            page: Scaffold(
              appBar: AppBar(title: const Text('Accounts')),
              body: ListView(
                children: const [
                  ListTile(title: Text('Multi-currency account')),
                  ListTile(title: Text('Available balance')),
                ],
              ),
            ),
          );
          for (final at in const [0, 60, 120, 260, 400, 420]) {
            await _pushTo(tester, controller, Duration(milliseconds: at));
            expect(tester.takeException(), isNull, reason: 'no overflow');
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('wired through the real page-transitions theme', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: a real push scrims in the theme ground',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final themes = buildAppThemes(_branding());
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: themes.light,
            darkTheme: themes.dark,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const Scaffold(body: Center(child: Text('first'))),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('second'))),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.byType(ExampleRouteTransition), findsWidgets);
        final scrim = find.ancestor(
          of: find.byType(ExampleLoader),
          matching: find.byType(ColoredBox),
        );
        expect(scrim, findsOneWidget);
        expect(
          tester.widget<ColoredBox>(scrim).color,
          brightness == Brightness.dark
              ? ExampleColors.appBackground
              : ExampleColors.lightPaper,
        );
        await tester.pumpAndSettle();
        expect(find.text('second'), findsOneWidget);
      });
    }
  });
}

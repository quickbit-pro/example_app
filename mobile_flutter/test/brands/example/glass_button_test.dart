// Tests for ExampleGlassButton, the rounded glass CTA.
//
// flutter_test loads no pubspec fonts, so nothing here asserts pixels. It
// asserts the four things an adopter can actually break: that a tight incoming
// width survives every layer (the StackFit trap that has shipped three times
// in this repo), that reduced motion leaves nothing ticking, that disabled and
// loading refuse the tap, and that the plain-surface ground really does fall
// back to an opaque material instead of an invisible tint.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_glass_button.dart';
import 'package:mobile_flutter/brands/example/example_sheen.dart';

final ThemeData _dark = ThemeData(brightness: Brightness.dark);
final ThemeData _light = ThemeData(brightness: Brightness.light);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  Brightness brightness = Brightness.dark,
  Size size = const Size(375, 812),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? _dark : _light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The button's own body decoration — the one AnimatedContainer carrying a
/// gradient. The other one carries only the focus ring.
BoxDecoration _body(WidgetTester tester) {
  final containers = tester.widgetList<AnimatedContainer>(
    find.descendant(
      of: find.byType(ExampleGlassButton),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return containers
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.gradient != null);
}

void main() {
  group('constraint passthrough', () {
    testWidgets('a tight incoming width survives to the button', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(label: 'Sign in', onPressed: _noop),
        ),
      );
      expect(tester.getSize(find.byType(ExampleGlassButton)).width, 343);
    });

    testWidgets('survives the sheen and the backdrop blur too', (tester) async {
      await _pump(
        tester,
        const ExampleSheenScope(
          child: SizedBox(
            width: 343,
            child: ExampleGlassButton(
              label: 'Continue',
              ground: ExampleGlassGround.atmosphere,
              sheen: true,
              onPressed: _noop,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ExampleGlassButton)).width, 343);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expand false hugs the label', (tester) async {
      await _pump(
        tester,
        const ExampleGlassButton(
          label: 'Add money',
          expand: false,
          onPressed: _noop,
        ),
      );
      expect(
          tester.getSize(find.byType(ExampleGlassButton)).width, lessThan(343));
    });

    testWidgets('holds the 44 pt target floor even when asked for less', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Confirm',
            height: 20,
            onPressed: _noop,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ExampleGlassButton)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('reduced motion', () {
    testWidgets('leaves nothing scheduled and settles immediately', (
      tester,
    ) async {
      await _pump(
        tester,
        const ExampleSheenScope(
          child: SizedBox(
            width: 343,
            child: ExampleGlassButton(
              label: 'Sign in',
              ground: ExampleGlassGround.atmosphere,
              sheen: true,
              onPressed: _noop,
            ),
          ),
        ),
        reduceMotion: true,
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the loading ring is static, not spinning', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Confirm payment',
            loading: true,
            onPressed: _noop,
          ),
        ),
        reduceMotion: true,
      );
      await tester.pumpAndSettle();
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, isNotNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('states', () {
    testWidgets('a null callback disables the button and the tap', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(label: 'Order card', onPressed: null),
        ),
      );
      await tester.tap(find.byType(ExampleGlassButton));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final semantics = tester.getSemantics(find.byType(ExampleGlassButton));
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.flagsCollection.isEnabled.toBoolOrNull(), isNot(true));
    });

    testWidgets('loading refuses the tap and swaps the label in place', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Confirm payment',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(ExampleGlassButton), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The silhouette does not move while the content swaps.
      expect(tester.getSize(find.byType(ExampleGlassButton)).width, 343);
    });

    testWidgets('loading announces itself', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Confirm payment',
            loading: true,
            onPressed: _noop,
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(ExampleGlassButton));
      expect(semantics.label, 'Confirm payment, in progress');
    });

    testWidgets('an enabled button fires once per tap', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Continue',
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(ExampleGlassButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('grounds', () {
    testWidgets('the plain-surface fallback is opaque and does not blur', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await _pump(
          tester,
          const SizedBox(
            width: 343,
            child: ExampleGlassButton(label: 'Sign in', onPressed: _noop),
          ),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        final gradient = _body(tester).gradient! as LinearGradient;
        for (final color in gradient.colors) {
          expect(color.a, 1.0, reason: 'opaque on $brightness');
        }
      }
    });

    testWidgets('the neutral surface fallback is opaque too', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Maybe later',
            tone: ExampleGlassButtonTone.neutral,
            onPressed: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      final gradient = _body(tester).gradient! as LinearGradient;
      for (final color in gradient.colors) {
        expect(color.a, 1.0);
      }
    });

    testWidgets('artwork pins the material to Twilight on a light page', (
      tester,
    ) async {
      late LinearGradient onLightPage;
      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Freeze card',
            ground: ExampleGlassGround.artwork,
            onPressed: _noop,
          ),
        ),
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();
      onLightPage = _body(tester).gradient! as LinearGradient;

      await _pump(
        tester,
        const SizedBox(
          width: 343,
          child: ExampleGlassButton(
            label: 'Freeze card',
            ground: ExampleGlassGround.artwork,
            onPressed: _noop,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final onDarkPage = _body(tester).gradient! as LinearGradient;
      expect(onLightPage.colors, onDarkPage.colors);
    });
  });

  group('layout', () {
    for (final width in <double>[375, 393, 834, 1440]) {
      for (final brightness in Brightness.values) {
        testWidgets('no overflow at $width in $brightness', (tester) async {
          await _pump(
            tester,
            SizedBox(
              width: width - 32,
              child: const ExampleGlassButton(
                label: 'Confirm payment',
                icon: Icons.lock_outline,
                trailing: Icon(Icons.arrow_forward_rounded),
                onPressed: _noop,
              ),
            ),
            brightness: brightness,
            size: Size(width, 812),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

void _noop() {}

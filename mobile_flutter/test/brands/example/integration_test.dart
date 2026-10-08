// The seams the integrator owns: the barrel, the alive layer's contract with
// the skeleton, and the palette roles the two brightness facades share.
//
// Everything here renders with animations disabled, so the sheen never reaches
// a ticker or a timer: the assertions are about which widgets are in the tree
// and which colours the tokens resolve to, not about motion. The sweeps
// themselves are covered by test/brands/example/sheen_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// One import on purpose: if the barrel stops exporting a file, this stops
// compiling.
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';

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
  legalEntity: '',
);

/// Pumps [child] inside the real Example theme at 375 x 812, with motion off.
/// [reduceMotion] defaults to true purely so `pumpAndSettle` terminates: an
/// endless sheen never settles, and most cases here are asserting layout and
/// colour rather than motion. It is NOT a statement about the viewer — since
/// the scope treats reduced motion as a hard kill switch and publishes no
/// controller, any test that needs a LIVE scope must pass false and drive the
/// clock with explicit pumps instead.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  bool reduceMotion = true,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final themes = buildAppThemes(_branding);
  await tester.pumpWidget(
    MaterialApp(
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: app!,
      ),
      home: Scaffold(body: child),
    ),
  );
  if (reduceMotion) {
    await tester.pumpAndSettle();
  } else {
    // A live scope loops forever, so settling is not an option. One frame to
    // mount, one past the 250 ms arrival delay.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  group('barrel', () {
    test('exports the alive layer and the palette', () {
      // Compile-time proof: these names resolve through example.dart alone.
      // Three intensities, not two: `onFill` was added for the hosts that
      // carry a label on a saturated fill (the primary CTA, the active nav
      // indicator), where the band composites over the glyphs and a `normal`
      // peak drops a white label to 2.78:1.
      expect(ExampleSheenIntensity.values, hasLength(3));
      expect(
        ExampleSheenIntensity.values,
        containsAll(<ExampleSheenIntensity>[
          ExampleSheenIntensity.soft,
          ExampleSheenIntensity.normal,
          ExampleSheenIntensity.onFill,
        ]),
      );
      expect(ExamplePalette.dark.isDark, isTrue);
      expect(ExamplePalette.light.brightness, Brightness.light);
    });
  });

  group('ExampleSkeleton and the alive layer', () {
    testWidgets('stays a static block when no scope is above it',
        (tester) async {
      await _pump(tester, const ExampleSkeleton.card());
      expect(find.byType(ExampleSkeleton), findsOneWidget);
      expect(find.byType(ExampleSheen), findsNothing);
    });

    testWidgets('takes one soft sheen inside a scope', (tester) async {
      await _pump(
        tester,
        const ExampleSheenScope(child: ExampleSkeleton.card()),
        // This case is specifically about what a LIVE scope hands its hosts.
        reduceMotion: false,
      );
      final sheen = tester.widget<ExampleSheen>(find.byType(ExampleSheen));
      expect(sheen.intensity, ExampleSheenIntensity.soft);
      // Clipped to the block's own radius, so the band never squares a corner.
      expect(sheen.borderRadius, BorderRadius.circular(AppRadii.lg));
    });

    testWidgets('opts out with sheen: false, so a list can host one band',
        (tester) async {
      await _pump(
        tester,
        const ExampleSheenScope(
          child: Column(
            children: [
              ExampleSkeleton.row(sheen: false),
              ExampleSkeleton.row(sheen: false),
            ],
          ),
        ),
      );
      expect(find.byType(ExampleSkeleton), findsNWidgets(2));
      expect(find.byType(ExampleSheen), findsNothing);
    });

    testWidgets('keeps its fade-in and its semantics inside a scope',
        (tester) async {
      await _pump(
        tester,
        const ExampleSheenScope(child: ExampleSkeleton.card()),
      );
      expect(
        find.descendant(
          of: find.byType(ExampleSkeleton),
          matching: find.byType(Opacity),
        ),
        findsOneWidget,
      );
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('resolves its tint from the palette in both themes',
        (tester) async {
      Color? tint;
      Widget probe() => Builder(
            builder: (context) {
              tint = ExampleSkeleton.tintOf(context);
              return const SizedBox.shrink();
            },
          );
      await _pump(tester, probe());
      expect(tint, ExampleColors.darkSurfaceSubtle);
      await _pump(tester, probe(), brightness: Brightness.light);
      expect(tint, ExampleColors.lightSkeletonBase);
    });
  });

  group('palette', () {
    test('the skeleton highlight is the sheen band, in both themes', () {
      expect(ExamplePalette.dark.skeletonHighlight, ExampleColors.sheenPeak);
      expect(
        ExamplePalette.light.skeletonHighlight,
        ExampleColors.lightSheenPeak,
      );
      expect(ExamplePalette.dark.sheenPeak, ExampleColors.sheenPeak);
      expect(ExamplePalette.light.sheenPeak, ExampleColors.lightSheenPeak);
    });

    test('both brightness facades read the same constants', () {
      expect(
        ExampleSurface.forBrightness(Brightness.light, 2),
        ExamplePalette.light.surfaceSubtle,
      );
      expect(
        ExampleSurface.forBrightness(Brightness.dark, 2),
        ExamplePalette.dark.surfaceSubtle,
      );
    });
  });
}

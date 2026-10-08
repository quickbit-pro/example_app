// Wave-1 smoke tests for the Example foundation: motion, amount, skeleton,
// states, atmosphere, glass, rows and the theme contract that keeps every
// other brand's text theme byte-identical to the pre-wave build.
//
// Everything renders at the 375 x 812 design viewport with a device pixel
// ratio of 1. flutter_test does not load pubspec fonts, so these tests assert
// structure, tokens and behaviour, never pixels.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/shared/theme/app_colors.dart';
import 'package:mobile_flutter/shared/theme/app_typography.dart';

AppBranding _branding({
  String brandId = 'example',
  String appName = 'EXAMPLE',
  String fontFamily = '',
}) =>
    AppBranding(
      appName: appName,
      brandId: brandId,
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: 'dark',
      fontFamily: fontFamily,
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.com',
      supportPhone: '',
      legalEntity: '',
    );

/// Pumps [child] as a Scaffold body inside the Example theme at 375 x 812.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  bool highContrast = false,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final themes = buildAppThemes(_branding());
  await tester.pumpWidget(
    MaterialApp(
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          highContrast: highContrast,
        ),
        child: app!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

AnimatedScale _scaleOf(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale));

Finder _atmospherePaint() => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is ExampleAtmospherePainter,
    );

ExampleAtmospherePainter _painterOf(WidgetTester tester) =>
    tester.widget<CustomPaint>(_atmospherePaint()).painter!
        as ExampleAtmospherePainter;

Finder _hairlines() => find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration ==
              const BoxDecoration(
                border: Border(bottom: ExampleBorders.hairlineSide),
              ),
    );

const _fallbackCard = PaymentCard(
  id: 'card-1',
  label: 'Card',
  last4: '3191',
  network: 'Visa',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 0),
  spendThisMonth: Money(currency: 'USD', minorUnits: 0),
  limit: Money(currency: 'USD', minorUnits: 0),
  virtual: false,
);

void main() {
  group('ExamplePressable', () {
    testWidgets('scales to pressedScale on pointer down and back on release',
        (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Center(
          child: ExamplePressable(
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );
      expect(_scaleOf(tester).scale, 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ExamplePressable)),
      );
      await tester.pump();
      expect(_scaleOf(tester).scale, .97);
      expect(_scaleOf(tester).duration, ExampleMotion.press);
      expect(_scaleOf(tester).curve, ExampleMotion.arrive);

      await tester.pump(ExampleMotion.press);
      await gesture.up();
      await tester.pump();
      expect(_scaleOf(tester).scale, 1);
      expect(_scaleOf(tester).duration, ExampleMotion.state);
      expect(_scaleOf(tester).curve, ExampleMotion.out);

      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('does not scale under reduced motion but still taps',
        (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Center(
          child: ExamplePressable(
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
        reduceMotion: true,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ExamplePressable)),
      );
      await tester.pump();
      expect(_scaleOf(tester).scale, 1);
      expect(_scaleOf(tester).duration, Duration.zero);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_scaleOf(tester).scale, 1);
      expect(taps, 1);
    });

    testWidgets('cancels the press once the pointer drags past the slop',
        (tester) async {
      await _pump(
        tester,
        Center(
          child: ExamplePressable(
            onTap: () {},
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ExamplePressable)),
      );
      await tester.pump();
      expect(_scaleOf(tester).scale, .97);

      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(_scaleOf(tester).scale, 1);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('as a visual wrapper it lets the child keep its gesture',
        (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        Center(
          child: ExamplePressable(
            child: FilledButton(
              onPressed: () => pressed++,
              child: const Text('Go'),
            ),
          ),
        ),
      );
      expect(find.byType(AnimatedScale), findsOneWidget);
      // The only gesture in the tree is the button's own InkWell; the
      // wrapper adds no detector, semantics node or focus stop of its own.
      expect(find.byType(GestureDetector), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(GestureDetector),
        ),
        findsOneWidget,
      );
      expect(find.byType(FocusableActionDetector), findsNothing);

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });

    testWidgets('disabled pressable neither scales nor fires', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Center(
          child: ExamplePressable(
            enabled: false,
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ExamplePressable)),
      );
      await tester.pump();
      expect(_scaleOf(tester).scale, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    });
  });

  group('ExampleStateSwitch', () {
    testWidgets('crossfades keyed children on the state token', (tester) async {
      var showB = false;
      late StateSetter setter;
      await _pump(
        tester,
        Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              setter = setState;
              return ExampleStateSwitch(
                child: Text(showB ? 'B' : 'A', key: ValueKey<bool>(showB)),
              );
            },
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);

      final switcher =
          tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, ExampleMotion.state);
      expect(
        switcher.reverseDuration,
        ExampleMotion.exitOf(ExampleMotion.state),
      );
      expect(switcher.switchInCurve, ExampleMotion.arrive);
      expect(switcher.switchOutCurve, ExampleMotion.exit);

      setter(() => showB = true);
      await tester.pump();
      await tester.pump(ExampleMotion.state ~/ 2);
      // Half way through, the outgoing child is still fading out.
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('swaps instantly under reduced motion', (tester) async {
      var showB = false;
      late StateSetter setter;
      await _pump(
        tester,
        Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              setter = setState;
              return ExampleStateSwitch(
                child: Text(showB ? 'B' : 'A', key: ValueKey<bool>(showB)),
              );
            },
          ),
        ),
        reduceMotion: true,
      );
      final switcher =
          tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, Duration.zero);

      setter(() => showB = true);
      await tester.pump();
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('ExampleAmount', () {
    testWidgets('sets a symbol currency with the fraction split at large',
        (tester) async {
      await _pump(
        tester,
        const Center(
          child: ExampleAmount(amount: 1234.56, currency: 'USD'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(r'$1,234.56'), findsOneWidget);
      final text = tester.widget<Text>(find.byType(Text));
      final span = text.textSpan! as TextSpan;
      // Number run, then the smaller fraction run; no code for a symbol.
      expect(span.children, hasLength(2));
      expect((span.children![0] as TextSpan).text, r'$1,234');
      expect((span.children![1] as TextSpan).text, '.56');
      expect(
        (span.children![1] as TextSpan).style!.fontSize,
        (ExampleAmountSize.large.fontSize * .6).roundToDouble(),
      );
      expect(span.style!.fontSize, ExampleAmountSize.large.fontSize);
      expect(span.style!.fontWeight, ExampleAmountSize.large.fontWeight);
      expect(span.style!.fontFeatures,
          contains(const FontFeature.tabularFigures()));
    });

    testWidgets('shows the ISO code small when asked or when unsymbolled',
        (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            ExampleAmount(
              amount: 1234.56,
              currency: 'USD',
              code: ExampleAmountCode.always,
            ),
            ExampleAmount(
              amount: 5,
              currency: 'AED',
              size: ExampleAmountSize.small,
            ),
            ExampleAmount(
              amount: 5,
              currency: 'AED',
              size: ExampleAmountSize.small,
              code: ExampleAmountCode.never,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(r'$1,234.56 USD'), findsOneWidget);
      expect(find.text('5.00 AED'), findsOneWidget);
      expect(find.text('5.00'), findsOneWidget);
    });

    testWidgets('holds its line with a placeholder while null', (tester) async {
      await _pump(
        tester,
        const Center(
          child: ExampleAmount(
            amount: null,
            currency: 'USD',
            code: ExampleAmountCode.always,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('${ExampleAmount.placeholder} USD'), findsOneWidget);
    });

    testWidgets('colours by tone with the Twilight semantic tokens',
        (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            ExampleAmount(
              amount: 20,
              currency: 'USD',
              size: ExampleAmountSize.inline,
              tone: ExampleAmountTone.signed,
            ),
            ExampleAmount(
              amount: -3.5,
              currency: 'USD',
              size: ExampleAmountSize.inline,
              tone: ExampleAmountTone.delta,
            ),
            ExampleAmount(
              amount: -3.5,
              currency: 'USD',
              size: ExampleAmountSize.inline,
              tone: ExampleAmountTone.signed,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final credit = tester.widget<Text>(find.text(r'+$20.00'));
      expect((credit.textSpan as TextSpan).style!.color, ExampleColors.success);
      final texts = tester.widgetList<Text>(find.text(r'-$3.50')).toList();
      expect(texts, hasLength(2));
      expect((texts[0].textSpan as TextSpan).style!.color, ExampleColors.danger);
      expect((texts[1].textSpan as TextSpan).style!.color, ExampleColors.pearl);
    });

    testWidgets('crossfades when the value changes and settles clean',
        (tester) async {
      var amount = 10.0;
      late StateSetter setter;
      await _pump(
        tester,
        Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              setter = setState;
              return ExampleAmount(amount: amount, currency: 'USD');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSwitcher), findsOneWidget);

      setter(() => amount = 20);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text(r'$20.00'), findsOneWidget);
      expect(find.text(r'$10.00'), findsNothing);
    });

    testWidgets('animate false renders without a switcher', (tester) async {
      await _pump(
        tester,
        const Center(
          child: ExampleAmount(amount: 1, currency: 'EUR', animate: false),
        ),
      );
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.text('€1.00'), findsOneWidget);
    });
  });

  group('ExampleMono', () {
    test('truncates the middle and groups digits', () {
      expect(
        ExampleMono.truncateMiddle('0x1234567890abcdef'),
        '0x1234…cdef',
      );
      expect(ExampleMono.truncateMiddle('short'), 'short');
      expect(
        ExampleMono.groupEvery('4242424242424242', 4),
        '4242 4242 4242 4242',
      );
      expect(ExampleMono.groupEvery('abc', 0), 'abc');
      expect(
        const ExampleMono(
          '4242424242424242',
          group: 4,
          truncate: ExampleMonoTruncate.middle,
          head: 4,
          tail: 4,
        ).display,
        '4242…4242',
      );
    });

    testWidgets('uses Geist Mono with slashed zeros inside Example',
        (tester) async {
      await _pump(tester, const Center(child: ExampleMono('0x00AB')));
      final text = tester.widget<Text>(find.text('0x00AB'));
      expect(text.style!.fontFamily, ExampleFonts.mono);
      expect(text.style!.fontFeatures, contains(const FontFeature('ss09')));
    });

    testWidgets('copyable strings copy the full text and confirm in place',
        (tester) async {
      String? copied;
      var notified = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pump(
        tester,
        Center(
          child: ExampleMono(
            '0x1234567890abcdef',
            truncate: ExampleMonoTruncate.middle,
            copyable: true,
            onCopied: () => notified++,
          ),
        ),
      );
      expect(find.text('0x1234…cdef'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(
        tester.getSize(find.byType(ExamplePressable)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.byType(ExamplePressable));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(copied, '0x1234567890abcdef');
      expect(notified, 1);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester
          .pump(ExampleMono.copiedFor + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });
  });

  group('ExampleSkeleton', () {
    const presets = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExampleSkeleton(),
        ExampleSkeleton.line(widthFactor: .4),
        ExampleSkeleton.avatar(),
        ExampleSkeleton.amount(),
        ExampleSkeleton.row(),
        ExampleSkeleton.card(),
      ],
    );

    testWidgets('every preset lays out at its promised size at 375 wide',
        (tester) async {
      await _pump(tester, presets);
      await tester.pumpAndSettle();
      final skeletons = find.byType(ExampleSkeleton);
      expect(skeletons, findsNWidgets(6));
      expect(tester.getSize(skeletons.at(0)), const Size(375, 16));
      expect(tester.getSize(skeletons.at(1)), const Size(150, 12));
      expect(tester.getSize(skeletons.at(2)), const Size(32, 32));
      final amount = tester.getSize(skeletons.at(3));
      expect(
        amount.height,
        closeTo(
          ExampleAmountSize.large.fontSize * ExampleAmountSize.large.height,
          .01,
        ),
      );
      expect(tester.getSize(skeletons.at(4)).height, 60);
      expect(tester.getSize(skeletons.at(5)), const Size(375, 120));

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Loading'), findsNWidgets(6));
      handle.dispose();
    });

    testWidgets('fades in once on the state token, instantly when reduced',
        (tester) async {
      await _pump(tester, const ExampleSkeleton.card());
      Opacity opacity() => tester.widget<Opacity>(
            find.descendant(
              of: find.byType(ExampleSkeleton),
              matching: find.byType(Opacity),
            ),
          );
      expect(opacity().opacity, 0);
      await tester.pump(ExampleMotion.state);
      await tester.pumpAndSettle();
      expect(opacity().opacity, 1);
      expect(
        find.descendant(
          of: find.byType(ExampleSkeleton),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );

      await _pump(tester, const ExampleSkeleton.card(), reduceMotion: true);
      expect(opacity().opacity, 1);
    });
  });

  group('Empty and error states', () {
    testWidgets('empty state renders mark, copy and actions at 375',
        (tester) async {
      var primary = 0;
      var secondary = 0;
      await _pump(
        tester,
        ExampleEmptyState(
          title: 'Your first card is a tap away',
          body: 'Order a virtual card and start spending in minutes.',
          actionLabel: 'Order a card',
          onAction: () => primary++,
          secondaryLabel: 'Not now',
          onSecondary: () => secondary++,
        ),
      );
      expect(find.text('Your first card is a tap away'), findsOneWidget);
      expect(find.byType(ExampleMark), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      await tester.tap(find.text('Order a card'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(primary, 1);
      expect(secondary, 1);
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('empty state with an icon drops the mark; compact fits',
        (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            ExampleEmptyState(
              title: 'No activity yet',
              icon: Icons.receipt_long_rounded,
              compact: true,
            ),
          ],
        ),
      );
      expect(find.byType(ExampleMark), findsNothing);
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('error state derives a friendly body and retries',
        (tester) async {
      var retries = 0;
      await _pump(
        tester,
        ExampleErrorState(
          error: Exception('socket timeout'),
          onRetry: () => retries++,
        ),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.text(
          'We could not reach the service. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets('error state prefers an explicit body', (tester) async {
      await _pump(
        tester,
        const ExampleErrorState(
          title: 'Rates unavailable',
          body: 'Live prices paused. Balances are still correct.',
          error: 'ignored',
        ),
      );
      expect(find.text('Rates unavailable'), findsOneWidget);
      expect(
        find.text('Live prices paused. Balances are still correct.'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('ExampleAtmosphere', () {
    testWidgets('presets paint the night ground behind their child',
        (tester) async {
      final presets = <String, Widget>{
        'auth': const ExampleAtmosphere.auth(child: SizedBox.expand()),
        'home': const ExampleAtmosphere.home(child: SizedBox.expand()),
        'card': const ExampleAtmosphere.card(child: SizedBox.expand()),
        'quiet': const ExampleAtmosphere.quiet(child: SizedBox.expand()),
      };
      for (final entry in presets.entries) {
        await _pump(tester, entry.value);
        expect(_atmospherePaint(), findsOneWidget, reason: entry.key);
        final painter = _painterOf(tester);
        expect(painter.base, ExampleColors.appBackground, reason: entry.key);
        expect(painter.intensity, 1, reason: entry.key);
        expect(painter.horizon, isNull, reason: entry.key);
        expect(painter.glows, hasLength(2), reason: entry.key);
        expect(
          find.ancestor(
            of: _atmospherePaint(),
            matching: find.byType(RepaintBoundary),
          ),
          findsWidgets,
          reason: entry.key,
        );
      }
    });

    testWidgets('paints on paper at .80 under the Example light theme',
        (tester) async {
      // .4 left every authored light glow at an effective .08 and the ground
      // composited to a 1.09:1 field — paper with no sky, which is the
      // strongest "inverted dark theme" tell there is. .80 more than doubles
      // the travel and still clears every ink role over the brightest preset
      // peak. A preset with no [lightGlows] keeps the .4 fallback, because it
      // is painting DARK glows onto paper.
      await _pump(
        tester,
        const ExampleAtmosphere.quiet(horizon: .3),
        brightness: Brightness.light,
      );
      final painter = _painterOf(tester);
      expect(painter.base, ExampleColors.lightPaper);
      expect(painter.intensity, .80);
      expect(painter.horizon, .3);
      expect(painter.horizonColor, ExampleColors.lightBorder);

      await _pump(
        tester,
        const ExampleAtmosphere(glows: [], base: ExampleColors.night),
        brightness: Brightness.light,
      );
      expect(_painterOf(tester).base, ExampleColors.night);
      expect(_painterOf(tester).intensity, 1);
    });

    test('glows compare by value and clamp intensity', () {
      const a = ExampleAtmosphereGlow(
        color: ExampleColors.violet,
        center: Alignment.topCenter,
      );
      const b = ExampleAtmosphereGlow(
        color: ExampleColors.violet,
        center: Alignment.topCenter,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const ExampleAtmosphereGlow(
            color: ExampleColors.teal,
            center: Alignment.topCenter,
          ),
        ),
      );
      expect(
        () => a.shader(const Rect.fromLTWH(0, 0, 100, 100), intensity: 9),
        returnsNormally,
      );
    });
  });

  group('ExampleGlassPanel', () {
    testWidgets('matte is the default and has no blur', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Center(
          child: ExampleGlassPanel(
            onTap: () => taps++,
            child: const Text('Matte'),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Matte'), findsOneWidget);
      final ink = tester.widget<Ink>(find.byType(Ink));
      expect((ink.decoration! as BoxDecoration).boxShadow, isEmpty);

      await tester.tap(find.text('Matte'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('matte emphasis carries the shared violet glow token',
        (tester) async {
      await _pump(
        tester,
        const Center(
          child: ExampleGlassPanel(emphasis: true, child: Text('Hero')),
        ),
      );
      final ink = tester.widget<Ink>(find.byType(Ink));
      expect(
        (ink.decoration! as BoxDecoration).boxShadow,
        ExampleShadows.glow(ExampleColors.violet, spread: -8, blur: 30),
      );
    });

    testWidgets('frosted blurs inside its own repaint boundary and clip',
        (tester) async {
      var taps = 0;
      await _pump(
        tester,
        ExampleAtmosphere.card(
          child: Center(
            child: ExampleGlassPanel(
              material: ExampleGlassMaterial.frosted,
              onTap: () => taps++,
              child: const Text('Frosted'),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(ClipRRect),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Frosted'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('frosted falls back to matte under high contrast',
        (tester) async {
      await _pump(
        tester,
        const Center(
          child: ExampleGlassPanel(
            material: ExampleGlassMaterial.frosted,
            child: Text('Readable'),
          ),
        ),
        highContrast: true,
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(Ink), findsOneWidget);
    });
  });

  group('Tokenised legacy glows', () {
    test('ExampleShadows.glow reproduces the three former literals', () {
      expect(
        ExampleShadows.glow(
          ExampleColors.violet,
          alpha: .18,
          blur: 26,
          spread: 0,
          offset: const Offset(0, 12),
        ).single,
        BoxShadow(
          color: ExampleColors.violet.withValues(alpha: .18),
          blurRadius: 26,
          offset: const Offset(0, 12),
        ),
      );
      expect(
        ExampleShadows.glow(ExampleColors.violet, spread: -8, blur: 30).single,
        BoxShadow(
          color: ExampleColors.violet.withValues(alpha: .35),
          blurRadius: 30,
          spreadRadius: -8,
        ),
      );
      expect(
        ExampleShadows.glow(
          ExampleColors.violet,
          alpha: .45,
          blur: 14,
          spread: -4,
        ).single,
        BoxShadow(
          color: ExampleColors.violet.withValues(alpha: .45),
          blurRadius: 14,
          spreadRadius: -4,
        ),
      );
    });

    testWidgets('payment card keeps its .18 / 26 / y12 violet lift',
        (tester) async {
      await _pump(
        tester,
        const Center(
          child: SizedBox(
            width: 343,
            child: ExamplePaymentCard(card: _fallbackCard),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ExamplePaymentCard),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (container.decoration! as BoxDecoration).boxShadow,
        [
          BoxShadow(
            color: ExampleColors.violet.withValues(alpha: .18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      );
    });

    testWidgets('segmented control selects on the state token', (tester) async {
      String? picked;
      await _pump(
        tester,
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ExampleSegmentedControl<String>(
            segments: const [
              (value: 'money', label: 'Money'),
              (value: 'crypto', label: 'Crypto'),
            ],
            selected: 'money',
            onChanged: (value) => picked = value,
          ),
        ),
      );
      final containers = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();
      expect(containers, hasLength(2));
      for (final container in containers) {
        expect(container.duration, ExampleMotion.state);
        expect(container.curve, ExampleMotion.arrive);
      }
      final selected = containers.singleWhere(
        (c) => (c.decoration! as BoxDecoration).color == ExampleColors.violet,
      );
      expect(
        (selected.decoration! as BoxDecoration).boxShadow,
        ExampleShadows.glow(
          ExampleColors.violet,
          alpha: .45,
          blur: 14,
          spread: -4,
        ),
      );

      await tester.tap(find.text('Crypto'));
      await tester.pumpAndSettle();
      expect(picked, 'crypto');

      await _pump(
        tester,
        ExampleSegmentedControl<String>(
          segments: const [(value: 'a', label: 'A')],
          selected: 'a',
          onChanged: (_) {},
        ),
        reduceMotion: true,
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero,
      );
    });

    testWidgets('circle action dims to the disabled token', (tester) async {
      await _pump(
        tester,
        const Center(
          child: ExampleCircleAction(
            icon: Icons.send_rounded,
            label: 'Send',
            onTap: null,
          ),
        ),
      );
      final dimmed = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(ExampleCircleAction),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(dimmed.opacity, ExampleOpacity.disabled);
    });
  });

  group('ExampleRow and ExampleListGroup', () {
    testWidgets('group draws inset hairlines between rows and a title',
        (tester) async {
      var opened = 0;
      var seeAll = 0;
      await _pump(
        tester,
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ExampleListGroup(
            title: 'Accounts',
            action: 'See all',
            onAction: () => seeAll++,
            children: [
              ExampleRow(
                title: 'USD account',
                subtitle: 'Main',
                leading: const ExampleCurrencyAvatar(code: 'USD'),
                trailing: const ExampleRowValue(
                  value: r'$1,240.00',
                  caption: 'Available',
                ),
                onTap: () => opened++,
                semanticsLabel: 'Open USD account',
              ),
              const ExampleRow(
                title: 'Savings',
                subtitle: 'Locked until June',
                leading: ExampleCurrencyAvatar(code: 'EUR'),
                trailing: ExampleRow.chevron,
              ),
              ExampleRow(
                title: 'Disabled account',
                enabled: false,
                onTap: () => opened++,
              ),
            ],
          ),
        ),
      );
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('USD account'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(_hairlines(), findsNWidgets(2));
      expect(find.byType(ExampleRow), findsNWidgets(3));
      for (final row in find.byType(ExampleRow).evaluate()) {
        expect(
          tester.getSize(find.byWidget(row.widget)).height,
          greaterThanOrEqualTo(56),
        );
      }

      await tester.tap(find.text('USD account'));
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(seeAll, 1);

      await tester.tap(find.text('Disabled account'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      final dimmed = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('Disabled account'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(dimmed.opacity, ExampleOpacity.disabled);
      expect(dimmed.duration, ExampleMotion.state);

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Open USD account'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a row without a gesture is not a button and can divide',
        (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            ExampleRow(title: 'Static', divider: true),
            ExampleRow(title: 'Second'),
          ],
        ),
      );
      expect(find.byType(ExamplePressable), findsNothing);
      expect(_hairlines(), findsOneWidget);
      expect(find.byType(MergeSemantics), findsWidgets);
    });

    testWidgets('disabled row dims instantly under reduced motion',
        (tester) async {
      await _pump(
        tester,
        const ExampleRow(title: 'Off', enabled: false),
        reduceMotion: true,
      );
      final dimmed =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(dimmed.opacity, ExampleOpacity.disabled);
      expect(dimmed.duration, Duration.zero);
    });
  });

  group('Theme contract', () {
    // The shared scale exactly as it shipped before wave 1. If any of these
    // move, every non-Example tenant moves with them.
    const baseline = <String, (double, FontWeight, double, double?)>{
      'displayLarge': (44, FontWeight.w800, 1.05, -0.6),
      'displayMedium': (36, FontWeight.w800, 1.06, -0.5),
      'displaySmall': (30, FontWeight.w800, 1.08, -0.4),
      'headlineMedium': (26, FontWeight.w800, 1.16, -0.3),
      'headlineSmall': (22, FontWeight.w800, 1.18, -0.2),
      'titleLarge': (18, FontWeight.w700, 1.22, null),
      'titleMedium': (16, FontWeight.w700, 1.25, null),
      'titleSmall': (14, FontWeight.w700, 1.28, null),
      'bodyLarge': (16, FontWeight.w400, 1.45, null),
      'bodyMedium': (14, FontWeight.w400, 1.42, null),
      'bodySmall': (12, FontWeight.w400, 1.35, null),
      'labelLarge': (14, FontWeight.w700, 1.2, 0.1),
      'labelMedium': (12, FontWeight.w700, 1.2, 0.2),
      'labelSmall': (11, FontWeight.w700, 1.2, 0.4),
    };

    TextStyle? slot(TextTheme theme, String name) => switch (name) {
          'displayLarge' => theme.displayLarge,
          'displayMedium' => theme.displayMedium,
          'displaySmall' => theme.displaySmall,
          'headlineMedium' => theme.headlineMedium,
          'headlineSmall' => theme.headlineSmall,
          'titleLarge' => theme.titleLarge,
          'titleMedium' => theme.titleMedium,
          'titleSmall' => theme.titleSmall,
          'bodyLarge' => theme.bodyLarge,
          'bodyMedium' => theme.bodyMedium,
          'bodySmall' => theme.bodySmall,
          'labelLarge' => theme.labelLarge,
          'labelMedium' => theme.labelMedium,
          'labelSmall' => theme.labelSmall,
          _ => throw ArgumentError.value(name),
        };

    test('AppTypography.textTheme without a family is the pre-wave scale', () {
      final scale = AppTypography.textTheme(HoppaColors.inkDark);
      expect(scale.headlineLarge, isNull);
      for (final entry in baseline.entries) {
        final style = slot(scale, entry.key)!;
        expect(style.fontFamily, isNull, reason: entry.key);
        expect(style.color, HoppaColors.inkDark, reason: entry.key);
        expect(style.fontSize, entry.value.$1, reason: entry.key);
        expect(style.fontWeight, entry.value.$2, reason: entry.key);
        expect(style.height, entry.value.$3, reason: entry.key);
        expect(style.letterSpacing, entry.value.$4, reason: entry.key);
      }
      // A tenant family threads through untouched; blank means none.
      expect(
        AppTypography.textTheme(HoppaColors.ink, fontFamily: 'Inter')
            .bodyLarge!
            .fontFamily,
        'Inter',
      );
      expect(
        AppTypography.textTheme(HoppaColors.ink, fontFamily: '  ')
            .bodyLarge!
            .fontFamily,
        isNull,
      );
    });

    test('a non-Example brand builds the same text theme as before', () {
      final generic =
          buildAppThemes(_branding(brandId: 'hoppa', appName: 'Hoppa'));
      for (final (theme, ink) in [
        (generic.dark, HoppaColors.inkDark),
        (generic.light, HoppaColors.ink),
      ]) {
        final before = ThemeData(
          brightness: theme.brightness,
          colorScheme: theme.colorScheme,
          useMaterial3: true,
          textTheme: AppTypography.textTheme(ink),
        );
        expect(theme.textTheme, before.textTheme);
        expect(theme.extension<ExampleBrand>(), isNull);
        for (final entry in baseline.entries) {
          final style = slot(theme.textTheme, entry.key)!;
          expect(style.fontFamily, isNot(ExampleFonts.sans), reason: entry.key);
          expect(style.letterSpacing, entry.value.$4, reason: entry.key);
          expect(style.fontWeight, entry.value.$2, reason: entry.key);
        }
      }
    });

    test('Example without a tenant font renders Geist re-tracked', () {
      final example = buildAppThemes(_branding()).dark;
      final text = example.textTheme;
      expect(example.extension<ExampleBrand>(), isNotNull);
      for (final entry in baseline.entries) {
        final style = slot(text, entry.key)!;
        expect(style.fontFamily, ExampleFonts.sans, reason: entry.key);
        expect(style.fontSize, entry.value.$1, reason: entry.key);
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: entry.key,
        );
      }
      expect(text.displayLarge!.fontWeight, FontWeight.w700);
      expect(text.displayLarge!.letterSpacing, -0.97);
      expect(text.headlineSmall!.letterSpacing, -0.33);
      expect(text.titleMedium!.letterSpacing, -0.16);
      expect(text.titleSmall!.letterSpacing, 0);
      expect(text.bodyMedium!.letterSpacing, 0);
      expect(text.bodyMedium!.height, closeTo(1.47, 1e-9));
      expect(text.labelLarge!.letterSpacing, 0);
      expect(text.labelMedium!.letterSpacing, .12);
      expect(text.labelSmall!.letterSpacing, .22);
    });

    test('a tenant APP_FONT_FAMILY on Example wins and keeps the shared scale',
        () {
      final text =
          buildAppThemes(_branding(fontFamily: 'Inter')).dark.textTheme;
      expect(text.displayLarge!.fontFamily, 'Inter');
      expect(text.displayLarge!.fontWeight, FontWeight.w800);
      expect(text.displayLarge!.letterSpacing, -0.6);
      expect(text.bodyMedium!.height, 1.42);
    });

    test('mono and label styles read the Example fonts', () {
      expect(ExampleFonts.sans, 'Geist');
      expect(ExampleFonts.mono, 'GeistMono');
      expect(ExampleMotion.exitOf(ExampleMotion.state),
          const Duration(milliseconds: 150));
    });
  });
}

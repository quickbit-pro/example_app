import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_glass_button.dart';
import 'package:mobile_flutter/brands/example/example_tokens.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/shared/theme/app_theme_extensions.dart';
import 'package:mobile_flutter/shared/widgets/brand_asset.dart';

const _design = AppDesign({
  'layout': 'example',
  'assets': {'logo': 'assets/branding/logo.png'},
  'typography': {'monoFontFamily': 'TenantMono', 'scale': 1.2},
  'shape': {'radiusScale': .5},
  'motion': {'durationScale': 2},
  'dark': {
    'paper': '#071B20',
    'surfaceHigh': '#153A40',
    'glassTop': '#17434A',
    'glassBottom': '#123138',
    'fill': '#12A4A0',
    'onFill': '#073E35',
    'accent': '#7BE8C8',
    'ink': '#EDFDF9',
    'borderSubtle': '#395E66',
    'borderEmphasis': '#89CECB',
    'shadowAmbient': '#77071518',
    'shadowLift': '#661FA09B',
  },
});

Widget _host(Widget child, {AppDesign design = _design}) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: [
          const ExampleBrand(),
          AppDesignTheme(design: design, appName: 'Harbor'),
          BrandShapeTheme(scale: design.radiusScale ?? 1),
        ],
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('configured panel, avatar and tokens use customer material',
      (tester) async {
    late BuildContext themedContext;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      themedContext = context;
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        ExampleGlassPanel(child: Text('Balance')),
        ExampleAvatar(name: 'A'),
      ]);
    })));

    final ink = tester.widget<Ink>(find.descendant(
      of: find.byType(ExampleGlassPanel),
      matching: find.byType(Ink),
    ));
    final panel = ink.decoration! as BoxDecoration;
    expect((panel.gradient! as LinearGradient).colors,
        [const Color(0xFF17434A), const Color(0xFF123138)]);
    expect(panel.borderRadius, BorderRadius.circular(9));
    expect(ExampleBorders.subtleSideOf(themedContext).color,
        const Color(0xFF395E66));
    expect(ExampleBorders.emphasisSideOf(themedContext).color,
        const Color(0xFF89CECB));
    expect(ExampleShadows.liftOf(themedContext).single.color,
        const Color(0x661FA09B));
    expect(
        ExampleShadows.glowOf(themedContext, ExampleColors.violet).single.color,
        const Color(0xFF12A4A0).withValues(alpha: .35));

    final avatar = tester.widget<Container>(find.descendant(
      of: find.byType(ExampleAvatar),
      matching: find.byType(Container),
    ));
    expect(
        ((avatar.decoration! as BoxDecoration).gradient! as LinearGradient)
            .colors,
        [const Color(0xFF12A4A0), const Color(0xFF7BE8C8)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configured card has tenant semantics and mono typography',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
      width: 343,
      child: ExampleLivingCard(sweepOnArrival: false),
    )));
    final semantics = tester.widgetList<Semantics>(find.descendant(
      of: find.byType(ExampleLivingCard),
      matching: find.byType(Semantics),
    ));
    expect(semantics.any((value) => value.properties.label == 'Harbor card'),
        isTrue);
    final number = tester.widget<Text>(find.text('••••  ••••  ••••  ••••'));
    expect(number.style!.fontFamily, 'TenantMono');
    expect(number.style!.fontSize, closeTo(188 * .078 * 1.2, .001));
    expect(tester.takeException(), isNull);
  });

  for (final tone in [
    ExampleGlassButtonTone.primary,
    ExampleGlassButtonTone.danger
  ]) {
    testWidgets('dark $tone glass uses ink on its dark material',
        (tester) async {
      await tester.pumpWidget(_host(ExampleGlassButton(
        label: 'Continue',
        tone: tone,
        ground: ExampleGlassGround.atmosphere,
        onPressed: () {},
      )));
      final label = tester.widget<Text>(find.text('Continue'));
      expect(label.style!.color, const Color(0xFFEDFDF9));
      expect(label.style!.color, isNot(const Color(0xFF073E35)));
    });
  }

  testWidgets('configured fallback card decorates with its tenant logo',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox(
      width: 343,
      child: ExamplePaymentCard(),
    )));
    final decoration = find.byKey(const ValueKey('payment-card-brand-artwork'));
    expect(decoration, findsOneWidget);
    final logo = tester.widget<BrandAsset>(find.descendant(
      of: decoration,
      matching: find.byType(BrandAsset),
    ));
    expect(logo.path, 'assets/branding/logo.png');
    expect(logo.size, closeTo(188 * .54, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion configuration scales durations and disables presses',
      (tester) async {
    late Duration scaled;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      scaled = ExampleMotion.of(context, ExampleMotion.press);
      return const SizedBox();
    })));
    expect(scaled, const Duration(milliseconds: 240));

    await tester.pumpWidget(_host(
      ExamplePressable(
        onTap: () {},
        child: const SizedBox(width: 80, height: 40, child: Text('Continue')),
      ),
      design: const AppDesign({
        'motion': {'enabled': false}
      }),
    ));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Continue')));
    await tester.pump();
    final animation = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(animation.duration, Duration.zero);
    expect(animation.scale, 1);
    await gesture.up();
  });
}

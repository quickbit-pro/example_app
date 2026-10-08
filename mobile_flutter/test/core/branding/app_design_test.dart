import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/brands/example/example_typography.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/shared/theme/app_theme_extensions.dart';

AppBranding branding(AppDesign design) => AppBranding(
      appName: 'North Bank',
      brandId: 'north',
      primarySeedHex: '7C5CFF',
      accentSeedHex: '2DD4BF',
      loginBackgroundHex: '',
      themeMode: 'system',
      fontFamily: '',
      logoAsset: 'legacy.png',
      radiusScale: '1',
      supportEmail: '',
      supportPhone: '',
      legalEntity: '',
      design: design,
    );

const design = AppDesign({
  'layout': 'example',
  'light': {
    'paper': '#FAF5EB',
    'surface': '#FFFFFF',
    'fill': '#245449',
    'onFill': '#F8FAFC',
    'accent': '#355D71',
    'success': '#245449',
    'ink': '#172E26',
    'heroStart': '#244B43',
    'heroEnd': '#619383',
  },
  'dark': {
    'paper': '#101E1B',
    'surface': '#1A2C26',
    'fill': '#3C7D68',
    'onFill': '#FFFFFF',
    'accent': '#93BFB0',
    'success': '#87B89F',
    'ink': '#EEF5F0',
    'navigationGlass': '#D9183028',
  },
  'typography': {
    'fontFamily': 'Example Sans',
    'monoFontFamily': 'Example Mono',
    'scale': 1.1
  },
  'shape': {'radiusScale': 0.5},
  'assets': {'logo': 'north.png', 'logoDark': 'north-dark.png'},
});

void main() {
  test('customer identity does not select the responsive layout', () {
    final config = branding(design);
    expect(config.isExampleIdentity, isFalse);
    expect(config.usesExampleLayout, isTrue);
    expect(branding(const AppDesign({'layout': 'generic'})).isExample, isFalse);
    expect(branding(const AppDesign()).isExample, isFalse);
  });

  test('strict color parsing accepts RGB and ARGB, rejecting malformed input',
      () {
    expect(AppDesign.parseColor('#123456'), const Color(0xFF123456));
    expect(AppDesign.parseColor('80123456'), const Color(0x80123456));
    for (final value in ['12345', '1234567', 'red', '##123456']) {
      expect(() => AppDesign.parseColor(value), throwsFormatException);
    }
    expect(() => AppDesign.fromJsonString('[]'), throwsFormatException);
    expect(() => AppDesign.fromJsonString('{"layout":"unknown"}'),
        throwsFormatException);
  });

  test('semantic colors and gradients reach light and dark Material themes',
      () {
    final themes = buildAppThemes(branding(design));
    expect(themes.mode, ThemeMode.system);
    expect(themes.light.scaffoldBackgroundColor, const Color(0xFFFAF5EB));
    expect(themes.dark.scaffoldBackgroundColor, const Color(0xFF101E1B));
    expect(themes.light.colorScheme.primary, const Color(0xFF245449));
    expect(themes.dark.colorScheme.primary, const Color(0xFF3C7D68));
    expect(themes.light.colorScheme.onPrimary, const Color(0xFFF8FAFC));
    expect(themes.dark.navigationBarTheme.backgroundColor,
        const Color(0xD9183028));
    expect(themes.light.extension<FinanceTheme>()!.heroGradient.colors,
        [const Color(0xFF244B43), const Color(0xFF619383)]);
    expect(themes.dark.extension<FinanceTheme>()!.positive,
        const Color(0xFF87B89F));
  });

  testWidgets(
      'widget palette, branding, typography and shapes share one config',
      (tester) async {
    final themes = buildAppThemes(branding(design));
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      theme: themes.dark,
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    final palette = ExamplePalette.of(context);
    expect(palette.ink, const Color(0xFFEEF5F0));
    expect(palette.accentFor(ExampleColors.iris), const Color(0xFF93BFB0));
    expect(palette.accentFor(ExampleColors.success), const Color(0xFF87B89F));
    expect(palette.tint(ExampleColors.success).withValues(alpha: 1),
        const Color(0xFF87B89F));
    expect(AppDesignTheme.nameOf(context), 'North Bank');
    expect(AppDesignTheme.logoOf(context), 'north-dark.png');
    expect(context.brandDesign.isConfigured, isTrue);
    expect(context.brandShape.radius(20), 10);
    expect(Theme.of(context).textTheme.bodyLarge!.fontFamily, 'Example Sans');
    expect(
        Theme.of(context).textTheme.bodyLarge!.fontSize, closeTo(17.6, .001));
    expect(ExampleTextStyles.mono(context).fontFamily, 'Example Mono');
  });

  test('configuration falls back without changing legacy brand palette', () {
    expect(
        identical(ExamplePalette.fromDesign(Brightness.dark, const AppDesign()),
            ExamplePalette.dark),
        isTrue);
    expect(
        identical(ExamplePalette.fromDesign(Brightness.light, const AppDesign()),
            ExamplePalette.light),
        isTrue);
    expect(const AppDesign().isConfigured, isFalse);
    expect(design.logoFor(Brightness.light), 'north.png');
    expect(design.splashBackground(Brightness.dark, fallback: Colors.black),
        Colors.black);
  });

  test('splash duration bounds cannot dismiss before minimum duration', () {
    final config = AppDesign.fromJsonString(
        '{"splash":{"minimumDurationMs":9000,"maximumDurationMs":1000},"loader":{"durationMs":0}}');
    expect(config.splashMinimumDurationMs, 9000);
    expect(config.splashMaximumDurationMs, 9000);
    expect(config.loaderDurationMs, 200);
  });
}

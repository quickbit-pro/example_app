import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/core/widgets/app_states.dart';
import 'package:mobile_flutter/features/assistant/presentation/ask_ai_screen.dart';
import 'package:mobile_flutter/features/dashboard/presentation/widgets/example_balance_chart.dart';
import 'package:mobile_flutter/flavors.dart';

const _tenants = [
  _Tenant(
    name: 'Harbor Money',
    id: 'harbor',
    font: 'Geist',
    scale: .9,
    light: {
      'paper': Color(0xFFF1FAF8),
      'surface': Color(0xFFE1F5F0),
      'fill': Color(0xFF006C65),
      'accent': Color(0xFF006C65),
      'success': Color(0xFF147D55),
      'borderSubtle': Color(0xFF72AEA1),
    },
    dark: {
      'paper': Color(0xFF062824),
      'surface': Color(0xFF103D35),
      'fill': Color(0xFF2AAB95),
      'accent': Color(0xFF65E7D2),
      'success': Color(0xFF91F0B7),
      'borderSubtle': Color(0xFF458E7E),
    },
  ),
  _Tenant(
    name: 'Ember Pay',
    id: 'ember',
    font: 'GeistMono',
    scale: 1.2,
    light: {
      'paper': Color(0xFFFFF6EC),
      'surface': Color(0xFFFFE8CE),
      'fill': Color(0xFFA33F04),
      'accent': Color(0xFFA33F04),
      'success': Color(0xFF52791F),
      'borderSubtle': Color(0xFFB47C45),
    },
    dark: {
      'paper': Color(0xFF2B1508),
      'surface': Color(0xFF452613),
      'fill': Color(0xFFD48133),
      'accent': Color(0xFFFFAF62),
      'success': Color(0xFFD0E68A),
      'borderSubtle': Color(0xFFAA663A),
    },
  ),
];

const _series = ExampleBalanceSeries(
  points: [
    ExampleBalancePoint(balance: 100, change: 0, label: '1 Sep'),
    ExampleBalancePoint(balance: 110, change: 10, label: '2 Sep'),
    ExampleBalancePoint(balance: 140, change: 30, label: '3 Sep'),
  ],
  title: 'Balance history',
  startLabel: '1 Sep',
  endLabel: '3 Sep',
);

void main() {
  for (final tenant in _tenants) {
    for (final brightness in Brightness.values) {
      final label = '${tenant.name} ${brightness.name}';

      testWidgets('$label styles the dashboard chart and empty state',
          (tester) async {
        final branding = tenant.branding;
        final colors = tenant.colors(brightness);
        await tester.pumpWidget(_host(
          branding,
          brightness,
          const Scaffold(
            body: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: ExampleBalanceChart(
                    series: _series,
                    currency: 'USD',
                    animate: false,
                  ),
                ),
                Expanded(
                  child: EmptyState(
                    title: 'No accounts yet',
                    message: 'Your accounts will appear here.',
                  ),
                ),
              ],
            ),
          ),
        ));
        await tester.pump();

        final context = tester.element(find.byType(ExampleBalanceChart));
        final palette = ExamplePalette.of(context);
        expect(branding.isExampleIdentity, isFalse);
        expect(branding.usesExampleLayout, isTrue);
        expect(context.isExampleTheme, isTrue);
        expect(AppDesignTheme.nameOf(context), tenant.name);
        expect(Theme.of(context).brightness, brightness);
        expect(Theme.of(context).scaffoldBackgroundColor, colors['paper']);
        expect(palette.accent, colors['accent']);
        expect(palette.fill, colors['fill']);
        expect(palette.success, colors['success']);
        expect(palette.surface, colors['surface']);

        // Inspect rendered text: inherited theme families must reach actual
        // feature labels as well as the Material theme's typography slots.
        final title = _renderedStyle(tester, 'Balance history');
        final axis = _renderedStyle(tester, '1 Sep');
        expect(title.fontFamily, tenant.font);
        expect(title.fontSize, closeTo(11 * tenant.scale, .001));
        expect(axis.fontFamily, tenant.font);
        expect(axis.fontSize, closeTo(10.5 * tenant.scale, .001));
        expect(_renderedStyle(tester, '+40.0%').color, colors['success']);

        final emptyIcon =
            tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
        expect(emptyIcon.color, colors['accent']);
        final panel = tester
            .widgetList<Container>(find.descendant(
              of: find.byType(EmptyState),
              matching: find.byType(Container),
            ))
            .singleWhere((widget) => widget.constraints?.maxWidth == 440);
        final decoration = panel.decoration! as BoxDecoration;
        expect(decoration.color, colors['surface']);
        expect(
            (decoration.border! as Border).top.color, colors['borderSubtle']);
        expect(
            _renderedStyle(tester, 'No accounts yet').fontFamily, tenant.font);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          '$label identifies its own assistant and retains help behavior',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final branding = tenant.branding;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig(
              flavor: AppFlavor.dev,
              apiBaseUrl: 'https://example.invalid',
              branding: branding,
            )),
          ],
          child: _host(branding, brightness, const AskAiScreen()),
        ));
        await tester.pump();

        expect(
            find.textContaining('${tenant.name} help content'), findsOneWidget);
        expect(find.textContaining('Example help content'), findsNothing);
        expect(_renderedStyle(tester, 'What can I help you with?').fontFamily,
            tenant.font);

        await tester.tap(find.text('How do I change my card limits?'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('${tenant.name} assistant'), findsOneWidget);
        expect(find.text('Example assistant'), findsNothing);
        expect(_renderedStyle(tester, '${tenant.name} assistant').color,
            tenant.colors(brightness)['accent']);
        expect(find.textContaining('tap Limit'), findsOneWidget);
        expect(find.text('Go to Cards'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Widget _host(AppBranding branding, Brightness brightness, Widget home) {
  final themes = buildAppThemes(branding);
  return MaterialApp(
    theme: themes.light,
    darkTheme: themes.dark,
    themeMode:
        brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark,
    home: home,
  );
}

TextStyle _renderedStyle(WidgetTester tester, String text) => tester
    .widget<RichText>(find.descendant(
      of: find.text(text),
      matching: find.byType(RichText),
    ))
    .text
    .style!;

class _Tenant {
  const _Tenant({
    required this.name,
    required this.id,
    required this.font,
    required this.scale,
    required this.light,
    required this.dark,
  });

  final String name;
  final String id;
  final String font;
  final double scale;
  final Map<String, Color> light;
  final Map<String, Color> dark;

  Map<String, Color> colors(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;

  AppBranding get branding => AppBranding(
        appName: name,
        brandId: id,
        primarySeedHex: '7B6CF6',
        accentSeedHex: 'A78BFA',
        loginBackgroundHex: '',
        themeMode: 'system',
        fontFamily: '',
        logoAsset: '',
        radiusScale: '1',
        supportEmail: 'support@example.invalid',
        supportPhone: '',
        legalEntity: name,
        design: AppDesign({
          'layout': 'example',
          'light': _hexColors(light),
          'dark': _hexColors(dark),
          'typography': {'fontFamily': font, 'scale': scale},
          'motion': const {'enabled': false},
        }),
      );
}

Map<String, String> _hexColors(Map<String, Color> colors) => colors.map(
      (key, color) => MapEntry(
          key, '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}'),
    );

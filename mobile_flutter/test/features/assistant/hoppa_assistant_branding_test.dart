import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_api.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_departure.dart';
import 'package:mobile_flutter/features/assistant/presentation/ask_ai_screen.dart';
import 'package:mobile_flutter/flavors.dart';

class _HoppaAssistantApi extends AssistantApi {
  _HoppaAssistantApi({this.enabled = true}) : super(Dio());
  final bool enabled;

  AssistantUsage get allowance => AssistantUsage(
        enabled: enabled,
        dailyLimit: 50,
        used: 1,
        remaining: 49,
        resetsAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        maxMessageCharacters: 1500,
      );

  @override
  Future<AssistantUsage> usage({CancelToken? cancelToken}) async => allowance;

  @override
  Future<AssistantReply> chat({
    required String message,
    required List<AssistantTurn> history,
    String? locale,
    AssistantDeparture? departure,
    CancelToken? cancelToken,
  }) async =>
      AssistantReply(
        reply: 'Here are a few travel options.',
        actions: const [],
        sources: const [],
        webSearchUsed: false,
        usage: allowance,
        refused: false,
      );
}

void main() {
  final config = jsonDecode(File('config/hoppa.json').readAsStringSync())
      as Map<String, dynamic>;
  final branding = AppBranding(
    appName: config['app']['name'] as String,
    brandId: config['app']['id'] as String,
    primarySeedHex: '621A96',
    accentSeedHex: 'C6F24E',
    loginBackgroundHex: '',
    themeMode: 'system',
    fontFamily: '',
    logoAsset: '',
    radiusScale: '1',
    supportEmail: config['app']['supportEmail'] as String,
    supportPhone: '',
    legalEntity: '',
    design: AppDesign(config['design'] as Map<String, dynamic>),
  );

  Future<void> mount(WidgetTester tester, Brightness brightness,
      {bool enabled = true}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final themes = buildAppThemes(branding);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assistantApiProvider
            .overrideWithValue(_HoppaAssistantApi(enabled: enabled)),
        appConfigProvider.overrideWithValue(AppConfig(
          flavor: AppFlavor.prod,
          apiBaseUrl: config['flutterDefines']['API_BASE_URL'] as String,
          branding: branding,
        )),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? themes.dark : themes.light,
        home: const AskAiScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'Hoppa concierge preserves brand and readable bubble ($brightness)',
        (tester) async {
      await mount(tester, brightness);
      await tester.enterText(
          find.byType(TextField), 'Find a quiet hotel in Rome');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hoppa concierge'), findsOneWidget);
      final userText = tester.widget<SelectableText>(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.data == 'Find a quiet hotel in Rome'),
      );
      expect(
          userText.style!.color,
          brightness == Brightness.dark
              ? const Color(0xFF3B1A55)
              : Colors.white);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled Hoppa concierge labels local help with Hoppa',
      (tester) async {
    await mount(tester, Brightness.light, enabled: false);
    expect(find.textContaining('answers from Hoppa help content.'),
        findsOneWidget);
    expect(find.textContaining('Example help content'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

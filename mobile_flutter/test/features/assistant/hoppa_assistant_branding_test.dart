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
import 'package:mobile_flutter/features/assistant/domain/hoppa_assistant_knowledge.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_departure_picker.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_quick_entry.dart';
import 'package:mobile_flutter/features/assistant/presentation/ask_ai_screen.dart';
import 'package:mobile_flutter/flavors.dart';

class _HoppaAssistantApi extends AssistantApi {
  _HoppaAssistantApi({this.enabled = true}) : super(Dio());
  final bool enabled;
  int chatCalls = 0;
  AssistantDeparture? sentDeparture;

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
  }) async {
    chatCalls++;
    sentDeparture = departure;
    return AssistantReply(
      reply: 'I can help you find your way around Hoppa.',
      actions: const [],
      sources: const [],
      webSearchUsed: false,
      usage: allowance,
      refused: false,
    );
  }
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

  late _HoppaAssistantApi api;

  Future<void> mount(WidgetTester tester, Brightness brightness,
      {bool enabled = true, double width = 390}) async {
    api = _HoppaAssistantApi(enabled: enabled);
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final themes = buildAppThemes(branding);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assistantApiProvider.overrideWithValue(api),
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
        'Hoppa Ask AI preserves brand and readable bubble ($brightness)',
        (tester) async {
      await mount(tester, brightness);
      await tester.enterText(find.byType(TextField), 'Show me around Hoppa');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ask AI'), findsNWidgets(2));
      expect(api.chatCalls, 1);
      expect(api.sentDeparture, isNull);
      final userText = tester.widget<SelectableText>(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText && widget.data == 'Show me around Hoppa'),
      );
      expect(
          userText.style!.color,
          brightness == Brightness.dark
              ? const Color(0xFF3B1A55)
              : Colors.white);
      expect(tester.takeException(), isNull);
    });
  }

  for (final enabled in [true, false]) {
    testWidgets('Hoppa help replaces travel UI (enabled=$enabled)',
        (tester) async {
      await mount(tester, Brightness.dark, enabled: enabled, width: 320);
      expect(find.text('How can we help?'), findsOneWidget);
      expect(find.text('Ask about the app…'), findsOneWidget);
      expect(find.text('Your travel concierge'), findsNothing);
      expect(find.text('Find flights'), findsNothing);
      expect(find.text('Find a hotel'), findsNothing);
      expect(find.text('Plan my escape'), findsNothing);
      expect(find.text('Dinner and experiences'), findsNothing);
      expect(find.byType(AssistantDeparturePicker), findsNothing);
      expect(find.byType(AssistantQuickEntry), findsNothing);
      expect(find.text('Dates'), findsNothing);
      expect(find.text('Budget'), findsNothing);
      await tester.ensureVisible(find.text(
          'Help with cards, payments, transfers, verification and account security.'));
      await tester.pump();
      expect(
          find.text(
              'Prices and availability are confirmed on the booking site.'),
          findsNothing);
      final toolbar = find.byKey(const ValueKey('assistant-compact-toolbar'));
      await tester
          .tap(find.descendant(of: toolbar, matching: find.text('Help')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ExpansionTile),
          findsNWidgets(hoppaAssistantTopics.length));
      final support =
          find.widgetWithText(ExpansionTile, 'How do I contact Hoppa support?');
      await tester.ensureVisible(support);
      await tester.tap(support);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(TextButton, 'Open Support tickets'),
          findsOneWidget);
      expect(api.chatCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hoppa answers FAQ in chat (enabled=$enabled)', (tester) async {
      await mount(tester, Brightness.light, enabled: enabled);
      await tester.enterText(find.byType(TextField), 'My payment was declined');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.text(hoppaAssistantTopics
              .firstWhere((t) => t.id == 'declined')
              .answer),
          findsOneWidget);
      expect(find.text('Check my card'), findsOneWidget);
      expect(find.text('Ask AI'), findsNWidgets(2));
      expect(api.chatCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Hoppa starter opens a help answer without an AI request',
      (tester) async {
    await mount(tester, Brightness.dark);
    final starter = find.text('How do I add money to my card?');
    await tester.ensureVisible(starter);
    await tester.tap(starter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(hoppaAssistantTopics.first.answer), findsOneWidget);
    expect(find.text('Go to Cards'), findsOneWidget);
    expect(api.chatCalls, 0);
    expect(tester.takeException(), isNull);
  });

  test('Hoppa FAQ matching uses whole words and exact prompts', () {
    for (final topic in hoppaAssistantTopics) {
      expect(matchHoppaAssistantTopic(topic.prompt)?.id, topic.id);
    }
    expect(matchHoppaAssistantTopic('my card was stolen')?.id, 'freeze');
    expect(matchHoppaAssistantTopic('set my PIN')?.id, 'pin');
    expect(matchHoppaAssistantTopic('shipping'), isNull);
    expect(matchHoppaAssistantTopic('my payment is pending')?.id, 'activity');
    expect(matchHoppaAssistantTopic('auto freeze')?.id, 'auto-freeze');
    expect(matchHoppaAssistantTopic('find a hotel'), isNull);
  });
}

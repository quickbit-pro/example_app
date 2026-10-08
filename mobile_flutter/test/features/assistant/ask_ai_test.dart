import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_api.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_preferences_api.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_preferences.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_history_storage.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_conversation.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_history_sheet.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_speech_recognizer.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_knowledge.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_departure.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_departure_picker.dart';
import 'package:mobile_flutter/features/assistant/presentation/ask_ai_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _branding = AppBranding(
    appName: 'Hoppa',
    brandId: 'hoppa',
    primarySeedHex: '7B6CF6',
    accentSeedHex: 'A78BFA',
    loginBackgroundHex: '',
    themeMode: 'dark',
    fontFamily: '',
    logoAsset: '',
    radiusScale: '1',
    supportEmail: 'support@hoppa.global',
    supportPhone: '',
    legalEntity: '');

AssistantUsage _usage({int used = 0, bool enabled = true}) => AssistantUsage(
    enabled: enabled,
    dailyLimit: 50,
    used: used,
    remaining: 50 - used,
    resetsAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    maxMessageCharacters: 1500);
AssistantReply _reply(
        {String text = 'Here are flight options.',
        int used = 1,
        List<AssistantSource> sources = const [],
        List<AssistantAction> actions = const []}) =>
    AssistantReply(
        reply: text,
        actions: actions,
        sources: sources,
        webSearchUsed: sources.isNotEmpty,
        usage: _usage(used: used),
        refused: false);

class _FakeSpeech implements AssistantSpeechRecognizer {
  int starts = 0;
  int cancels = 0;
  bool available = true;
  Future<bool>? startResult;
  ValueChanged<String>? words;
  VoidCallback? done;
  @override
  Future<bool> start(
      {required ValueChanged<String> onWords,
      required VoidCallback onDone,
      required VoidCallback onError}) async {
    starts++;
    words = onWords;
    done = onDone;
    return startResult == null ? available : await startResult!;
  }

  @override
  Future<void> stop() async {
    done?.call();
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

final _historyOwner = StateProvider<String?>((ref) => 'owner-a');

class _MemoryHistory extends AssistantHistoryStorage {
  final buckets = <String, List<SavedAssistantConversation>>{};
  final saved = <SavedAssistantConversation>[];
  Completer<void>? holdSave;

  @override
  Future<List<SavedAssistantConversation>> load(String owner) async =>
      List.of(buckets[owner] ?? []);

  @override
  Future<bool> save(String owner, SavedAssistantConversation conversation,
      {required bool Function() isCurrent}) async {
    await holdSave?.future;
    if (!isCurrent()) return false;
    saved.add(conversation);
    buckets[owner] = [
      conversation,
      ...?buckets[owner]?.where((entry) => entry.id != conversation.id)
    ];
    return true;
  }

  @override
  Future<bool> delete(String owner, String id,
      {required bool Function() isCurrent}) async {
    if (!isCurrent()) return false;
    buckets[owner] =
        (buckets[owner] ?? []).where((entry) => entry.id != id).toList();
    return true;
  }
}

class _FakePreferencesApi extends AssistantPreferencesApi {
  _FakePreferencesApi() : super(Dio());
  AssistantPreferences value = const AssistantPreferences();
  Future<AssistantPreferences> Function()? answer;
  final calls = <CancelToken?>[];

  @override
  Future<AssistantPreferences> load({CancelToken? cancelToken}) async {
    calls.add(cancelToken);
    return answer == null ? value : await answer!();
  }
}

class _Request {
  const _Request(this.message, this.history, this.locale, this.cancelToken,
      this.departure);
  final String message;
  final List<AssistantTurn> history;
  final String? locale;
  final CancelToken? cancelToken;
  final AssistantDeparture? departure;
}

class _FakeApi extends AssistantApi {
  _FakeApi() : super(Dio());
  AssistantUsage currentUsage = _usage();
  int usageCalls = 0;
  bool failUsage = false;
  final calls = <_Request>[];
  Future<AssistantReply> Function(_Request)? answer;
  @override
  Future<AssistantUsage> usage({CancelToken? cancelToken}) async {
    usageCalls++;
    if (failUsage) throw StateError('offline');
    return currentUsage;
  }

  @override
  Future<AssistantReply> chat(
      {required String message,
      required List<AssistantTurn> history,
      String? locale,
      AssistantDeparture? departure,
      CancelToken? cancelToken}) async {
    final request = _Request(message, history, locale, cancelToken, departure);
    calls.add(request);
    final reply = await (answer?.call(request) ?? Future.value(_reply()));
    currentUsage = reply.usage;
    return reply;
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _pumpApp(WidgetTester tester, _FakeApi api,
    {bool light = false,
    double width = 390,
    Future<bool> Function(Uri)? launcher,
    _FakeSpeech? speech,
    _MemoryHistory? history,
    _FakePreferencesApi? preferences,
    Widget? home}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final themes = buildAppThemes(_branding);
  final theme = light ? themes.light : themes.dark;
  await tester.pumpWidget(ProviderScope(
      overrides: [
        assistantApiProvider.overrideWithValue(api),
        assistantPreferencesApiProvider
            .overrideWithValue(preferences ?? _FakePreferencesApi()),
        assistantHistoryOwnerProvider.overrideWith(
            (ref) => history == null ? null : ref.watch(_historyOwner)),
        if (history != null)
          assistantHistoryStorageProvider.overrideWithValue(history),
        if (speech != null)
          assistantSpeechRecognizerProvider.overrideWithValue(() => speech),
        if (launcher != null)
          assistantLinkLauncherProvider.overrideWithValue(launcher),
        appConfigProvider.overrideWithValue(const AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'https://example.invalid',
            branding: _branding)),
      ],
      child: MaterialApp(
          theme: theme,
          darkTheme: theme,
          themeMode: light ? ThemeMode.light : ThemeMode.dark,
          home: home ?? const AskAiScreen())));
  await _flush(tester);
}

Finder get _send => find.descendant(
    of: find.byTooltip('Send question'), matching: find.byType(FilledButton));
Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(_send);
  await _flush(tester);
}

void main() {
  testWidgets(
      'quick dates and budget form a draft and use one request only on Send',
      (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api);
    await tester.tap(find.byKey(const ValueKey('assistant-budget')));
    await _flush(tester);
    await tester.tap(find.text('EUR 500'));
    await tester.tap(find.text('Use budget'));
    await _flush(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-dates')));
    await _flush(tester);
    final picker = tester
        .widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog));
    final start = picker.firstDate.add(const Duration(days: 7));
    final end = start.add(const Duration(days: 3));
    Navigator.of(tester.element(find.byType(DateRangePickerDialog)))
        .pop(DateTimeRange(start: start, end: end));
    await _flush(tester);
    expect(api.calls, isEmpty);
    expect(find.text('50/50'), findsOneWidget);
    final draft = tester
        .widget<TextField>(find.byKey(const ValueKey('assistant-message')))
        .controller!
        .text;
    expect(draft, contains('Travel dates:'));
    expect(draft, contains('Maximum budget: EUR 500 total for the trip.'));
    await tester.tap(_send);
    await _flush(tester);
    expect(api.calls.single.message, draft);
    expect(find.text('49/50'), findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);
  });

  testWidgets('account switch closes quick-entry dialog and clears its draft',
      (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api);
    await tester.tap(find.byKey(const ValueKey('assistant-budget')));
    await _flush(tester);
    await tester.tap(find.text('EUR 500'));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AskAiScreen)));
    container.read(authSessionGenerationProvider.notifier).state++;
    await _flush(tester);
    await _flush(tester);
    expect(find.text('Use budget'), findsNothing);
    expect(api.calls, isEmpty);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assistant-message')))
            .controller!
            .text,
        isEmpty);
  });
  testWidgets(
      'editing a failed request replaces budget once and new chat clears it',
      (tester) async {
    final api = _FakeApi()..answer = (_) async => throw StateError('offline');
    await _pumpApp(tester, api);
    await tester.tap(find.byKey(const ValueKey('assistant-budget')));
    await _flush(tester);
    await tester.tap(find.text('EUR 500'));
    await tester.tap(find.text('Use budget'));
    await _flush(tester);
    await tester.tap(_send);
    await _flush(tester);
    await tester.ensureVisible(find.text('Edit question'));
    await _flush(tester);
    await tester.tap(find.text('Edit question'));
    await _flush(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-budget')));
    await _flush(tester);
    await tester.tap(find.text('EUR 1000'));
    await tester.tap(find.text('Use budget'));
    await _flush(tester);
    final draft = tester
        .widget<TextField>(find.byKey(const ValueKey('assistant-message')))
        .controller!
        .text;
    expect(draft, 'Maximum budget: EUR 1000 total for the trip.');
    expect(api.calls, hasLength(1));
    await tester.tap(find.text('New chat'));
    await _flush(tester);
    expect(find.text('Budget'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assistant-message')))
            .controller!
            .text,
        isEmpty);
  });

  testWidgets(
      'quick details never truncate an existing maximum-length question',
      (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api);
    final question = List.filled(1500, 'a').join();
    await tester.enterText(
        find.byKey(const ValueKey('assistant-message')), question);
    await tester.tap(find.byKey(const ValueKey('assistant-budget')));
    await _flush(tester);
    await tester.tap(find.text('EUR 500'));
    await tester.tap(find.text('Use budget'));
    await _flush(tester);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('assistant-message')))
            .controller!
            .text,
        question);
    expect(find.text('Shorten your question before adding trip details.'),
        findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  test('questions match the most relevant help topic', () {
    expect(
        matchAssistantTopic('How can I send money to my friend?')!.id, 'send');
    expect(matchAssistantTopic('change my daily spending limit')!.id, 'limits');
    expect(matchAssistantTopic('my card was stolen')!.id, 'freeze');
    expect(matchAssistantTopic('turn on two-factor')!.id, 'security');
    expect(matchAssistantTopic('what is the weather'), isNull);
  });
  for (final light in [false, true]) {
    testWidgets(
        'concierge suggestion and reply fit narrow screen (light=$light)',
        (tester) async {
      final api = _FakeApi();
      await _pumpApp(tester, api, light: light, width: 320);
      expect(find.text('Your travel concierge'), findsOneWidget);
      expect(
          find.text('Do not share card numbers, passwords or security codes.'),
          findsNothing);
      expect(find.text('50/50'), findsOneWidget);
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 1500);
      await tester.ensureVisible(find.text('Find flights'));
      await _flush(tester);
      await tester.tap(find.text('Find flights'));
      await _flush(tester);
      expect(api.calls, isEmpty);
      expect(find.text('50/50'), findsOneWidget);
      final draft =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(draft, contains('trip budget'));
      await tester.tap(_send);
      await _flush(tester);
      expect(api.calls.single.message, draft);
      expect(api.calls.single.history, isEmpty);
      expect(api.calls.single.locale, 'en');
      expect(find.text('Here are flight options.'), findsOneWidget);
      expect(find.text('49/50'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'compact footer keeps details accessible without consuming chat height',
      (tester) async {
    // Use real font metrics for this height assertion; the test Ahem font wraps the hint.
    await (FontLoader('Geist')
          ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf')))
        .load();
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf')))
        .load();
    final api = _FakeApi();
    await _pumpApp(tester, api, width: 390);
    expect(find.text('0 / 1500'), findsNothing);
    expect(find.textContaining('Resets '), findsNothing);
    final toolbar =
        tester.getRect(find.byKey(const ValueKey('assistant-compact-toolbar')));
    final composer = tester.getRect(find.byType(TextField));
    expect(composer.bottom - toolbar.top, lessThan(120));
    await tester.tap(find.byTooltip('Ask AI information'));
    await _flush(tester);
    expect(find.textContaining('Resets '), findsOneWidget);
    expect(find.text('Do not share card numbers, passwords or security codes.'),
        findsOneWidget);
    expect(
        find.text(
            'Voice uses your device or browser speech service. Review the text before sending.'),
        findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(find.text('Close'));
    await _flush(tester);
    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('onboarding city and range personalise editable starter drafts',
      (tester) async {
    final api = _FakeApi();
    final preferences = _FakePreferencesApi()
      ..value = const AssistantPreferences(
          city: 'Ljubljana', countryCode: 'SI', monthlyVolume: '0-1000');
    await _pumpApp(tester, api, preferences: preferences, width: 320);
    expect(find.text('Departing from Ljubljana, SI'), findsOneWidget);
    expect(find.text('Ljubljana, SI · Value-focused ideas'), findsOneWidget);
    await tester.ensureVisible(find.text('Find flights'));
    await _flush(tester);
    await tester.tap(find.text('Find flights'));
    await _flush(tester);
    final draft =
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(draft, contains('low-cost flights from Ljubljana'));
    expect(draft, isNot(contains('0-1000')));
    expect(api.calls, isEmpty);
    await tester.enterText(
        find.byType(TextField), '$draft In October, for two.');
    await tester.tap(_send);
    await _flush(tester);
    expect(api.calls.single.departure?.city, 'Ljubljana');
    expect(api.calls.single.message, endsWith('In October, for two.'));
    expect(api.calls.single.message, isNot(contains('0-1000')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final manual in [const AssistantDeparture(city: 'Vienna'), null]) {
    testWidgets(
        'late onboarding city does not replace manual departure $manual',
        (tester) async {
      final response = Completer<AssistantPreferences>();
      final preferences = _FakePreferencesApi()..answer = () => response.future;
      final api = _FakeApi();
      await _pumpApp(tester, api, preferences: preferences);
      tester
          .widget<AssistantDeparturePicker>(
              find.byType(AssistantDeparturePicker))
          .onChanged(manual);
      response.complete(const AssistantPreferences(
          city: 'Ljubljana', countryCode: 'SI', monthlyVolume: '1001-5000'));
      await _flush(tester);
      expect(
          tester
              .widget<AssistantDeparturePicker>(
                  find.byType(AssistantDeparturePicker))
              .departure
              ?.city,
          manual?.city);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('late onboarding preferences preserve a restored chat departure',
      (tester) async {
    final response = Completer<AssistantPreferences>();
    final preferences = _FakePreferencesApi()..answer = () => response.future;
    final history = _MemoryHistory();
    history.buckets['owner-a'] = [
      SavedAssistantConversation(
        id: 'saved-trip',
        title: 'Weekend from Paris',
        updatedAt: DateTime.now(),
        departure: const AssistantDeparture(city: 'Paris', countryCode: 'FR'),
        turns: [
          const SavedAssistantTurn(role: 'user', text: 'Weekend from Paris'),
          SavedAssistantTurn(
              role: 'assistant',
              text: 'Which dates?',
              reply: _reply(text: 'Which dates?')),
        ],
      )
    ];
    final api = _FakeApi();
    await _pumpApp(tester, api, preferences: preferences, history: history);
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    await tester.tap(find.text('Weekend from Paris'));
    await _flush(tester);
    response.complete(
        const AssistantPreferences(city: 'Ljubljana', countryCode: 'SI'));
    await _flush(tester);
    expect(find.text('Departing from Paris, FR'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('account switch cancels and discards old onboarding preferences',
      (tester) async {
    final first = Completer<AssistantPreferences>();
    final second = Completer<AssistantPreferences>();
    var load = 0;
    final preferences = _FakePreferencesApi()
      ..answer = () => ++load == 1 ? first.future : second.future;
    final api = _FakeApi();
    await _pumpApp(tester, api, preferences: preferences);
    final scope =
        ProviderScope.containerOf(tester.element(find.byType(AskAiScreen)));
    scope.read(authSessionGenerationProvider.notifier).state++;
    await _flush(tester);
    expect(preferences.calls.first!.isCancelled, isTrue);
    second.complete(
        const AssistantPreferences(city: 'Vienna', countryCode: 'AT'));
    await _flush(tester);
    first.complete(const AssistantPreferences(
        city: 'Ljubljana', monthlyVolume: '100001+'));
    await _flush(tester);
    expect(find.text('Departing from Vienna, AT'), findsOneWidget);
    expect(find.textContaining('Special stays and experiences'), findsNothing);
    expect(find.textContaining('Ljubljana'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final verification in ['planning', 'web_sources']) {
    testWidgets(
        'structured $verification answer uses cards and one status note',
        (tester) async {
      final opened = <Uri>[];
      final api = _FakeApi()
        ..answer = (_) async => AssistantReply(
              reply: 'Compatibility reply should be hidden',
              actions: const [],
              sources: verification == 'planning'
                  ? const []
                  : const [
                      AssistantSource(
                          title: 'Hotel information',
                          url: 'https://www.booking.com/hotel/')
                    ],
              webSearchUsed: verification == 'web_sources',
              usage: _usage(used: 1),
              refused: false,
              verification: verification,
              answer: AssistantStructuredAnswer(
                title: 'A quiet Rome weekend',
                summary: 'One stay to consider.',
                options: [
                  AssistantAnswerOption(
                      title: 'Garden retreat',
                      highlights: const ['Quiet courtyard'],
                      source: verification == 'web_sources'
                          ? const AssistantSource(
                              title: 'Hotel information',
                              url: 'https://www.booking.com/hotel/')
                          : null)
                ],
              ),
            );
      await _pumpApp(tester, api, width: 320, launcher: (uri) async {
        opened.add(uri);
        return true;
      });
      await _ask(tester, 'Find a quiet hotel in Rome');
      expect(find.text('Garden retreat'), findsOneWidget);
      expect(find.text('Compatibility reply should be hidden'), findsNothing);
      if (verification == 'web_sources') {
        await tester.ensureVisible(find.text('View website'));
        await _flush(tester);
        await tester.tap(find.text('View website'));
        await _flush(tester);
        expect(opened.single.toString(), 'https://www.booking.com/hotel/');
      } else {
        expect(find.text('View website'), findsNothing);
        expect(opened, isEmpty);
      }
      expect(
          find.text(verification == 'planning'
              ? 'Planning suggestions only. Current prices and availability have not been verified.'
              : 'Found on the web. Confirm final prices and availability with the provider.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'follow-up sends prior turns and new conversation preserves quota',
      (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api);
    await _ask(tester, 'Find a hotel in Rome');
    api.answer = (_) async => _reply(text: 'Here are quieter hotels.', used: 2);
    await _ask(tester, 'Somewhere quieter please');
    expect(
        api.calls.last.history.map((turn) => turn.role), ['user', 'assistant']);
    expect(api.calls.last.history.map((turn) => turn.content),
        ['Find a hotel in Rome', 'Here are flight options.']);
    await tester.tap(find.byTooltip('New conversation'));
    await _flush(tester);
    expect(find.text('Here are quieter hotels.'), findsNothing);
    expect(find.text('48/50'), findsOneWidget);
    expect(api.usageCalls, 2);
    await _ask(tester, 'Flights to Paris');
    expect(api.calls.last.history, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('daily quota disables typing and suggestions', (tester) async {
    final api = _FakeApi()..currentUsage = _usage(used: 50);
    await _pumpApp(tester, api);
    expect(find.text('0/50'), findsOneWidget);
    expect(find.text('Daily allowance used. Come back after the reset.'),
        findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.ensureVisible(find.text('Find flights'));
    await _flush(tester);
    await tester.tap(find.text('Find flights'));
    await _flush(tester);
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed request retries explicitly without duplicate question',
      (tester) async {
    final api = _FakeApi();
    api.answer = (_) async {
      api.currentUsage = _usage(used: 1);
      throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout);
    };
    await _pumpApp(tester, api);
    await _ask(tester, 'Find flights to Rome');
    expect(api.calls, hasLength(1));
    expect(find.text('Find flights to Rome'), findsOneWidget);
    expect(
        find.text(
            'Your answer could not be loaded. Try again or edit your question.'),
        findsOneWidget);
    expect(find.text('49/50'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    api.answer = (_) async => _reply(used: 2);
    await tester.tap(find.text('Try again'));
    await _flush(tester);
    expect(api.calls, hasLength(2));
    expect(api.calls.last.history, isEmpty);
    expect(api.calls.last.message, api.calls.first.message);
    expect(find.text('Find flights to Rome'), findsOneWidget);
    expect(find.text('Here are flight options.'), findsOneWidget);
    expect(find.text('48/50'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed request can be edited without including it in history',
      (tester) async {
    final api = _FakeApi()..answer = (_) async => throw StateError('offline');
    await _pumpApp(tester, api);
    await _ask(tester, 'Flights');
    await tester.tap(find.text('Edit question'));
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Flights');
    api.answer = (_) async => _reply();
    await _ask(tester, 'Flights to Paris');
    expect(api.calls.last.history, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('429 refreshes actual quota and blocks retries when exhausted',
      (tester) async {
    final api = _FakeApi()..currentUsage = _usage(used: 49);
    api.answer = (_) async {
      api.currentUsage = _usage(used: 50);
      throw DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: 429,
              data: {'code': 'assistant.daily_limit'}));
    };
    await _pumpApp(tester, api);
    await _ask(tester, 'Flights to Paris');
    expect(api.calls, hasLength(1));
    expect(find.text('0/50'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('safe sources/actions open externally; prose/unsafe links do not',
      (tester) async {
    final opened = <Uri>[];
    final api = _FakeApi()
      ..answer = (_) async => _reply(
              text:
                  'Try [this text](https://evil.invalid) or use a source below.',
              sources: [
                const AssistantSource(
                    title:
                        'A very long official airline source title with flight information',
                    url: 'https://www.lufthansa.com/flight-search'),
                const AssistantSource(
                    title: 'Unsafe source', url: 'http://127.0.0.1/admin'),
              ],
              actions: [
                const AssistantAction(
                    label: 'Search flights',
                    url: 'https://www.google.com/travel/flights?q=Rome',
                    kind: 'flights'),
                const AssistantAction(
                    label: 'Unsafe action',
                    url: 'javascript:alert(1)',
                    kind: 'maps'),
              ]);
    await _pumpApp(tester, api, width: 320, launcher: (uri) async {
      opened.add(uri);
      return true;
    });
    await _ask(tester, 'Flights to Rome');
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Unsafe source'), findsNothing);
    expect(find.text('Unsafe action'), findsNothing);
    expect(find.byType(OutlinedButton), findsNWidgets(2));
    await tester.ensureVisible(find.text('Search flights'));
    await _flush(tester);
    await tester.tap(find.text('Search flights'));
    await _flush(tester);
    expect(opened.single.host, 'www.google.com');
    expect(
        find.text('Prices and availability are confirmed on the booking site.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('only explicit disabled status shows local app help',
      (tester) async {
    final api = _FakeApi()..currentUsage = _usage(enabled: false);
    await _pumpApp(tester, api);
    expect(find.text('App help'), findsOneWidget);
    await tester.ensureVisible(find.text('Help'));
    await _flush(tester);
    await tester.tap(find.text('Help'));
    await _flush(tester);
    await tester.tap(find.text('How do I change my card limits?'));
    await _flush(tester);
    expect(find.textContaining('tap Limit'), findsOneWidget);
    expect(find.text('Go to Cards'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(find.textContaining('left today'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Help opens local options even after the AI quota is exhausted',
      (tester) async {
    final api = _FakeApi()..currentUsage = _usage(used: 50);
    await _pumpApp(tester, api, width: 320);
    expect(find.text('How do I change my card limits?'), findsNothing);
    await tester.ensureVisible(find.text('Help'));
    await _flush(tester);
    await tester.tap(find.text('Help'));
    await _flush(tester);
    await tester.tap(find.text('How do I change my card limits?'));
    await _flush(tester);
    expect(find.textContaining('tap Limit'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(find.text('Close'));
    await _flush(tester);
    expect(find.text('How do I change my card limits?'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('usage failure does not silently use app help and recovers',
      (tester) async {
    final api = _FakeApi()..failUsage = true;
    await _pumpApp(tester, api);
    expect(find.text('App help'), findsNothing);
    expect(find.text('Could not check your daily allowance. Please try again.'),
        findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    api.failUsage = false;
    await tester.tap(find.text('Try again'));
    await _flush(tester);
    expect(find.text('Your travel concierge'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'new conversation cancels pending request and discards late reply',
      (tester) async {
    final response = Completer<AssistantReply>();
    final api = _FakeApi()..answer = (_) => response.future;
    await _pumpApp(tester, api);
    await _ask(tester, 'Find flights to Rome');
    expect(find.text('Planning your answer…'), findsOneWidget);
    await tester.tap(find.byTooltip('New conversation'));
    await _flush(tester);
    expect(api.calls.single.cancelToken!.isCancelled, isTrue);
    response.complete(_reply(text: 'Old answer'));
    await _flush(tester);
    expect(find.text('Old answer'), findsNothing);
    expect(find.text('Your travel concierge'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('account change clears conversation and cancels old request',
      (tester) async {
    final response = Completer<AssistantReply>();
    final api = _FakeApi()..answer = (_) => response.future;
    await _pumpApp(tester, api);
    await _ask(tester, 'My private trip');
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AskAiScreen)));
    container.read(authSessionGenerationProvider.notifier).state++;
    await _flush(tester);
    expect(api.calls.single.cancelToken!.isCancelled, isTrue);
    response.complete(_reply(text: 'Previous account answer'));
    await _flush(tester);
    expect(find.text('My private trip'), findsNothing);
    expect(find.text('Previous account answer'), findsNothing);
    expect(api.usageCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('disposing screen cancels active request', (tester) async {
    final response = Completer<AssistantReply>();
    final api = _FakeApi()..answer = (_) => response.future;
    await _pumpApp(tester, api);
    await _ask(tester, 'Flights to Paris');
    await tester.pumpWidget(const SizedBox());
    expect(api.calls.single.cancelToken!.isCancelled, isTrue);
    response.complete(_reply());
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'UTF-16 message limit truncates pasted emoji without splitting pairs',
      (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api);
    await tester.enterText(find.byType(TextField), '😀' * 1000);
    await tester.pump();
    final text =
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(text.length, 1500);
    expect(text.runes.length, 750);
    expect(find.text('1500 / 1500'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'voice drafts require review and explicit send, with no startup permission request',
      (tester) async {
    final api = _FakeApi();
    final speech = _FakeSpeech();
    await _pumpApp(tester, api, speech: speech, width: 320);
    expect(speech.starts, 0);
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    expect(speech.starts, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    speech.words!('Find flights to Rome');
    await _flush(tester);
    expect(api.calls, isEmpty);
    expect(tester.widget<FilledButton>(_send).onPressed, isNull);
    await tester.tap(find.byTooltip('Stop voice input'));
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(find.text('Review your text, then tap send.'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.enterText(
        find.byType(TextField), 'Find flights to Rome for two');
    await tester.pump();
    await tester.tap(_send);
    await _flush(tester);
    expect(api.calls.single.message, 'Find flights to Rome for two');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'unsupported speech leaves typing available and sends no requests',
      (tester) async {
    final api = _FakeApi();
    final speech = _FakeSpeech()..available = false;
    await _pumpApp(tester, api, speech: speech);
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    expect(
        find.text(
            'Voice input is unavailable. You can type or use your keyboard microphone.'),
        findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'account change and background cancel voice and ignore late transcript',
      (tester) async {
    final api = _FakeApi();
    final speech = _FakeSpeech();
    await _pumpApp(tester, api, speech: speech);
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    final previousWords = speech.words!;
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AskAiScreen)));
    container.read(authSessionGenerationProvider.notifier).state++;
    await _flush(tester);
    previousWords('Private old trip');
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(speech.cancels, greaterThan(0));
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    final backgroundWords = speech.words!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    backgroundWords('Unexpected late words');
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(api.calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new conversation and disposal release voice', (tester) async {
    final api = _FakeApi();
    final speech = _FakeSpeech();
    await _pumpApp(tester, api, speech: speech);
    await _ask(tester, 'Flights to Rome');
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    final words = speech.words!;
    await tester.tap(find.byTooltip('New conversation'));
    await _flush(tester);
    words('Old follow-up');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    final priorCancels = speech.cancels;
    await tester.pumpWidget(const SizedBox());
    expect(speech.cancels, greaterThan(priorCancels));
    speech.words!('After disposal');
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'permission sheet keeps first mic tap but background cancels startup',
      (tester) async {
    final api = _FakeApi();
    final permission = Completer<bool>();
    final speech = _FakeSpeech()..startResult = permission.future;
    await _pumpApp(tester, api, speech: speech);
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _flush(tester);
    expect(speech.cancels, 0);
    permission.complete(true);
    await _flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    speech.words!('Flight to London');
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Flight to London');
    await tester.tap(find.byTooltip('Stop voice input'));
    await _flush(tester);
    final secondPermission = Completer<bool>();
    speech.startResult = secondPermission.future;
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    final lateWords = speech.words!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    secondPermission.complete(true);
    lateWords('Unsafe background transcript');
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Flight to London');
    expect(api.calls, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'sensitive input rejection asks for an edit and keeps rejected text out of history',
      (tester) async {
    final api = _FakeApi();
    api.answer = (_) async => throw DioException(
          requestOptions: RequestOptions(),
          response: Response(
              requestOptions: RequestOptions(),
              statusCode: 400,
              data: {'code': 'assistant.sensitive_input'}),
        );
    await _pumpApp(tester, api, width: 320);
    await _ask(tester, 'My password is sample-secret');
    expect(
        find.text(
            'Remove card numbers, bank account details, passwords or security codes before sending. Start a new conversation if they appeared in an earlier message.'),
        findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(
        find.text('Each attempt uses one request from your daily allowance.'),
        findsNothing);
    expect(find.text('50/50'), findsOneWidget);
    expect(api.calls, hasLength(1));
    await tester.ensureVisible(find.text('Edit question'));
    await _flush(tester);
    await tester.tap(find.text('Edit question'));
    await _flush(tester);
    api.answer = (_) async => _reply();
    await _ask(tester, 'Find flights to Rome');
    expect(api.calls.last.message, 'Find flights to Rome');
    expect(api.calls.last.history, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('source shows complete destination host on a narrow screen',
      (tester) async {
    const host = 'booking.com.this-is-a-very-long-subdomain.attacker.tld';
    final api = _FakeApi()
      ..answer = (_) async => _reply(sources: [
            const AssistantSource(
                title: 'Booking.com', url: 'https://$host/hotel'),
          ]);
    await _pumpApp(tester, api, width: 320);
    await _ask(tester, 'Find hotels in Rome');
    final hostText = tester.widget<Text>(find.text(host));
    expect(hostText.maxLines, isNull);
    expect(hostText.overflow, isNot(TextOverflow.ellipsis));
    expect(hostText.softWrap, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('local app help is not uploaded after concierge becomes enabled',
      (tester) async {
    final api = _FakeApi()..currentUsage = _usage(enabled: false);
    await _pumpApp(tester, api);
    await _ask(tester, 'How do I change my card limits?');
    expect(api.calls, isEmpty);
    api.currentUsage = _usage();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    await _ask(tester, 'Find flights to Rome');
    expect(api.calls.single.history, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'departure is separate context, persists for new chat and clears for another account',
      (tester) async {
    const departure = AssistantDeparture(
        city: 'Ljubljana', countryCode: 'SI', airportCode: 'LJU');
    final api = _FakeApi();
    await _pumpApp(tester, api, width: 320);
    tester
        .widget<AssistantDeparturePicker>(find.byType(AssistantDeparturePicker))
        .onChanged(departure);
    await _flush(tester);
    await _ask(tester, 'Find flights to London');
    expect(api.calls.single.departure?.city, 'Ljubljana');
    expect(api.calls.single.departure?.countryCode, 'SI');
    expect(api.calls.single.departure?.airportCode, 'LJU');
    expect(api.calls.single.message, 'Find flights to London');
    expect(api.calls.single.history, isEmpty);
    await tester.tap(find.byTooltip('New conversation'));
    await _flush(tester);
    final picker = tester.widget<AssistantDeparturePicker>(
        find.byType(AssistantDeparturePicker));
    expect(picker.departure?.city, 'Ljubljana');
    final staleChange = picker.onChanged;
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AskAiScreen)));
    container.read(authSessionGenerationProvider.notifier).state++;
    await _flush(tester);
    staleChange(departure);
    await _flush(tester);
    expect(
        tester
            .widget<AssistantDeparturePicker>(
                find.byType(AssistantDeparturePicker))
            .departure,
        isNull);
    await _ask(tester, 'Find flights to Rome');
    expect(api.calls.last.departure, isNull);
    expect(api.calls.last.history, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'retry keeps submitted departure while an edited request can change it',
      (tester) async {
    const origin = AssistantDeparture(city: 'Ljubljana', countryCode: 'SI');
    const changed = AssistantDeparture(city: 'Vienna', countryCode: 'AT');
    final response = Completer<AssistantReply>();
    final api = _FakeApi()..answer = (_) => response.future;
    await _pumpApp(tester, api);
    tester
        .widget<AssistantDeparturePicker>(find.byType(AssistantDeparturePicker))
        .onChanged(origin);
    await _flush(tester);
    await _ask(tester, 'Find flights to London');
    final pendingPicker = tester.widget<AssistantDeparturePicker>(
        find.byType(AssistantDeparturePicker));
    expect(pendingPicker.enabled, isFalse);
    pendingPicker.onChanged(changed);
    response.completeError(StateError('provider unavailable'));
    await _flush(tester);
    api.answer = (_) async => _reply();
    await tester.tap(find.text('Try again'));
    await _flush(tester);
    expect(api.calls.last.departure?.city, 'Ljubljana');
    tester
        .widget<AssistantDeparturePicker>(find.byType(AssistantDeparturePicker))
        .onChanged(changed);
    await _flush(tester);
    await _ask(tester, 'What about Paris?');
    expect(api.calls.last.departure?.city, 'Vienna');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'saved history restores replies and departure without replaying chat or saved quota',
      (tester) async {
    final history = _MemoryHistory();
    final api = _FakeApi();
    await _pumpApp(tester, api, history: history, width: 320);
    tester
        .widget<AssistantDeparturePicker>(find.byType(AssistantDeparturePicker))
        .onChanged(
            const AssistantDeparture(city: 'Ljubljana', countryCode: 'SI'));
    await _ask(tester, 'Find flights to London');
    expect(history.saved.single.turns.map((turn) => turn.role),
        ['user', 'assistant']);
    await tester.tap(find.byTooltip('New conversation'));
    await _flush(tester);
    api.currentUsage = _usage(used: 17);
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    expect(find.byType(AssistantHistorySheet), findsOneWidget);
    expect(
        find.text('Saved on this device for 7 days. Up to 20 conversations.'),
        findsOneWidget);
    await tester.tap(find.text('Find flights to London'));
    await _flush(tester);
    expect(api.calls, hasLength(1));
    expect(find.text('Here are flight options.'), findsOneWidget);
    expect(find.text('33/50'), findsOneWidget);
    expect(
        tester
            .widget<AssistantDeparturePicker>(
                find.byType(AssistantDeparturePicker))
            .departure
            ?.city,
        'Ljubljana');
    await _ask(tester, 'Make it two people');
    expect(api.calls.last.history.map((turn) => turn.content),
        ['Find flights to London', 'Here are flight options.']);
    expect(history.buckets['owner-a'], hasLength(1));
    expect(history.buckets['owner-a']!.single.turns, hasLength(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed sensitive questions and drafts are never saved',
      (tester) async {
    final history = _MemoryHistory();
    final api = _FakeApi();
    await _pumpApp(tester, api, history: history);
    await tester.enterText(find.byType(TextField), 'An unsent private draft');
    await _flush(tester);
    expect(history.saved, isEmpty);
    await _ask(tester, 'Find flights to London');
    api.answer = (_) async => throw DioException(
        requestOptions: RequestOptions(),
        response: Response(
            requestOptions: RequestOptions(),
            statusCode: 400,
            data: {'code': 'assistant.sensitive_input'}));
    await _ask(tester, 'My password is secret');
    expect(history.saved, hasLength(1));
    expect(history.saved.single.turns, hasLength(2));
    expect(history.saved.single.turns.map((turn) => turn.text).join(' '),
        isNot(contains('secret')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'deleting active history cancels pending answer and prevents resurrection',
      (tester) async {
    final history = _MemoryHistory();
    final api = _FakeApi();
    await _pumpApp(tester, api, history: history);
    await _ask(tester, 'Find flights to London');
    final response = Completer<AssistantReply>();
    api.answer = (_) => response.future;
    await _ask(tester, 'What about tomorrow?');
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    await tester.tap(find.byTooltip('Delete conversation'));
    await _flush(tester);
    expect(api.calls.last.cancelToken!.isCancelled, isTrue);
    response.complete(_reply(text: 'Late answer'));
    await _flush(tester);
    expect(history.buckets['owner-a'], isEmpty);
    expect(find.text('No saved conversations yet.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await _flush(tester);
    expect(find.text('Late answer'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('account switch dismisses history and rejects queued writes',
      (tester) async {
    final history = _MemoryHistory()..holdSave = Completer<void>();
    final api = _FakeApi();
    await _pumpApp(tester, api, history: history);
    await _ask(tester, 'Private first-account trip');
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AskAiScreen)));
    container.read(_historyOwner.notifier).state = 'owner-b';
    container.read(authSessionGenerationProvider.notifier).state++;
    await _flush(tester);
    history.holdSave!.complete();
    await _flush(tester);
    expect(find.byType(AssistantHistorySheet), findsNothing);
    expect(find.text('Private first-account trip'), findsNothing);
    expect(history.saved, isEmpty);
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    expect(find.text('No saved conversations yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Back returns to previous screen and completed history can finish saving',
      (tester) async {
    final history = _MemoryHistory()..holdSave = Completer<void>();
    final api = _FakeApi();
    await _pumpApp(tester, api,
        history: history,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const AskAiScreen())),
                    child: const Text('Open concierge')))));
    await tester.tap(find.text('Open concierge'));
    await _flush(tester);
    await _ask(tester, 'Find flights to London');
    await tester.tap(find.byTooltip('Back'));
    await _flush(tester);
    expect(find.text('Open concierge'), findsOneWidget);
    history.holdSave!.complete();
    await _flush(tester);
    expect(history.saved, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening history cancels dictation and ignores late words',
      (tester) async {
    final api = _FakeApi();
    final speech = _FakeSpeech();
    await _pumpApp(tester, api, history: _MemoryHistory(), speech: speech);
    await tester.tap(find.byTooltip('Dictate your request'));
    await _flush(tester);
    final words = speech.words!;
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    words('Old dictated question');
    await _flush(tester);
    await tester.tap(find.byTooltip('Close'));
    await _flush(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(speech.cancels, greaterThan(0));
    expect(api.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'opening history freezes completed turns and rejects a late in-flight answer',
      (tester) async {
    final history = _MemoryHistory();
    final api = _FakeApi();
    await _pumpApp(tester, api, history: history);
    await _ask(tester, 'Find flights to London');
    final response = Completer<AssistantReply>();
    api.answer = (_) => response.future;
    await _ask(tester, 'First follow-up');
    await tester.tap(find.byTooltip('Conversation history'));
    await _flush(tester);
    expect(api.calls.last.cancelToken!.isCancelled, isTrue);
    response.complete(_reply(text: 'Cancelled old answer'));
    await _flush(tester);
    await tester.tap(find.descendant(
        of: find.byType(AssistantHistorySheet),
        matching: find.text('Find flights to London')));
    await _flush(tester);
    expect(find.text('Cancelled old answer'), findsNothing);
    expect(api.calls, hasLength(2));
    api.answer = (_) async => _reply(text: 'New follow-up answer');
    await _ask(tester, 'Second follow-up');
    expect(api.calls.last.history.map((turn) => turn.content),
        ['Find flights to London', 'Here are flight options.']);
    expect(history.buckets['owner-a']!.single.turns.map((turn) => turn.text), [
      'Find flights to London',
      'Here are flight options.',
      'Second follow-up',
      'New follow-up answer'
    ]);
    await tester.pumpWidget(const SizedBox());
  });
}

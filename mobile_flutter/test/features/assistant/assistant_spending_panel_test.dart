import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_api.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_spending.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_spending_panel.dart';

AssistantSpendingResult _result() => AssistantSpendingResult(
    AssistantReply(
        reply: 'Groceries were your largest category.',
        actions: const [],
        sources: const [],
        webSearchUsed: false,
        usage: AssistantUsage(
            enabled: true,
            dailyLimit: 50,
            used: 1,
            remaining: 49,
            resetsAt: DateTime.utc(2026, 9, 24),
            maxMessageCharacters: 1500),
        refused: false),
    const AssistantSpendingSummary('2026-09-01', '2026-09-23', [
      AssistantSpendingCurrency('EUR', 123, 20, 103, 3, 1,
          [AssistantSpendingCategory('Groceries', 123, 20)])
    ], activity: [
      AssistantActivityCurrency('EUR', 123, 20, 103, 4, 1, 0, 0, 0)
    ]));

class _Api extends AssistantApi {
  _Api() : super(Dio());
  int calls = 0;
  String? period;
  CancelToken? token;
  List<String> previous = [];
  Completer<AssistantSpendingResult>? pending;
  @override
  Future<AssistantSpendingResult> analyseSpending(
      {required String period,
      required String message,
      String? locale,
      List<String> previousQuestions = const [],
      CancelToken? cancelToken}) async {
    calls++;
    previous = previousQuestions;
    this.period = period;
    token = cancelToken;
    return pending == null ? _result() : pending!.future;
  }
}

Finder get _listScroll => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Future<ProviderContainer> _open(WidgetTester tester, _Api api,
    {double scale = 1, Size size = const Size(320, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [assistantApiProvider.overrideWithValue(api)],
      child: MaterialApp(
          theme: ThemeData.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const AssistantSpendingPanel()),
                      child: const Text('Open spending')))))));
  final container =
      ProviderScope.containerOf(tester.element(find.text('Open spending')));
  await tester.tap(find.text('Open spending'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
      'requires explicit sharing and keeps totals separate from explanation',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    expect(api.calls, 0);
    await tester.scrollUntilVisible(find.text('Share activity & analyse'), 200,
        scrollable: _listScroll);
    await tester.tap(find.text('Share activity & analyse'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(api.period, 'this_month');
    await tester.scrollUntilVisible(find.text('Net flow: EUR 103.00'), 200,
        scrollable: _listScroll);
    expect(find.text('Net flow: EUR 103.00'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Groceries were your largest category.'), 200,
        scrollable: _listScroll);
    expect(find.text('Groceries were your largest category.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open spending'));
    await tester.pumpAndSettle();
    expect(find.text('Net flow: EUR 103.00'), findsNothing);
    expect(api.calls, 1);
  });
  testWidgets(
      'follow-up keeps conversation, sends prior questions and resets on period change',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.tap(find.text('Share activity & analyse'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Which was the largest?');
    await tester.tap(find.text('Ask about my activity'));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(api.previous, [
      'Summarise all my account activity: money in, money out, transfers and fees.'
    ]);
    expect(find.text('Which was the largest?'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>), -300,
        scrollable: _listScroll);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last month').last);
    await tester.pumpAndSettle();
    expect(find.text('Which was the largest?'), findsNothing);
    expect(find.text('Share activity & analyse'), findsOneWidget);
    expect(api.calls, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'desktop separates totals from chat and preserves context when resized',
      (tester) async {
    final api = _Api();
    await _open(tester, api, size: const Size(1440, 960));
    expect(
        find.byKey(const ValueKey('activity-desktop-dialog')), findsOneWidget);
    expect(api.calls, 0);
    await tester.tap(find.text('Fees and charges'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'What fees were recorded?');
    await tester.tap(find.text('Share activity & analyse'));
    await tester.pumpAndSettle();
    final overview = find.byKey(const ValueKey('activity-desktop-overview'));
    final conversation =
        find.byKey(const ValueKey('activity-desktop-conversation'));
    expect(
        find.descendant(
            of: overview, matching: find.text('Net flow: EUR 103.00')),
        findsOneWidget);
    expect(
        find.descendant(
            of: conversation,
            matching: find.text('Groceries were your largest category.')),
        findsOneWidget);
    expect(tester.getRect(overview).right,
        lessThan(tester.getRect(conversation).left));
    expect(tester.getRect(conversation).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
    await tester.enterText(find.byType(TextField), 'Explain that fee.');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-desktop-dialog')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Explain that fee.');
    await tester.tap(find.text('Ask about my activity'));
    await tester.pumpAndSettle();
    expect(api.previous, ['What fees were recorded?']);
    tester.view.physicalSize = const Size(1050, 640);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('activity-desktop-dialog')), findsOneWidget);
    expect(find.text('Ask about my activity').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account switch closes private view and rejects a late response',
      (tester) async {
    final api = _Api()..pending = Completer();
    final container = await _open(tester, api);
    await tester.scrollUntilVisible(find.text('Share activity & analyse'), 200,
        scrollable: _listScroll);
    await tester.tap(find.text('Share activity & analyse'));
    await tester.pump();
    container.read(authSessionGenerationProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(api.token!.isCancelled, isTrue);
    expect(find.byType(AssistantSpendingPanel), findsNothing);
    api.pending!.complete(_result());
    await tester.pumpAndSettle();
    expect(find.text('Net flow: EUR 103.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing cancels request and large text remains scrollable',
      (tester) async {
    final api = _Api()..pending = Completer();
    await _open(tester, api, scale: 2);
    await tester.scrollUntilVisible(find.text('Share activity & analyse'), 200,
        scrollable: _listScroll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share activity & analyse'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(api.token!.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
    api.pending!.complete(_result());
    await tester.pump();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_quick_entry.dart';

void main() {
  test('trip details use unambiguous local dates and explicit budget basis',
      () {
    final details = AssistantTripDetails(
        dates: DateTimeRange(
            start: DateTime(2026, 12, 30), end: DateTime(2027, 1, 3)),
        budget: const AssistantTripBudget(1000, 'EUR', 'total for the trip'));
    expect(details.requestText,
        'Travel dates: 2026-12-30 to 2027-01-03.\nMaximum budget: EUR 1000 total for the trip.');
  });
  test('changing and clearing choices preserves surrounding draft edits', () {
    const old = 'Maximum budget: EUR 500 per person.';
    const next = 'Maximum budget: GBP 1000 total for the trip.';
    expect(applyAssistantTripDetails('Rome please\n\n$old', old, next),
        'Rome please\n\n$next');
    expect(applyAssistantTripDetails('Rome please\n\n$old', old, ''),
        'Rome please');
    expect(applyAssistantTripDetails('I edited my budget to 700', old, next),
        'I edited my budget to 700\n\n$next');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('presets and selected chips fit 320px at scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var details = AssistantTripDetails(
          dates: DateTimeRange(
              start: DateTime(2027, 1, 20), end: DateTime(2027, 2, 1)));
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, setState) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: AssistantQuickEntry(
                          value: details,
                          onChanged: (value) =>
                              setState(() => details = value)))))));
      await tester.tap(find.byKey(const ValueKey('assistant-budget')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('EUR 1000'));
      await tester.tap(find.text('EUR 1000'));
      await tester.tap(find.text('Use budget'));
      await tester.pumpAndSettle();
      expect(details.budget!.amount, 1000);
      expect(details.budget!.basis, 'total for the trip');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Clear budget'));
      await tester.pumpAndSettle();
      expect(details.budget, isNull);
      expect(details.dates, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('budget validates custom amount and cancel preserves selection',
      (tester) async {
    const selected = AssistantTripDetails(
        budget: AssistantTripBudget(500, 'EUR', 'per person'));
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssistantQuickEntry(
                value: selected, onChanged: (_) => changes++))));
    await tester.tap(find.byKey(const ValueKey('assistant-budget')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('assistant-budget-amount')), '0');
    await tester.tap(find.text('Use budget'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an amount from 1 to 1,000,000.'), findsOneWidget);
    expect(changes, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(find.text('EUR 500 per person'), findsOneWidget);
  });
}

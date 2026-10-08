import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/privacy/private_mode_provider.dart';
import 'package:mobile_flutter/features/cards/presentation/widgets/card_face.dart';
import 'package:shared_preferences/shared_preferences.dart';

PaymentCard card(String id, {num? balance, String currency = 'USD'}) =>
    PaymentCard.fromJson({
      'id': id,
      'status': 'active',
      'currency': currency,
      'last4': '1234',
      if (balance != null) 'balance': {'currency': currency, 'amount': balance},
    });
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Money.maskAmounts = false;
  });
  tearDown(() => Money.maskAmounts = false);
  testWidgets(
      'three previews identify only the third funded card and refresh its own amount',
      (tester) async {
    final cards = [
      card('1', balance: 0),
      card('2', balance: 0),
      card('3', balance: 45.50)
    ];
    late StateSetter refresh;
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      refresh = setState;
      return SingleChildScrollView(
          child: Column(children: [
        for (final c in cards)
          SizedBox(
              width: 300,
              child: CardFace(card: c, showBalance: true, interactive: false))
      ]));
    })))));
    await tester.pumpAndSettle();
    expect(find.text(r'$0.00 USD'), findsNWidgets(2));
    expect(find.text(r'$45.50 USD'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('card-preview-balance-3')))
            .data,
        r'$45.50 USD');
    refresh(() => cards[2] = card('3', balance: 32));
    await tester.pumpAndSettle();
    expect(find.text(r'$45.50 USD'), findsNothing);
    expect(find.text(r'$32.00 USD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'unknown balance differs from zero and private mode hides the amount',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(privateModeProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: Column(children: [
          SizedBox(
              width: 300,
              child: CardFace(
                  card: card('unknown'),
                  showBalance: true,
                  interactive: false)),
          SizedBox(
              width: 300,
              child: CardFace(
                  card: card('funded', balance: 98),
                  showBalance: true,
                  interactive: false)),
        ])))));
    await tester.pumpAndSettle();
    expect(find.text('Balance unavailable'), findsOneWidget);
    expect(find.text(r'$0.00 USD'), findsNothing);
    expect(find.text(r'$98.00 USD'), findsOneWidget);
    await container.read(privateModeProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(find.text(r'$98.00 USD'), findsNothing);
    final text = tester
        .widget<Text>(find.byKey(const ValueKey('card-preview-balance-funded')))
        .data!;
    expect(text, contains('USD'));
    expect(text, isNot(contains('98')));
    expect(tester.takeException(), isNull);
  });
}

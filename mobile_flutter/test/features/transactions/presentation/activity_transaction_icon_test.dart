import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/presentation/activity_transaction_icon.dart';
import 'package:mobile_flutter/shared/widgets/finance_transaction_row.dart';

LedgerTransaction _transaction(String type, String amount,
        {String title = 'Provider transaction'}) =>
    LedgerTransaction.fromJson({
      'id': 'transaction-1',
      'type': type,
      'amount': amount,
      'currency': 'USD',
      'title': title,
      'bookedAt': '2026-09-06T10:00:00Z',
    });

void main() {
  test('fees and both exchange directions keep operation icons', () {
    for (final amount in ['-12.00', '12.00', '0.00']) {
      expect(activityTransactionIcon(_transaction('exchange_fee', amount)),
          Icons.receipt_long_outlined);
      expect(activityTransactionIcon(_transaction('crypto_exchange', amount)),
          Icons.currency_exchange_rounded);
    }
    expect(activityTransactionIcon(_transaction('8', '-1.00')),
        Icons.receipt_long_outlined);
  });

  test('actual direction and type distinguish transfer and card operations',
      () {
    expect(activityTransactionIcon(_transaction('deposit', '12.00')),
        Icons.arrow_downward_rounded);
    expect(activityTransactionIcon(_transaction('crypto_withdrawal', '12.00')),
        Icons.arrow_upward_rounded);
    expect(activityTransactionIcon(_transaction('card_payment', '-12.00')),
        Icons.shopping_basket_outlined);
    expect(activityTransactionIcon(_transaction('refund', '12.00')),
        Icons.arrow_downward_rounded);
    expect(activityTransactionIcon(_transaction('card_withdrawal', '-12.00')),
        Icons.arrow_upward_rounded);
    expect(activityTransactionIcon(_transaction('transfer', '0.00')),
        Icons.swap_vert_rounded);
  });

  test('merchant names cannot override the real operation', () {
    expect(
        activityTransactionIcon(_transaction('card_payment', '-12.00',
            title: 'Exchange Fee Coffee')),
        Icons.shopping_basket_outlined);
  });

  testWidgets('Activity icon replaces initials without affecting other rows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ExampleTransactionRow(
            title: 'Incoming transfer',
            amount: 12,
            currency: 'USD',
            fallbackIcon: Icons.arrow_downward_rounded,
          ),
          ExampleTransactionRow(
            title: 'Coffee Shop',
            amount: -3,
            currency: 'USD',
          ),
        ]),
      ),
    ));

    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.text('IT'), findsNothing);
    expect(find.text('CS'), findsOneWidget);
  });

  testWidgets('merchant logo retains its URL and an operation icon on failure',
      (tester) async {
    const logoUrl = 'https://merchant.example/logo.png';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ExampleTransactionAvatar(
          name: 'Coffee Shop',
          logoUrl: logoUrl,
          fallbackIcon: Icons.shopping_basket_outlined,
        ),
      ),
    ));

    final merchantImage = tester.widget<Image>(find.byType(Image));
    expect((merchantImage.image as NetworkImage).url, logoUrl);
    final fallback = merchantImage.errorBuilder!(
        tester.element(find.byType(Image)),
        Exception('Unavailable logo'),
        null);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: fallback)));
    expect(find.byIcon(Icons.shopping_basket_outlined), findsOneWidget);
    expect(find.text('CS'), findsNothing);
  });
}

import 'package:mobile_flutter/features/transactions/data/transaction_documents_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_detail_screen.dart';

void main() {
  for (final example in [false, true]) {
    testWidgets('linked fee and charged headline (Example: $example)',
        (tester) async {
      final rows = [
        LedgerTransaction.fromJson({
          'id': 'purchase',
          'type': 'card_payment',
          'status': 'closed',
          'amount': 10,
          'currency': 'USD',
          'cardId': 17,
          'metadata': {'clientTransactionId': 'client'}
        }),
        LedgerTransaction.fromJson({
          'id': 'fee',
          'type': 'card_payment_fee',
          'status': 'closed',
          'amount': .5,
          'currency': 'USD',
          'cardId': 17,
          'metadata': {'clientTransactionId': 'client_Fee_Consumption'}
        }),
      ];
      await tester.pumpWidget(ProviderScope(
          overrides: [
            transactionDocumentsProvider.overrideWith((ref, id) async => []),
            activityTransactionsProvider.overrideWith((ref) async => rows),
          ],
          child: MaterialApp(
              theme: example
                  ? ThemeData.dark().copyWith(extensions: [const ExampleBrand()])
                  : null,
              home: const TransactionDetailScreen(transactionId: 'purchase'))));
      await tester.pumpAndSettle();
      expect(find.text('-\$10.50'), findsWidgets);
      expect(find.text('Purchase amount'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Consumption fee'), 180,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('USD 0.50 · Charged'), findsOneWidget);
      expect(find.text('Total including fees'), findsOneWidget);
      expect(find.text('-\$10.50'), findsNWidgets(2));
    });
  }
  testWidgets('shows provider metadata and local card amount', (tester) async {
    final transaction = LedgerTransaction(
      id: 'transaction-1',
      title: 'Coffee Shop',
      subtitle: 'closed',
      amount: const Money(currency: 'USD', minorUnits: -492),
      transactionAmount: const Money(currency: 'EUR', minorUnits: -420),
      bookedAt: DateTime(2026, 8, 31, 12, 30),
      type: TransactionType.card,
      rawType: 'card_payment',
      metadata: const {
        'merchantCountry': 'NL',
        'provider': 'Interlace',
        'payment': {'schemeName': 'Mastercard'},
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
        ],
        child: const MaterialApp(
          home: TransactionDetailScreen(transactionId: 'transaction-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('-€4.20'), findsOneWidget);
    expect(find.text('-\$4.92 settled'), findsOneWidget);
    expect(find.text('Advanced details'), findsOneWidget);
    expect(find.text('Merchant Country'), findsNothing);
    await tester.ensureVisible(find.text('Advanced details'));
    await tester.tap(find.text('Advanced details'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Merchant Country'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Merchant Country'), findsOneWidget);
    expect(find.text('NL'), findsOneWidget);
  });

  testWidgets('receipt retains a native crypto withdrawal below one cent',
      (tester) async {
    final transaction = LedgerTransaction.fromJson({
      'id': 'older-crypto',
      'title': 'Crypto withdrawal',
      'type': 'crypto_withdrawal',
      'currency': 'BTC',
      'amount': '0.00012345',
      'bookedAt': '2026-09-05T12:30:00Z',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
        ],
        child: const MaterialApp(
          home: TransactionDetailScreen(transactionId: 'older-crypto'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('-0.00012345 BTC'), findsOneWidget);
    expect(find.text('+0.00012345 BTC'), findsNothing);
  });

  testWidgets('receipt shows exact API card identity and keeps booking time',
      (tester) async {
    final transaction = LedgerTransaction.fromJson({
      'id': 'card-receipt',
      'cardId': '17',
      'title': 'Card purchase',
      'type': 'card_payment',
      'amount': -4.2,
      'currency': 'USD',
      'bookedAt': '2026-09-06T10:30:00',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
          cardsProvider.overrideWith((ref) async => [
                PaymentCard.fromJson({'id': '17', 'last4': '1462'}),
                PaymentCard.fromJson({'id': '18', 'last4': '8763'}),
              ]),
        ],
        child: const MaterialApp(
          home: TransactionDetailScreen(transactionId: 'card-receipt'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Card •••• 1462'), findsOneWidget);
    expect(find.textContaining('8763'), findsNothing);
    expect(find.text('06.09.2026 10:30'), findsOneWidget);
  });

  testWidgets('receipt masks account identity and nested identity metadata',
      (tester) async {
    final transaction = LedgerTransaction.fromJson({
      'id': 'account-receipt',
      'title': 'Account payment',
      'type': 'transfer_out',
      'amount': -10,
      'currency': 'USD',
      'bookedAt': '2026-09-06T10:30:00',
      'metadata': {
        'accountId': 'actual-account',
        'iban': 'BE68539007547034',
        'recipients': [
          {
            'accountNumber': '12345678',
            'cardNumber': '1234567812341462',
            'accessToken': 'hidden-token',
          },
        ],
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
          budgetsProvider.overrideWith((ref) async => const []),
          equalsBankingInfoProvider.overrideWith((ref) async => const []),
          accountsProvider.overrideWith((ref) async => const [
                AccountBalance(
                  id: 'actual-account',
                  name: 'Account',
                  iban: 'BE68539007547034',
                  balance: Money(currency: 'USD', minorUnits: 0),
                  available: Money(currency: 'USD', minorUnits: 0),
                ),
              ]),
        ],
        child: const MaterialApp(
          home: TransactionDetailScreen(transactionId: 'account-receipt'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account BE***7034'), findsOneWidget);
    expect(find.text('***5678'), findsNothing);
    await tester.ensureVisible(find.text('Advanced details'));
    await tester.tap(find.text('Advanced details'));
    await tester.pumpAndSettle();
    expect(find.text('BE***7034'), findsOneWidget);
    expect(find.text('***5678'), findsOneWidget);
    expect(find.text('•••• 1462'), findsOneWidget);
    expect(find.textContaining('BE68539007547034'), findsNothing);
    expect(find.textContaining('12345678'), findsNothing);
    expect(find.textContaining('hidden-token'), findsNothing);
  });

  testWidgets('missing booking date stays unavailable including semantics',
      (tester) async {
    final transaction = LedgerTransaction.fromJson({
      'id': 'undated-receipt',
      'title': 'Transfer',
      'subtitle': 'complete',
      'type': 'transfer_out',
      'amount': -1,
      'currency': 'USD',
      'bookedAt': 'invalid-date',
    });
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [const ExampleBrand()]),
          home: const TransactionDetailScreen(transactionId: 'undated-receipt'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(transaction.hasBookedAt, isFalse);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Booking time unavailable, settled'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('bank receipt uses an operation icon and never claims card rail',
      (tester) async {
    final transaction = LedgerTransaction.fromJson({
      'id': 'bank-deposit',
      'title': 'Budget credit from INTECH d.o.o.',
      'type': 'deposit',
      'currency': 'EUR',
      'amount': '50.00',
      'bookedAt': '2026-05-08T14:38:00',
      'metadata': {
        'provider': 'Equals',
        'accountId': 'provider-account',
        'budgetId': 'actual-budget',
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
          accountsProvider.overrideWith((ref) async => const []),
          budgetsProvider.overrideWith((ref) async => const []),
          equalsBankingInfoProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [const ExampleBrand()]),
          home: const TransactionDetailScreen(transactionId: 'bank-deposit'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bank transfer'), findsOneWidget);
    expect(find.text('Card network'), findsNothing);
    expect(find.text('SEPA'), findsNothing);
    expect(find.text('BC'), findsNothing);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.text('+€50.00'), findsOneWidget);
    expect(find.text('08.05.2026 14:38'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('whole crypto receipt amounts use two decimals', (tester) async {
    final transaction = LedgerTransaction.fromJson({
      'id': 'whole-crypto',
      'title': 'Crypto withdrawal',
      'type': 'crypto_withdrawal',
      'currency': 'USDC',
      'amount': '-1.000000',
      'bookedAt': '2026-09-06T14:30:00Z',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDocumentsProvider.overrideWith((ref, id) async => []),
          activityTransactionsProvider
              .overrideWith((ref) async => [transaction]),
          accountsProvider.overrideWith((ref) async => const []),
          budgetsProvider.overrideWith((ref) async => const []),
          equalsBankingInfoProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [const ExampleBrand()]),
          home: const TransactionDetailScreen(transactionId: 'whole-crypto'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('-1.00 USDC'), findsOneWidget);
    expect(find.text('-1.000000 USDC'), findsNothing);
    expect(transaction.amount.decimalAmount, -1);
    expect(tester.takeException(), isNull);
  });
}

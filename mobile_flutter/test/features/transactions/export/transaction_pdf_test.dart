import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf.dart';

LedgerTransaction _transaction({
  String id = 'crypto-out-123',
  String title = 'Crypto withdrawal',
  String currency = 'USDC',
  num amount = -550.123456,
  Map<String, Object?> extra = const {},
}) =>
    LedgerTransaction.fromJson({
      'id': id,
      'title': title,
      'type': 'crypto_withdrawal',
      'currency': currency,
      'amount': amount,
      'bookedAt': '2026-09-03T13:07:09Z',
      'status': 'completed',
      ...extra,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Money.maskAmounts = false);
  tearDown(() => Money.maskAmounts = false);

  test('snapshot preserves the passed subset, filters and masked identity', () {
    final source = [_transaction()];
    final filters = ['Direction: Out', 'Asset type: Crypto', 'Card ••••1462'];
    final snapshot = TransactionPdfSnapshot(
      transactions: source,
      filters: filters,
      identityFor: (_) => 'Card ••••1462',
    );
    source.add(_transaction(id: 'not-in-export'));
    filters.clear();

    expect(snapshot.rows, hasLength(1));
    expect(snapshot.rows.single.reference, 'crypto-out-123');
    expect(snapshot.rows.single.identity, 'Card ••••1462');
    expect(snapshot.rows.single.amount, '-550.123456 USDC');
    expect(snapshot.filters,
        ['Direction: Out', 'Asset type: Crypto', 'Card ••••1462']);
    expect(() => snapshot.rows.clear(), throwsUnsupportedError);
  });

  test('native and settlement currencies remain separate with their precision',
      () {
    final row = TransactionPdfRow.fromTransaction(_transaction(
      currency: 'USD',
      amount: -12.34,
      extra: {
        'transactionCurrency': 'BTC',
        'transactionAmount': {'currency': 'BTC', 'amount': -0.00012345},
      },
    ));
    expect(row.amount, '-0.00012345 BTC');
    expect(row.settlementAmount, '-\$12.34 USD');
  });

  test('PDF crypto amounts trim only trailing zeros, retaining small amounts',
      () {
    for (final (amount, expected) in <(double, String)>[
      (-1, '-1.00 USDC'),
      (-1.2345, '-1.2345 USDC'),
      (-0.000001, '-0.000001 USDC'),
    ]) {
      final transaction = _transaction(amount: amount);
      final receipt = TransactionPdfSnapshot(
        transactions: [transaction],
        receipt: true,
      );
      expect(receipt.rows.single.amount, expected);
      expect(transaction.amount.decimalAmount, amount);
    }
  });

  test('missing dates and statuses do not become a completed payment today',
      () {
    final row = TransactionPdfRow.fromTransaction(_transaction(extra: {
      'bookedAt': null,
      'status': '',
    }));
    expect(row.booked, 'Date unavailable');
    expect(row.status, 'Not provided');
    expect(row.identity, isNull);
  });

  test('snapshot keeps private-mode amounts hidden even if setting changes',
      () {
    Money.maskAmounts = true;
    final snapshot = TransactionPdfSnapshot(transactions: [_transaction()]);
    Money.maskAmounts = false;
    expect(snapshot.rows.single.amount, '•••• USDC');
  });

  test('receipts require one row and use a safe reference filename', () {
    expect(
      () => TransactionPdfSnapshot(transactions: [], receipt: true),
      throwsArgumentError,
    );
    final snapshot = TransactionPdfSnapshot(
      transactions: [_transaction(id: '../../card 42:/')],
      receipt: true,
      generatedAt: DateTime.utc(2026, 9, 6, 11, 22, 33),
    );
    expect(snapshot.title, 'Transaction receipt');
    expect(snapshot.fileName, 'example-receipt-card42-20260906112233000.pdf');
  });

  test('export filenames use the configured app name safely', () {
    final snapshot = TransactionPdfSnapshot(
      transactions: [_transaction()],
      appName: 'Hoppa / Customer',
      generatedAt: DateTime.utc(2026, 9, 6, 11, 22, 33),
    );
    expect(snapshot.fileName, 'hoppa-customer-activity-20260906112233000.pdf');
  });

  test('PDFs contain embedded text fonts, real PDF structure and pagination',
      () async {
    final transactions = [
      _transaction(title: 'Withdrawal • račun'),
      _transaction(
        id: 'fixture-fiat-fee',
        currency: 'EUR',
        amount: -.90,
        title: 'Monthly card fee',
        extra: {'type': 'card_fee'},
      ),
      _transaction(
        id: 'fixture-card-settlement',
        currency: 'USD',
        amount: -174.25,
        title: 'Card purchase with original currency details',
        extra: {
          'type': 'card_payment',
          'subtitle': 'Card Payment\nOriginal amount: '
              '${const Money(currency: 'TRY', minorUnits: 642050).formatted}',
        },
      ),
      for (var index = 0; index < 75; index++)
        _transaction(id: 'fixture-$index', title: 'Withdrawal $index'),
    ];
    final snapshot = TransactionPdfSnapshot(
      transactions: transactions,
      appName: 'Hoppa Customer',
      filters: ['Direction: All', 'Asset type: All', 'Date: 2026-09-03'],
      identityFor: (transaction) => transaction.id == 'fixture-fiat-fee'
          ? 'Card ••••1462'
          : 'Account BE…1234',
      generatedAt: DateTime.utc(2026, 9, 6, 11, 22, 33),
    );
    final bytes = await buildTransactionPdf(snapshot);
    final structure = latin1.decode(bytes);
    expect(structure, startsWith('%PDF-'));
    expect(structure, contains('%%EOF'));
    expect(structure, contains('/FontFile2'));
    expect(structure, contains('/ToUnicode'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(structure).length,
        greaterThan(1));

    final receipt = await buildTransactionPdf(TransactionPdfSnapshot(
      transactions: [transactions.first],
      appName: snapshot.appName,
      receipt: true,
      identityFor: (_) => 'Account BE…1234',
      generatedAt: snapshot.generatedAt,
    ));
    expect(latin1.decode(receipt), startsWith('%PDF-'));

    // Optional local visual QA artifacts, never shipped with the app.
    final output = Platform.environment['EXAMPLE_PDF_TEST_OUTPUT'];
    if (output != null && output.isNotEmpty) {
      await Directory(output).create(recursive: true);
      await File('$output/activity-fixture.pdf').writeAsBytes(bytes);
      await File('$output/receipt-fixture.pdf').writeAsBytes(receipt);
    }
  });
}

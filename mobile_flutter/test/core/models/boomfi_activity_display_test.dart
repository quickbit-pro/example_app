import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/formatters/transaction_display.dart';

void main() {
  test('sold USDC is a debit and EUR proceeds remain separate', () {
    final row = LedgerTransaction.fromJson({
      'id': 88840,
      'type': 'exchange',
      'amount': '15.90',
      'currency': 'USDC',
      'merchantName': 'BoomFi',
      'status': 'completed',
      'metadata': {
        'provider': 'boomfi',
        'sellAmount': '15.9',
        'sellCurrency': 'USDC',
        'buyAmount': '13.92',
        'buyCurrency': 'EUR'
      },
    });
    expect(row.amount.formatted, '-15.90 USDC');
    expect(row.title, 'USDC → EUR');
    expect(transactionDisplayTitle(row.title), 'USDC → EUR');
    expect(row.secondarySettlementAmount?.formatted, '€13.92');
  });
  test('deposit and bank withdrawal have clear labels and correct signs', () {
    for (final (type, currency, amount, title) in [
      ('crypto_deposit', 'USDC', 15.901935, 'USDC deposit'),
      ('withdrawal', 'EUR', -13.92, 'Bank withdrawal'),
    ]) {
      final row = LedgerTransaction.fromJson({
        'type': type,
        'currency': currency,
        'amount': amount,
        'merchantName': 'BoomFi',
        'metadata': {'Provider': 'BoomFi'}
      });
      expect(row.title, title);
      expect(row.amount.decimalAmount, amount);
    }
  });
  test('does not infer unknown proceeds or flip a received currency debit', () {
    final row = LedgerTransaction.fromJson({
      'type': 'exchange',
      'amount': 13.92,
      'currency': 'EUR',
      'metadata': {
        'provider': 'BoomFi',
        'sellCurrency': 'USDC',
        'buyCurrency': 'EUR',
        'buyAmount': 'NaN'
      }
    });
    expect(row.amount.isPositive, isTrue);
    expect(row.exchangeReceivedAmount, isNull);
  });
}

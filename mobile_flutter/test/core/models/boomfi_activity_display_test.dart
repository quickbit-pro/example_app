import 'package:dio/dio.dart';
import 'package:mobile_flutter/core/widgets/app_states.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/formatters/transaction_display.dart';

void main() {
  test('legacy provider names display as ZBX in transaction descriptions', () {
    for (final name in ['BoomFi', 'BoomFI', 'BOOMFI', 'boomfi']) {
      expect(transactionDisplayTitle(name), 'ZBX');
      expect(transactionDisplayTitle('$name transfer'), 'ZBX transfer');
      expect(exchangeProviderDisplayText('Account with $name'), 'Account with ZBX');
    }
  });

  test('all provider error paths use the public ZBX name', () {
    for (final name in ['BoomFi', 'BoomFI', 'BOOMFI', 'boomfi']) {
      expect(friendlyErrorMessage(FormatException('$name needs verification')),
          'ZBX needs verification');
      expect(friendlyErrorMessage(Exception('$name needs verification')),
          'ZBX needs verification');
      for (final status in [400, 409, 422]) {
        final options = RequestOptions(path: '/exchange/quote');
        final error = DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: status,
              data: {'message': '$name needs verification'}),
          type: DioExceptionType.badResponse,
        );
        expect(friendlyErrorMessage(error), 'ZBX needs verification');
      }
    }
  });

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

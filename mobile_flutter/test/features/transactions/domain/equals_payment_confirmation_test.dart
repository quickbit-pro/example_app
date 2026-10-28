import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/domain/equals_payment_confirmation.dart';

void main() {
  LedgerTransaction transaction(Map<String, dynamic> overrides) =>
      LedgerTransaction.fromJson({
        'id': 91191,
        'type': 'payout',
        'status': 'completed',
        'amount': -10,
        'currency': 'EUR',
        'externalTransactionId': '9433626',
        'metadata': {
          'provider': 'equalsmoney',
          'originalType': 'payment',
          'paymentId': '9433626'
        },
        ...overrides,
      });
  test('91191 qualifies and metadata supports API object and JSON formats', () {
    expect(canDownloadEqualsPaymentConfirmation(transaction({})), isTrue);
    expect(
        canDownloadEqualsPaymentConfirmation(transaction({
          'metadata':
              jsonEncode({'provider': 'equalsmoney', 'payment_id': 9433626})
        })),
        isTrue);
    expect(
        canDownloadEqualsPaymentConfirmation(transaction({
          'type': 'withdrawal',
          'metadata': {'provider': 'equalsmoney', 'original_type': 'payment'}
        })),
        isTrue);
  });
  test('card purchases, deposits, fees and non-Equals transfers do not qualify',
      () {
    for (final type in [
      'card_payment',
      'deposit',
      'fee',
      'exchange',
      'transfer'
    ]) {
      expect(
          canDownloadEqualsPaymentConfirmation(transaction({
            'type': type,
            'metadata': {'provider': 'equalsmoney'}
          })),
          isFalse);
    }
    expect(
        canDownloadEqualsPaymentConfirmation(transaction({
          'metadata': {'provider': 'interlace', 'paymentId': 9433626}
        })),
        isFalse);
    expect(
        canDownloadEqualsPaymentConfirmation(
            transaction({'metadata': 'invalid json'})),
        isFalse);
  });
  test('requires positive integer provider and local IDs', () {
    for (final invalid in [null, '', '0', '-2', '1.5', 'pay_123', '01', 1.5]) {
      expect(
          canDownloadEqualsPaymentConfirmation(transaction({
            'externalTransactionId': null,
            'metadata': {'provider': 'equalsmoney', 'paymentId': invalid}
          })),
          isFalse,
          reason: '$invalid');
    }
    expect(
        canDownloadEqualsPaymentConfirmation(transaction({'id': 'card:91191'})),
        isFalse);
    expect(
        canDownloadEqualsPaymentConfirmation(transaction({
          'externalTransactionId': null,
          'metadata': {'provider': 'equalsmoney', 'paymentId': 9433626.0}
        })),
        isTrue);
  });
  test(
      'eligibility mirrors web behavior without inventing a settled-only restriction',
      () {
    expect(
        canDownloadEqualsPaymentConfirmation(
            transaction({'status': 'pending'})),
        isTrue);
  });
}

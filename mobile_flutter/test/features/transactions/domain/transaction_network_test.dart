import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/domain/transaction_network.dart';

void main() {
  test('bank deposit has a bank fallback without inventing SEPA', () {
    final transaction = _transaction(
      type: 'deposit',
      title: 'Budget credit from INTECH d.o.o.',
      metadata: const {
        'provider': 'Equals',
        'accountId': 'provider-account',
        'budgetId': 'actual-budget',
      },
    );
    expect(transactionNetworkLabel(transaction), 'Bank transfer');
  });

  test('explicit provider payment rail supplies SEPA', () {
    expect(
      transactionNetworkLabel(_transaction(
        type: 'deposit',
        metadata: const {
          'payment': {'paymentMethod': 'SEPA'}
        },
      )),
      'SEPA',
    );
    expect(
      transactionNetworkLabel(_transaction(
        type: 'transfer_out',
        metadata: const {'PaymentRail': 'SCT_INST'},
      )),
      'SEPA Instant',
    );
  });

  test('EUR transfer does not imply SEPA and respects another actual rail', () {
    expect(transactionNetworkLabel(_transaction(type: 'transfer_out')),
        'Bank transfer');
    expect(
      transactionNetworkLabel(_transaction(
        type: 'transfer_out',
        metadata: const {'paymentMethod': 'SWIFT'},
      )),
      'SWIFT',
    );
  });

  test('card receipt keeps the supplied scheme or a generic card label', () {
    expect(
      transactionNetworkLabel(_transaction(
        type: 'card_payment',
        metadata: const {
          'payment': {'schemeName': 'Mastercard'}
        },
      )),
      'Mastercard',
    );
    expect(transactionNetworkLabel(_transaction(type: 'card_payment')),
        'Card network');
  });

  test('USDC title and currency cannot choose its blockchain', () {
    expect(
      transactionNetworkLabel(_transaction(
        type: 'crypto_withdrawal',
        title: 'USDC withdrawal',
        currency: 'USDC',
      )),
      isNull,
    );
    expect(
      transactionNetworkLabel(_transaction(
        type: 'crypto_withdrawal',
        title: 'USDC withdrawal',
        currency: 'USDC',
        metadata: const {'chain': 'Base'},
      )),
      'Base',
    );
  });

  test('titles and unrelated nested fields never supply the network', () {
    expect(
      transactionNetworkLabel(_transaction(
        type: 'card_payment',
        title: 'USDC BTC Ethereum shop',
        metadata: const {
          'feeBreakdown': {'network': '0.10'},
          'recipient': {'paymentMethod': 'SEPA'},
        },
      )),
      'Card network',
    );
  });

  test('unknown operations and internal exchanges do not invent a rail', () {
    for (final type in [
      'unknown',
      '999',
      'exchange',
      'internal_transfer',
      'fee'
    ]) {
      expect(transactionNetworkLabel(_transaction(type: type)), isNull);
    }
    expect(
      transactionNetworkLabel(_transaction(
        type: 'exchange',
        metadata: const {'paymentMethod': 'exchange'},
      )),
      isNull,
    );
  });

  test('top-level provider network fields survive ledger parsing', () {
    final transaction = LedgerTransaction.fromJson({
      'id': 'crypto-withdrawal',
      'type': 'crypto_withdrawal',
      'currency': 'USDC',
      'amount': '-50.123456',
      'bookedAt': '2026-09-06T14:30:00Z',
      'Chain': {'Name': 'Polygon'},
    });
    expect(transactionNetworkLabel(transaction), 'Polygon');
    expect(transaction.displayAmount.decimalAmount, -50.123456);
  });
}

LedgerTransaction _transaction({
  required String type,
  String title = 'Transaction',
  String currency = 'EUR',
  Map<String, dynamic> metadata = const {},
}) =>
    LedgerTransaction.fromJson({
      'id': 'transaction',
      'type': type,
      'title': title,
      'currency': currency,
      'amount': 50,
      'bookedAt': '2026-09-06T14:30:00Z',
      'metadata': metadata,
    });

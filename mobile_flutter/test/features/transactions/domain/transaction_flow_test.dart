import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/domain/transaction_flow.dart';

LedgerTransaction _transaction(String type, {Map<String, dynamic>? values}) =>
    LedgerTransaction.fromJson({
      'id': type,
      'type': type,
      'amount': '10.00',
      'currency': 'USD',
      'status': 'completed',
      ...?values,
    });

void main() {
  test('conversion cycle counts only external deposits, withdrawal and costs',
      () {
    final transactions = [
      _transaction('crypto_deposit', values: {
        'currency': 'USDT',
        'amount': '1000.00',
      }),
      _transaction('crypto_to_quantum', values: {
        'amount': '998.50',
        'metadata': {
          'sourceAmount': '1000.00',
          'sourceCurrency': 'USDT',
          'destinationAmount': '998.50',
          'destinationCurrency': 'USD',
        },
      }),
      _transaction('quantum_to_crypto_exchange', values: {
        'amount': '998.50',
        'metadata': {
          'targetCurrency': 'USDC',
          'cryptoAmountReceived': '997.25',
        },
      }),
      _transaction('crypto_withdrawal', values: {
        'currency': 'USDC',
        'amount': '997.25',
      }),
      _transaction('fees', values: {'amount': '2.50'}),
    ];

    final external = transactions
        .where((transaction) => !transactionIsInternalMovement(transaction))
        .toList();
    expect(external.map((transaction) => transaction.rawType),
        ['crypto_deposit', 'crypto_withdrawal', 'fees']);
    expect(external.map((transaction) => transaction.amount.decimalAmount),
        [1000.0, -997.25, -2.5]);
    expect(external.map((transaction) => transaction.amount.currency),
        ['USDT', 'USDC', 'USD']);
    // Both conversions stay available as actual ledger rows with their
    // provider amounts. No fictional USD/USDT/USDC parity is needed.
    expect(transactions[1].amount.decimalAmount, 998.50);
    expect(transactions[2].amount.decimalAmount, -998.50);
  });

  test('explicit card funding and balance movement types are internal', () {
    for (final type in [
      'card_topup',
      'auto_card_topup',
      'card_load',
      'card_loading',
      'card_unload',
      'crypto_to_quantum_transfer',
      'balance_transfer',
      'exchange',
      'crypto_exchange',
    ]) {
      expect(transactionIsInternalMovement(_transaction(type)), isTrue,
          reason: type);
    }
  });

  test('fees and transfers to other customers are not hidden by metadata', () {
    for (final type in [
      'card_topup_fee',
      'exchange_fee',
      'fees',
      'p2p_send',
      'p2p_receive',
      'transfer_to_master',
      'transfer_from_master',
    ]) {
      expect(
        transactionIsInternalMovement(_transaction(type, values: {
          'metadata': {'operation': 'card_topup'},
        })),
        isFalse,
        reason: type,
      );
    }
  });

  test('generic transfers require explicit own-transfer metadata', () {
    for (final type in [
      'transfer_in',
      'transfer_out',
      'deposit',
      'withdrawal'
    ]) {
      expect(transactionIsInternalMovement(_transaction(type)), isFalse);
    }
    expect(
      transactionIsInternalMovement(_transaction('transfer_out', values: {
        'metadata': {
          'details': {'operationType': 'own_account_transfer'},
        },
      })),
      isTrue,
    );
    expect(
      transactionIsInternalMovement(_transaction('deposit', values: {
        'metadata': {'isInternalTransfer': true},
      })),
      isTrue,
    );
  });

  test('Hoppa Equals FX trades and exchange-sourced ledger legs are internal',
      () {
    expect(transactionIsInternalMovement(_transaction('fx_trade')), isTrue);
    for (final type in ['deposit', 'withdrawal']) {
      expect(
          transactionIsInternalMovement(_transaction(type, values: {
            'metadata': {'provider': 'equalsmoney', 'source': 'exchange'},
          })),
          isTrue);
    }
    for (final type in ['fees', 'exchange_fee', 'p2p_send']) {
      expect(
          transactionIsInternalMovement(_transaction(type, values: {
            'metadata': {'provider': 'equalsmoney', 'source': 'exchange'},
          })),
          isFalse);
    }
    expect(
        transactionIsInternalMovement(_transaction('deposit', values: {
          'metadata': {'source': 'exchange'},
        })),
        isFalse);
    expect(
        transactionIsInternalMovement(_transaction('deposit', values: {
          'metadata': {'provider': 'interlace', 'source': 'exchange'},
        })),
        isFalse);
  });

  test(
      'merchant labels and ambiguous budget credits cannot establish ownership',
      () {
    expect(
      transactionIsInternalMovement(_transaction('deposit', values: {
        'title': 'Exchange from my own card',
        'merchantName': 'Crypto Exchange',
        'metadata': {
          'description': 'Internal transfer',
          'provider': 'equalsmoney',
          'budgetId': 'actual-budget-id',
          'source': 'external_credit',
        },
      })),
      isFalse,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/group_activity_transactions.dart';
import 'package:mobile_flutter/core/models/group_card_fees.dart';
import 'package:mobile_flutter/features/transactions/domain/activity_net_flow.dart';

LedgerTransaction row(String id, String type,
        [Map<String, dynamic> extra = const {}]) =>
    LedgerTransaction.fromJson({
      'id': id,
      'type': type,
      'amount': 12,
      'currency': 'USD',
      'status': 'closed',
      'transactionDate': '2026-09-04T19:56:55.580',
      ...extra,
    });

void main() {
  test(
      'Beno legacy FX shape: credit without order joins debit and delayed trade',
      () {
    final rows = [
      row('trade', 'fx_trade', {
        'amount': 11.79,
        'currency': 'CNY',
        'tradeId': 'order-1',
        'transactionGroupId': 'equalsmoney:order:order-1',
        'transactionDate': '2026-09-04T20:19:41.718260',
      }),
      row('credit', 'deposit', {
        'amount': 11.79,
        'currency': 'CNY',
        'transactionGroupId': 'equalsmoney:ledger:123',
        'transactionDate': '2026-09-04T20:19:09.531',
        'metadata': {
          'source': 'exchange',
          'provider': 'equalsmoney',
          'budgetId': 'budget-1',
          'boxTransactionId': 123
        },
      }),
      row('debit', 'withdrawal', {
        'amount': 555,
        'currency': 'HUF',
        'tradeId': 'order-1',
        'isPrimary': false,
        'transactionGroupId': 'equalsmoney:order:order-1',
        'transactionDate': '2026-09-04T20:19:09.447',
        'metadata': {
          'source': 'exchange',
          'provider': 'equalsmoney',
          'budgetId': 'budget-1',
          'boxTransactionId': 122
        },
      }),
      row('exchange', 'exchange', {
        'amount': 11.79, 'currency': 'CNY', 'tradeId': 'order-1',
        'transactionDate': '2026-09-04T20:19:08',
        // The provider's exchange view names the SELL box, not the buy box.
        'metadata': {'budgetId': 'budget-1', 'boxTransactionId': 122},
      }),
    ];
    final group = groupActivityTransactions(rows).single;
    expect(group.primary.id, 'trade');
    expect(group.entries, rows);
    expect(cardListAmount(group.primary).decimalAmount, 11.79);
    expect(rows.first.cardFees, isEmpty);
  });

  test('legacy FX fallback rejects mismatches and competing operations', () {
    List<LedgerTransaction> operation(String id) => [
          row('trade-$id', 'fx_trade', {
            'tradeId': id,
            'amount': 11.79,
            'currency': 'CNY',
            'transactionGroupId': 'equalsmoney:order:$id',
          }),
          row('debit-$id', 'withdrawal', {
            'amount': 555,
            'currency': 'HUF',
            'transactionGroupId': 'equalsmoney:order:$id',
            'isPrimary': false,
            'metadata': {
              'source': 'exchange',
              'provider': 'equalsmoney',
              'budgetId': 'b'
            },
          }),
        ];
    LedgerTransaction credit([Map<String, dynamic> extra = const {}]) =>
        row('credit', 'deposit', {
          'amount': 11.79,
          'currency': 'CNY',
          'metadata': {
            'source': 'exchange',
            'provider': 'equalsmoney',
            'budgetId': 'b'
          },
          ...extra,
        });
    for (final extra in [
      {'amount': 12},
      {'currency': 'EUR'},
      {'status': 'pending'},
      {'budgetId': 'other'},
      {'transactionGroupId': 'equalsmoney:order:other'},
      {'transactionDate': '2026-09-04T20:00:00'},
      {
        'metadata': {
          'source': 'external_credit',
          'provider': 'equalsmoney',
          'budgetId': 'b'
        }
      },
    ]) {
      final result =
          groupActivityTransactions([...operation('one'), credit(extra)]);
      expect(result, hasLength(2), reason: '$extra');
      expect(result.last.primary.id, 'credit');
    }
    expect(
        groupActivityTransactions([
          ...operation('one'),
          ...operation('two'),
          credit(),
        ]),
        hasLength(3));
  });

  test('Beno legacy unload: type 3 wallet and card bookings differ by 1ms', () {
    final rows = [
      row('unload', 'card_unload', {
        'cardId': 'card-1',
        'metadata': {'type': 3},
        'transactionDate': '2026-09-04T19:56:55.581',
      }),
      row('wallet', 'wallet_debit', {
        'metadata': {'type': 3}
      }),
    ];
    final group = groupActivityTransactions(rows).single;
    expect(group.primary.id, 'unload');
    expect(group.entries, rows);
    expect(cardListAmount(group.primary).decimalAmount, -12);
  });

  test(
      'linked unload is not counted again as wallet spending; scopes retain movement',
      () {
    final card = row('unload', 'card_unload', {
      'metadata': {'type': 3}
    });
    final wallet = row('wallet', 'wallet_debit', {
      'metadata': {'type': 3}
    });
    final all = activityFlowTotals([card, wallet], currency: 'USD', rates: {});
    expect(all.outgoing, 0);
    expect(all.eventCount, 0);
    final scoped = activityFlowTotals([card, wallet],
        currency: 'USD', rates: {}, includeRelated: true);
    expect(scoped.outgoing, 12);
    expect(scoped.eventCount, 1);
    final walletOnly = activityFlowTotals([wallet],
        currency: 'USD', rates: {}, includeRelated: true);
    expect(walletOnly.outgoing, 12);
  });

  test('legacy top-up keeps credited amount with its fee available underneath',
      () {
    final rows = [
      row('topup', 'card_topup', {
        'amount': 11.82,
        'status': 'completed',
        'transactionDate': '2026-09-04T19:57:16.025109',
        'metadata': {'fee': .18, 'grossAmount': 12},
      }),
      row('fee', 'fees', {
        'description': 'fees: card_topup_fee',
        'amount': -.18,
        'status': 'completed',
        'transactionDate': '2026-09-04T19:57:15.119881',
      }),
    ];
    final group = groupActivityTransactions(rows).single;
    expect(group.primary.id, 'topup');
    expect(group.entries, rows);
    expect(cardListAmount(group.primary).decimalAmount, 11.82);
    final totals = activityFlowTotals(rows, currency: 'USD', rates: {});
    expect(totals.outgoing, .18);
    expect(totals.incoming, 0);
  });

  test('legacy matching rejects ambiguity, wrong event, scope, status and time',
      () {
    final wallet = row('wallet', 'wallet_debit', {
      'metadata': {'type': 3}
    });
    final card = row('card', 'card_unload', {
      'metadata': {'type': 3}
    });
    expect(
        groupActivityTransactions([
          wallet,
          card,
          row('other', 'card_unload', {
            'metadata': {'type': 3}
          })
        ]),
        hasLength(3));
    for (final extra in [
      {
        'metadata': {'type': 2}
      },
      {'transactionDate': '2026-09-04T19:56:57'},
      {'status': 'failed'},
      {'currency': 'EUR'},
      {'amount': 13},
      {'transactionGroupId': 'another-operation'},
    ]) {
      expect(
          groupActivityTransactions([
            card,
            row('wallet', 'wallet_debit', {
              'metadata': {'type': 3},
              ...extra,
            })
          ]),
          hasLength(2),
          reason: '$extra');
    }
    expect(
        groupActivityTransactions([
          row('wallet', 'wallet_debit', {
            'accountId': 'one',
            'metadata': {'type': 3}
          }),
          row('card', 'card_unload', {
            'accountId': 'two',
            'metadata': {'type': 3}
          }),
        ]),
        hasLength(2));
  });

  test('group and parent references join even when child arrives first', () {
    final child = row('wallet', 'wallet_debit', {
      'transactionGroupId': 'operation',
      'parentTransactionId': 'unload',
      'isPrimary': false,
    });
    final unload = row('unload', 'card_unload');
    final extra = row('other-leg', 'deposit', {
      'transactionGroupId': 'operation',
      'isPrimary': false,
    });
    final group = groupActivityTransactions([child, extra, unload]).single;
    expect(group.primary, unload);
    expect(group.entries, [child, extra, unload]);
  });

  test('card and wallet views match exact provider or client reference', () {
    for (final field in ['externalTransactionId', 'clientTransactionId']) {
      final rows = [
        row('wallet', 'wallet_debit', {field: 'transfer-1'}),
        row('card', 'card_unload', {field: 'transfer-1', 'cardId': 'card-1'}),
      ];
      final group = groupActivityTransactions(rows).single;
      expect(group.primary.id, 'card');
      expect(group.entries, rows);
    }
  });

  test('unrelated same-time same-amount transactions stay separate', () {
    expect(
        groupActivityTransactions(
            [row('wallet', 'wallet_debit'), row('card', 'card_unload')]),
        hasLength(2));
    expect(groupActivityTransactions([]), isEmpty);
  });

  test('ambiguous references stay separate', () {
    expect(
        groupActivityTransactions([
          row('wallet', 'wallet_debit',
              {'externalTransactionId': 'transfer-1'}),
          row('card', 'card_unload', {'externalTransactionId': 'transfer-1'}),
          row('other-card', 'card_unload',
              {'externalTransactionId': 'transfer-1'}),
        ]),
        hasLength(3));
  });

  test('missing parent stays available in a scoped or filtered feed', () {
    final child = row('wallet', 'wallet_debit', {
      'parentTransactionId': 'unload',
      'isPrimary': false,
    });
    final group = groupActivityTransactions([child]).single;
    expect(group.primary, child);
    expect(group.entries, [child]);
  });

  test('PascalCase API references are preserved', () {
    final first = row('one', 'deposit', {'TransactionGroupId': 'same'});
    final second = row('two', 'withdrawal', {'ParentTransactionId': 'one'});
    expect(groupActivityTransactions([first, second]), hasLength(1));
  });

  test('fees and duplicate provider views remain accessible', () {
    final rows = [
      row('payment', 'card_payment', {'clientTransactionId': 'client'}),
      row('fee', 'card_payment_fee', {
        'amount': .18,
        'clientTransactionId': 'client_Fee_Consumption',
      }),
    ];
    final group = groupActivityTransactions(rows).single;
    expect(group.entries, rows);
    expect(cardListAmount(group.primary).decimalAmount, -12.18);
    final duplicateRows = [
      row('fx', 'fx_trade', {'tradeId': 'order-1'}),
      row('exchange', 'exchange', {'tradeId': 'order-1'}),
    ];
    expect(
        groupActivityTransactions(duplicateRows).single.entries, duplicateRows);
  });
}

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
      'BoomFi legs group by explicit IDs while separate deposits remain separate',
      () {
    final deposit = row('501', 'crypto_deposit', {
      'transactionGroupId': 'boomfi:payment:pay_parent',
      'amount': 12.582916,
      'currency': 'USDC',
      'metadata': {'provider': 'BoomFi', 'externalTransactionId': 'pay_parent'},
    });
    final payout = row('502', 'withdrawal', {
      'transactionGroupId': 'boomfi:payment:pay_parent',
      'parentTransactionId': 501,
      'isPrimary': false,
      'amount': -12.582916,
      'currency': 'USDC',
      'status': 'requires_action',
      'metadata': {'provider': 'BoomFi', 'externalTransactionId': 'pay_child'},
    });
    final separate = row('503', 'crypto_deposit', {
      'transactionGroupId': 'boomfi:payment:pay_separate',
      'amount': 12.582916,
      'currency': 'USDC',
      'metadata': {
        'provider': 'BoomFi',
        'externalTransactionId': 'pay_separate'
      },
    });
    final groups = groupActivityTransactions([deposit, payout, separate]);
    expect(groups.length, 2);
    final operation = groups.singleWhere((g) => g.primary.id == '501');
    expect(operation.entries, [deposit, payout]);
    expect(operation.primary, same(deposit));
  });

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

  test(
      'legacy top-up preserves card credit and displays total source deduction',
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
    expect(group.primary.amount.decimalAmount, 11.82);
    expect(group.primary.cardFees.single.id, 'fee');
    expect(activityListAmount(group.primary).decimalAmount, -12);
    expect(
        activityListAmount(group.primary, sourceAmounts: false).decimalAmount,
        11.82);
    expect(group.activityEntries, [rows.first]);
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

  test('explicit fee link attaches to non-primary parent and keeps raw amounts',
      () {
    final parent = row('payment', 'payout', {'amount': 12, 'isPrimary': false});
    final fee =
        row('fee', 'fees', {'amount': .25, 'parentTransactionId': 'payment'});
    final group = groupActivityTransactions([fee, parent]).single;
    expect(group.primary.id, 'payment');
    expect(activityListAmount(group.primary).decimalAmount, -12.25);
    expect(parent.amount.decimalAmount, -12);
    expect(parent.cardFees, isEmpty);
    expect(group.activityEntries, [parent]);
  });

  test('FX total uses sell currency and never mixes buy-currency units', () {
    final trade = row('fx', 'fx_trade', {
      'amount': 12.72,
      'currency': 'GBP',
      'metadata': {'sellAmount': 15, 'sellCurrency': 'EUR'},
    });
    final fee = row('fee', 'fees', {
      'amount': .01,
      'currency': 'EUR',
      'parentTransactionId': 'fx',
    });
    final group = groupActivityTransactions([trade, fee]).single;
    expect(activityListAmount(group.primary).currency, 'EUR');
    expect(activityListAmount(group.primary).decimalAmount, -15.01);
    expect(group.primary.amount.currency, 'GBP');
    expect(group.primary.amount.decimalAmount, 12.72);
    final totals = activityFlowTotals([trade, fee], currency: 'EUR', rates: {});
    expect(totals.outgoing, .01);
    expect(totals.incoming, 0);
  });

  test('declined purchase shows only charged fee, once', () {
    final purchase =
        row('decline', 'card_payment', {'amount': 50, 'status': 'declined'});
    final fee = row('fee', 'card_decline_fee', {
      'amount': 0,
      'feeAmount': .5,
      'feeCurrency': 'USD',
      'relatedCardTransactionId': 'decline',
    });
    final group = groupActivityTransactions([fee, purchase]).single;
    expect(activityListAmount(group.primary).decimalAmount, -.5);
    expect(group.primary.cardFees, hasLength(1));
    expect(group.activityEntries, [purchase]);
    expect(
        activityFlowTotals([fee, purchase], currency: 'USD', rates: {})
            .outgoing,
        .5);
  });
}

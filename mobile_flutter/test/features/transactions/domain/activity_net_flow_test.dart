import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/domain/activity_net_flow.dart';

LedgerTransaction row(String id, double amount, String currency,
        {String status = 'completed',
        String type = 'deposit',
        bool primary = true}) =>
    LedgerTransaction.fromJson({
      'id': id,
      'amount': amount,
      'currency': currency,
      'status': status,
      'type': type,
      'isPrimary': primary
    });

void main() {
  test('a declined purchase counts the fees it was still charged, once', () {
    final rows = [
      LedgerTransaction.fromJson({
        'id': 'decline-fee',
        'type': 'card_decline_fee',
        'amount': -0.5,
        'currency': 'USD',
        'status': 'completed',
        'transactionDate': '2026-09-01T09:44:46',
        'cardId': '541',
        'relatedCardTransactionId': 'ext-p',
      }),
      LedgerTransaction.fromJson({
        'id': 'p',
        'externalTransactionId': 'ext-p',
        'type': 'card_payment',
        'amount': 66.87,
        'currency': 'USD',
        'status': 'fail',
        'transactionDate': '2026-09-01T09:44:43',
        'cardId': '541',
      }),
    ];
    final totals =
        activityFlowTotals(rows, currency: 'USD', rates: {'USD': 1.0});
    expect(totals.eventCount, 1);
    expect(totals.incoming, 0);
    expect(totals.outgoing, closeTo(.5, .000001));
  });

  test('a fee the provider surfaced twice is summed once', () {
    final rows = [
      LedgerTransaction.fromJson({
        'id': 'fees',
        'type': 'fees',
        'amount': 0.03,
        'currency': 'EUR',
        'status': 'completed',
        'transactionGroupId': 'equalsmoney:order:E1-Fee',
        'tradeId': 'E1-Fee',
        'metadata': {'boxTransactionId': '9'},
      }),
      LedgerTransaction.fromJson({
        'id': 'fee',
        'type': 'fee',
        'amount': 0.03,
        'currency': 'EUR',
        'status': 'completed',
        'tradeId': 'E1-Fee',
        'metadata': {'boxTransactionId': 9, 'provider': 'equalsmoney'},
      }),
    ];
    final totals =
        activityFlowTotals(rows, currency: 'EUR', rates: {'EUR': 1.0});
    expect(totals.eventCount, 1);
    expect(totals.outgoing, closeTo(.03, .000001));
  });

  test('mixed fiat and stablecoins yield one correctly converted net', () {
    final rows = [
      row('eur', 100, 'EUR'),
      row('usd', -20, 'USD'),
      row('usdt', 5, 'USDT'),
      row('usdc', -2, 'USDC'),
      row('gbp', -10, 'GBP')
    ];
    final usd = {'EUR': 1.2, 'USD': 1.0, 'GBP': 1.5, 'USDT': 1.0, 'USDC': 1.0};
    expect(activityNetFlow(rows, currency: 'USD', rates: usd), 88);
    final totals = activityFlowTotals(rows, currency: 'USD', rates: usd);
    expect(totals.incoming, 125);
    expect(totals.outgoing, 37);
    expect(totals.eventCount, 5);
    expect(
        activityNetFlow(rows, currency: 'EUR', rates: {
          for (final e in usd.entries) e.key: e.value / 1.2,
        }),
        closeTo(88 / 1.2, .000001));
    expect(
        activityNetFlow(rows, currency: 'GBP', rates: {
          for (final e in usd.entries) e.key: e.value / 1.5,
        }),
        closeTo(88 / 1.5, .000001));
  });
  test('pending, failures, duplicate rows and own conversion are not income',
      () {
    final rows = [
      row('credit', 10, 'USD'),
      row('credit', 10, 'USD'),
      row('pending', 100, 'USD', status: 'pending'),
      row('failed', -100, 'USD', status: 'declined'),
      row('fx', 50, 'EUR', type: 'fx_trade'),
      row('related', 10, 'USD', primary: false),
      row('fee', -1, 'USD', type: 'fee')
    ];
    expect(activityNetFlow(rows, currency: 'USD', rates: {}), 9);
    final totals = activityFlowTotals(rows, currency: 'USD', rates: {});
    expect(totals.incoming, 10);
    expect(totals.outgoing, 1);
    expect(totals.eventCount, 2);
  });
  test('missing FX never produces a partial or nominal mixed-currency sum', () {
    expect(
        activityNetFlow([row('usd', 5, 'USD'), row('aed', 10, 'AED')],
            currency: 'USD', rates: {}),
        isNull);
  });
  test('a scoped card includes its funding, and empty filters total zero', () {
    final rows = [row('funding', 10, 'USD', type: 'card_topup')];
    expect(activityNetFlow(rows, currency: 'USD', rates: {}), 0);
    expect(
        activityNetFlow(rows, currency: 'USD', rates: {}, includeRelated: true),
        10);
    expect(activityNetFlow([], currency: 'EUR', rates: {}), 0);
  });
}

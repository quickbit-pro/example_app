import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';

void main() {
  test('bank exchange displays settled conversion and pending withdrawal', () {
    final transfer = BoomFiTransfer.fromJson({
      'id': 2, 'status': 'exchange_submitted', 'transferDirection': 'exchange_to_bank',
      'cryptoCurrency': 'USDC', 'cryptoAmount': '12.58', 'fiatCurrency': 'EUR',
      'fiatSettledAt': '2026-10-09T16:31:11.936Z', 'boomFiOrderId': 'order-2',
    });
    expect(transfer.showInProgress, isTrue);
    expect(transfer.flowLabel, 'USDC → EUR → Bank account');
    expect(transfer.progressStage, 2);
    expect(transfer.progressLabels, ['Exchange\nbalance', 'Convert to\nEUR', 'Withdraw to\nbank']);
    expect(transfer.progressStatusLabel, 'Awaiting provider details');
  });

  test('unsubmitted failed quote is hidden but failure after settlement stays visible', () {
    BoomFiTransfer transfer(Map<String, dynamic> extra) => BoomFiTransfer.fromJson({
      'id': 1, 'status': 'exchange_failed', 'transferDirection': 'exchange_to_bank', ...extra,
    });
    expect(transfer({}).showInProgress, isFalse);
    expect(transfer({'boomFiOrderId':'order-2'}).showInProgress, isTrue);
    expect(transfer({'fiatSettledAt':'2026-10-09T16:31:11Z'}).showInProgress, isTrue);
    expect(transfer({'status':'exchange_quoted'}).showInProgress, isFalse);
    expect(transfer({'status':'completed'}).showInProgress, isFalse);
  });

  test('transfer directions and bank payout stage use the actual flow', () {
    final toCard = BoomFiTransfer.fromJson({'transferDirection':'equals_to_interlace','status':'payout_submitted'});
    expect(toCard.flowLabel, 'Fiat account → Crypto card');
    expect(toCard.progressLabels.first, 'Fiat\naccount');
    expect(toCard.progressLabels.last, 'Crypto\ncard');
    expect(toCard.progressStage, 3);
    final payout = BoomFiTransfer.fromJson({'transferDirection':'exchange_to_bank','status':'payout_submitted'});
    expect(payout.progressStage, 2);
    expect(payout.progressStatusLabel, 'Bank withdrawal processing');
  });

  test('currency balances do not add the same funds across network routes', () {
    final overview = BoomFiExchangeOverview.fromJson({
      'balances': {'balances': [
        for (final chain in [1, 1399811149, -200])
          {'account_id': chain, 'currency': 'USDC', 'amount': '12.582916', 'chain': {'id': chain}},
        {'account_id': 142, 'currency': 'EUR', 'amount': '0'},
      ]}
    });
    expect(overview.balances.length, 4);
    expect(overview.displayBalances.length, 2);
    final usdc = overview.displayBalances.singleWhere((b) => b.currency == 'USDC');
    expect(usdc.amount, 12.582916);
    expect(overview.displayBalances.singleWhere((b) => b.currency == 'EUR').amount, 0);
  });

  test('Exchange overview only becomes ready with provider data', () {
    final pending = BoomFiExchangeOverview.fromJson(const {
      'account': {'id': 0, 'enabled': false, 'state': 'pending'},
      'balances': {'balances': []},
      'settlement_accounts': [],
    });
    final ready = BoomFiExchangeOverview.fromJson(const {
      'account': {'id': 42, 'enabled': true, 'state': 'active'},
      'balances': {
        'balances': [
          {
            'account_id': 10,
            'currency': 'USDC',
            'amount': '12.5',
            'pending_amount': '0.5',
            'chain': {'id': 1, 'name': 'Ethereum'},
          },
        ],
      },
      'fiat_funding_currencies': ['EUR'],
    });

    expect(pending.hasProviderData, isFalse);
    expect(pending.isReady, isFalse);
    expect(ready.isReady, isTrue);
    expect(ready.balances.single.isCrypto, isTrue);
    expect(ready.balances.single.amount, 12.5);
  });

  test('transfer decision states are parsed from public API response', () {
    final quote = BoomFiTransfer.fromJson(const {
      'id': 7,
      'status': 'awaiting_quote_approval',
      'transferDirection': 'interlace_to_equals',
    });
    final funds = BoomFiTransfer.fromJson(const {
      'Id': 8,
      'Status': 'awaiting_funds_decision',
    });

    expect(quote.needsQuoteDecision, isTrue);
    expect(funds.needsFundsDecision, isTrue);
  });
}

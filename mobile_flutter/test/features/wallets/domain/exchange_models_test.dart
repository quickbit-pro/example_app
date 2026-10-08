import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';

void main() {
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

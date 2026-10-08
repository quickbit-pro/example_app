import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/cards/domain/card_top_up_balance.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';

HoppaWalletAsset asset(String symbol, double amount) => HoppaWalletAsset(
    symbol: symbol,
    name: symbol,
    network: '',
    amount: amount,
    fiatValue: 0,
    address: '',
    tint: Colors.grey,
    walletId: symbol);

void main() {
  test('available top-up combines USD and both stablecoins at 1:1', () {
    final available = cardTopUpAvailable([
      asset('USD', 1.15),
      asset('USDT', 247),
      asset('USDC', 0),
    ]);
    expect(available, 248.15);
    expect(cardBalanceQuickAmount(available, 1, wholeDollarMax: true), 248);
    expect(cardBalanceQuickAmount(available, .5, wholeDollarMax: true), 124.07);
    expect(
        cardTopUpAvailable(
            [asset('USD', 1.15), asset('USDC', 10.25), asset('USDT', 247)]),
        258.40);
  });
  test('unsupported currencies and invalid balances do not inflate funding',
      () {
    expect(
        cardTopUpAvailable([
          asset('EUR', 1000),
          asset('BTC', 10),
          asset('USDT', -1),
          asset('USD', double.nan),
          asset('USDC', double.infinity)
        ]),
        0);
  });
  test('Max preserves exact cents for unload and floors only top-up dollars',
      () {
    expect(cardBalanceQuickAmount(1.15, 1), 1.15);
    expect(cardBalanceQuickAmount(248.999, 1, wholeDollarMax: true), 248);
    expect(cardBalanceQuickAmount(9.99, 1, wholeDollarMax: true), 9);
    expect(cardBalanceQuickAmount(0, 1, wholeDollarMax: true), 0);
    expect(
        cardBalanceQuickAmount(
            cardTopUpAvailable(
                [asset('USD', .1), asset('USDC', .7), asset('USDT', .2)]),
            1,
            wholeDollarMax: true),
        1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/money/domain/balance_value_order.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';

void main() {
  test('Equals overview uses common-currency value, not the native number', () {
    final portfolio = PortfolioEstimate.fromJson({
      'currency': 'USD',
      'valuationRates': [
        {'currency': 'EUR', 'rate': 44.0823824863 / 37.92},
        {'currency': 'AED', 'rate': 11.477195371 / 42.15},
        {'currency': 'RON', 'rate': 2.27792943546 / 10.29},
      ],
    });
    const budgets = [
      PlatformResource(
          id: 'main',
          title: 'Account balance',
          subtitle: '',
          metadata: {
            'balances': [
              {'currency': 'AED', 'amount': 42.15},
              {'currency': 'RON', 'amount': 10.29},
              {'currency': 'EUR', 'amount': 37.92},
            ]
          }),
    ];
    final balances =
        equalsBudgetBalances(budgets, valuationRates: portfolio.valuationRates);
    expect(balances.map((row) => row.currency), ['EUR', 'AED', 'RON']);
    expect(balances.map((row) => row.decimalAmount), [37.92, 42.15, 10.29]);
    // A larger AED holding must win: EUR is not hard-coded as primary.
    expect(
        compareBalanceValues(
            'EUR', 37.92, 'AED', 1000, portfolio.valuationRates),
        greaterThan(0));
  });

  test('unknown rates never imply parity with known currencies', () {
    expect(compareBalanceValues('EUR', 2, 'JPY', 10000, {'EUR': 1.16}),
        lessThan(0));
    expect(compareBalanceValues('EUR', 2, 'JPY', 10000, {}), lessThan(0));
    expect(compareBalanceValues('EUR', 2, 'EUR', 10, {}), greaterThan(0));
  });
}

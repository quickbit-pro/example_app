import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/money/domain/payment_balance_options.dart';

void main() {
  const account = AccountBalance(
    id: 'budget-1',
    name: 'Operating budget',
    iban: 'GB00TEST1234',
    balance: Money(currency: 'GBP', minorUnits: 10000),
    available: Money(currency: 'GBP', minorUnits: 9000),
    supportedCurrencies: ['AED', 'EUR', 'GBP'],
    currencyBalances: [
      Money(currency: 'AED', minorUnits: 0),
      Money(currency: 'EUR', minorUnits: 2500),
      Money(currency: 'GBP', minorUnits: 9000),
    ],
  );

  test('only exposes positive funded currencies', () {
    expect(fundedCurrencyOptions(account), ['EUR', 'GBP']);
  });

  test('prefers the payee currency when it is funded', () {
    expect(
      fundedCurrencyOptions(account, preferredCurrency: 'GBP'),
      ['GBP', 'EUR'],
    );
  });

  test('account selector label omits balances shown below the selector', () {
    final label = paymentAccountOptionLabel(account);
    expect(label, 'Operating budget');
  });

  test('adds the funded Equals account balance from budget resources', () {
    const mainBalance = PlatformResource(
      id: 'equals-main',
      title: 'Account balance',
      subtitle: 'GBP',
      metadata: {
        'accountId': 'equals-main',
        'displayName': 'Account balance',
        'balances': [
          {'currency': 'GBP', 'amount': '377.00'},
        ],
      },
    );

    final result = paymentAccountsWithBudgets([account], [mainBalance]);

    expect(result.first.name, 'Account balance');
    expect(result.first.currencyBalances.single.formatted, '£377.00');
    expect(result.last.name, 'Operating budget');
  });
}

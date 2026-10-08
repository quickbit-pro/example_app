import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/transactions/domain/activity_account_option.dart';

void main() {
  test('roster currencies never inherit a default USD balance currency', () {
    final account = AccountBalance.fromJson({
      'accountId': 'account-1',
      'displayName': 'Bank account',
      'supportedCurrencies': ['EUR', 'RON'],
      'currencyBalances': [
        {'currency': 'EUR', 'availableBalance': 42.18},
        {'currency': 'RON', 'availableBalance': 930.25},
      ],
    });
    expect(account.hasBalanceCurrency, isFalse);
    final choices = buildActivityAccountOptions(accounts: [account]);
    expect(choices.map((option) => option.currency).toSet(), {'EUR', 'RON'});
    expect(choices.any((option) => option.label.contains('USD')), isFalse);
  });

  test('missing balance currency keeps an unqualified real account scope', () {
    for (final value in <Object?>[
      null,
      0,
      {'amount': 0},
      {'currency': ''}
    ]) {
      final account = AccountBalance.fromJson({
        'id': 'account-1',
        'name': 'Current',
        if (value != null) 'balance': value,
      });
      expect(account.hasBalanceCurrency, isFalse);
      final option = buildActivityAccountOptions(accounts: [account]).single;
      expect(option.currency, isEmpty);
      expect(option.label, 'Current');
      expect(option.scopeIds, {'account-1'});
      expect(option.matches(_transaction(account: 'account-1')), isTrue);
      expect(
          option.matches(_transaction(account: 'account-1', currency: 'RON')),
          isTrue);
      expect(
          option.matches(_transaction(account: 'different-account')), isFalse);
    }
  });

  test('linked currencies take precedence over a legacy primary balance', () {
    final account = AccountBalance.fromJson({
      'id': 'account-1',
      'name': 'Current',
      'balance': {'currency': 'USD', 'minorUnits': 0},
      'linkedBankAccounts': [
        {'currency': 'EUR', 'iban': 'BE68539007547034'},
      ],
    });
    final choices = buildActivityAccountOptions(accounts: [account]);
    expect(choices.map((option) => option.currency), ['EUR']);
  });

  test('an explicit balance currency is a valid fallback in either JSON case',
      () {
    for (final balance in [
      {'currency': 'EUR', 'minorUnits': 0},
      {'Currency': 'EUR', 'MinorUnits': 0},
    ]) {
      final account = AccountBalance.fromJson({
        'id': 'account-1',
        'name': 'Current',
        'balance': balance,
      });
      expect(account.hasBalanceCurrency, isTrue);
      expect(account.balance.currency, 'EUR');
      expect(buildActivityAccountOptions(accounts: [account]).single.currency,
          'EUR');
    }
  });

  test(
      'zero balances stay selectable but supported currencies do not create accounts',
      () {
    final choices = buildActivityAccountOptions(accounts: [
      AccountBalance.fromJson({
        'id': 'account-1',
        'name': 'Euro Account',
        'iban': 'BE68539007547034',
        'balance': {'currency': 'EUR', 'minorUnits': 0},
        'supportedCurrencies': ['EUR', 'RON'],
        'currencyBalances': [
          {'currency': 'EUR', 'available': 0},
          {'currency': 'RON', 'available': 0},
        ],
      }),
    ]);
    expect(
        choices.map((option) => option.currency), containsAll(['EUR', 'RON']));
    expect(
        choices.every((option) => option.label.contains('BE***7034')), isTrue);
    expect(
        choices
            .firstWhere((option) => option.currency == 'RON')
            .matches(_transaction(account: 'account-1', currency: 'RON')),
        isTrue);
    expect(
        choices
            .firstWhere((option) => option.currency == 'EUR')
            .matches(_transaction(account: 'account-1', currency: 'RON')),
        isFalse);
  });

  test('budgets sharing parent and currency never match each other', () {
    final choices = buildActivityAccountOptions(budgets: [
      _budget('first', ['EUR', 'RON']),
      _budget('second', ['EUR']),
    ]);
    final selected =
        choices.firstWhere((option) => option.key == 'budget:first:EUR');
    expect(selected.scopeIds, {'first'});
    expect(selected.matches(_transaction(budget: 'first')), isTrue);
    expect(selected.matches(_transaction(budget: 'second')), isFalse);
    expect(selected.matches(_transaction(account: 'shared-parent')), isFalse);
    expect(selected.matches(_transaction(budget: 'first', currency: 'RON')),
        isFalse);
    expect(choices.length, 3);
  });

  test('synthesized platform IDs and parent account IDs do not create options',
      () {
    final choices = buildActivityAccountOptions(budgets: [
      PlatformResource.fromJson({'title': 'Euro', 'currency': 'EUR'}),
      PlatformResource.fromJson(
          {'title': 'Budget', 'accountId': 'shared-parent'}),
    ]);
    expect(choices, isEmpty);
  });

  test('bank identity is matched by exact budget and currency, never position',
      () {
    final choices = buildActivityAccountOptions(
      budgets: [
        _budget('first', ['EUR']),
        _budget('second', ['EUR'])
      ],
      bankingInfo: [
        PlatformResource.fromJson({
          'budgetId': 'second',
          'currency': 'EUR',
          'accountNumber': 'BE68539007541234'
        }),
        PlatformResource.fromJson({
          'budgetId': 'first',
          'currency': 'EUR',
          'accountNumber': 'BE68539007545678'
        }),
      ],
    );
    expect(
        choices
            .firstWhere((option) => option.key == 'budget:first:EUR')
            .maskedIdentifier,
        'BE***5678');
    expect(
        choices
            .firstWhere((option) => option.key == 'budget:second:EUR')
            .maskedIdentifier,
        'BE***1234');
  });

  test('embedded receiving currencies create distinct zero-history options',
      () {
    final choices = buildActivityAccountOptions(budgets: [
      PlatformResource.fromJson({
        'id': 'first',
        'name': 'Main',
        'settlementDetails': {
          'currencyDetails': [
            {
              'currencyCode': 'EUR',
              'local': {'accountIdentifier': 'BE68539007547034'}
            },
            {
              'currencyCode': 'RON',
              'local': {'accountIdentifier': 'RO49AAAA1B31007593840000'}
            },
          ]
        },
      }),
    ]);
    expect(
        choices.map((option) => option.label),
        containsAll([
          'EUR account · BE***7034',
          'RON account · RO***0000',
        ]));
  });

  test('supported currency catalog does not become an account roster', () {
    final account = AccountBalance.fromJson({
      'accountId': 'actual-account',
      'displayName': 'Account balance',
      'supportedCurrencies': ['AED', 'AUD', 'EUR', 'RON'],
      'currencyBalances': [
        {'currency': 'EUR', 'available': 0}
      ],
    });
    final choices = buildActivityAccountOptions(accounts: [account]);
    expect(choices.single.currency, 'EUR');
    expect(choices.single.label, 'EUR account');
  });

  test('account and budget aliases merge only by explicit child budget ID', () {
    final choices = buildActivityAccountOptions(
      accounts: [
        AccountBalance.fromJson({
          'accountId': 'shared-parent',
          'budgetId': 'first',
          'accountType': 'BUDGET',
          'displayName': 'Account balance',
          'supportedCurrencies': ['AED', 'AUD', 'EUR'],
          'currencyBalances': [
            {'currency': 'AED', 'available': 0},
            {'currency': 'EUR', 'available': 0},
          ],
        }),
        AccountBalance.fromJson({
          'accountId': 'shared-parent',
          'budgetId': 'second',
          'accountType': 'BUDGET',
          'displayName': 'Travel',
        }),
      ],
      budgets: [
        _budget('first', ['EUR']),
        _budget('second', ['EUR'])
      ],
    );
    expect(choices.map((choice) => choice.key).toSet(),
        {'budget:first:EUR', 'budget:second:EUR'});
    final first =
        choices.firstWhere((choice) => choice.key == 'budget:first:EUR');
    expect(first.scopeIds, {'first'});
    expect(first.matches(_transaction(account: 'shared-parent')), isFalse);
    expect(first.matches(_transaction(budget: 'second')), isFalse);
    expect(first.matches(_transaction(budget: 'first')), isTrue);
  });

  test('same currency and name remain distinct with labelled actual references',
      () {
    final choices = buildActivityAccountOptions(budgets: [
      for (final id in ['actual-first', 'actual-second'])
        PlatformResource.fromJson({
          'budgetId': id,
          'name': 'Account balance',
          'currencies': ['EUR'],
        }),
    ]);
    expect(choices.length, 2);
    expect(choices.map((choice) => choice.label).toSet().length, 2);
    expect(choices.every((choice) => choice.label.startsWith('EUR account')),
        isTrue);
    expect(choices.every((choice) => choice.label.contains('Ref ')), isTrue);
    expect(choices.every((choice) => choice.maskedIdentifier.isEmpty), isTrue);
  });

  test(
      'zero-history account is retained without a currency capability expansion',
      () {
    final choices = buildActivityAccountOptions(accounts: [
      AccountBalance.fromJson({
        'accountId': 'empty-account',
        'displayName': 'Travel',
        'supportedCurrencies': ['EUR', 'RON'],
      }),
    ]);
    expect(choices.single.label, 'Travel');
    expect(choices.single.currency, isEmpty);
    expect(choices.single.scopeIds, {'empty-account'});
  });
}

PlatformResource _budget(String id, List<String> currencies) =>
    PlatformResource.fromJson({
      'id': id,
      'name': id,
      'accountId': 'shared-parent',
      'currencies': currencies,
    });

LedgerTransaction _transaction(
        {String account = 'shared-parent',
        String budget = '',
        String currency = 'EUR'}) =>
    LedgerTransaction(
      id: 'row',
      title: 'API movement',
      subtitle: '',
      amount: Money(currency: currency, minorUnits: 100),
      bookedAt: DateTime(2026, 9, 6),
      type: TransactionType.transfer,
      accountId: account,
      budgetId: budget,
    );

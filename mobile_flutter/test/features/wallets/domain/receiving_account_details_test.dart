import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/wallets/domain/receiving_account_details.dart';

void main() {
  test('one multi-currency account shares its EUR IBAN with RON', () {
    final budget = _resource({
      'budgetId': 'budget-a',
      'accountId': 'owner-a',
      'supportedCurrencies': ['EUR', 'RON'],
      'balances': [
        {'currency': 'EUR', 'amount': 47.92},
        {'currency': 'RON', 'amount': 10.29}
      ],
    });
    final accounts =
        receivingAccountsFromResources([_prefill('budget-a', currency: 'EUR')]);
    final eur = receivingAccountForBudget(budget, accounts, currency: 'EUR');
    final ron = receivingAccountForBudget(budget, accounts, currency: 'RON');
    expect(ron, isNotNull);
    expect(ron!.accountNumber, eur!.accountNumber);
    expect(ron.swift, eur.swift);
    expect(ron.holder, eur.holder);
    expect(
        receivingAccountForBudget(budget, accounts, currency: 'USD'), isNull);
  });

  test('shared IBAN fallback never borrows another budget or ambiguous routing',
      () {
    final budget = _resource({
      'budgetId': 'budget-a',
      'accountId': 'owner-a',
      'supportedCurrencies': ['EUR', 'RON']
    });
    expect(
        receivingAccountForBudget(
            budget,
            receivingAccountsFromResources([
              _prefill('budget-b', currency: 'EUR'),
            ]),
            currency: 'RON'),
        isNull);
    expect(
        receivingAccountForBudget(
            budget,
            receivingAccountsFromResources([
              _prefill('budget-a', currency: 'EUR'),
              _prefill('budget-a',
                  number: 'GB82WEST12345698765432', currency: 'GBP'),
            ]),
            currency: 'RON'),
        isNull);
  });

  test('embedded EUR settlement IBAN also serves the account RON balance', () {
    final budget = _resource({
      'budgetId': 'budget-a',
      'balances': [
        {'currency': 'EUR', 'amount': 47.92},
        {'currency': 'RON', 'amount': 10.29}
      ],
      'settlementDetails': {
        'currencyDetails': [
          {
            'currencyCode': 'EUR',
            'international': {
              'accountIdentifier': 'BE68539007547034',
              'bankIdentifier': 'BBRUBEBB'
            }
          }
        ]
      },
    });
    expect(
        receivingAccountForBudget(budget, const [], currency: 'RON')
            ?.accountNumber,
        'BE68539007547034');
  });

  test('parses the Equals recipient prefill routing and holder fields', () {
    final account = receivingAccountsFromResources([
      _resource({
        'userId': 7,
        'userName': 'Example Holder',
        'paymentType': 'INDIVIDUAL',
        'paymentMethod': 'SEPA',
        'currency': 'EUR',
        'country': 'BE',
        'accountNumber': '539007547034',
        'bankName': 'Example Bank',
        'routingCodes': [
          {
            'routingCodeType': 'IBAN',
            'routingCodeValue': 'be68 5390 0754 7034'
          },
          {'routingCodeType': 'SWIFT_CODE', 'routingCodeValue': 'BBRUBEBB'},
        ],
      }),
    ]).single;

    expect(account.accountNumber, 'BE68539007547034');
    expect(account.isIban, isTrue);
    expect(account.maskedIdentifier, 'BE***7034');
    expect(account.swift, 'BBRUBEBB');
    expect(account.holder, 'Example Holder');
    expect(account.bankName, 'Example Bank');
    expect(account.currencies, {'EUR'});
    expect(account.scopeIds, isEmpty);
    expect(
        account.copyAll,
        'Fiat account details\n'
        'IBAN: BE68539007547034\n'
        'SWIFT/BIC: BBRUBEBB\n'
        'Account holder: Example Holder\n'
        'Bank: Example Bank');
    expect(account.qrPayload, account.copyAll);
  });

  test('parses Pascal case wrappers and every linked bank account', () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'Data': {
          'BudgetId': 'budget-a',
          'AccountId': 'owner-a',
          'UserName': 'Example Holder',
          'LinkedBankAccounts': [
            {'Iban': 'BE68539007547034', 'SwiftCode': 'BBRUBEBB'},
            {'AccountNumber': '12345678', 'Currency': 'GBP'},
          ],
        },
      }),
    ]);

    expect(accounts, hasLength(2));
    expect(accounts.first.swift, 'BBRUBEBB');
    expect(accounts.last.accountNumber, '12345678');
    expect(accounts.last.maskedIdentifier, '***5678');
    expect(accounts.last.isIban, isFalse);
    expect(accounts.last.holder, 'Example Holder');
    expect(accounts.last.scopeIds, {'budget-a', 'owner-a'});
  });

  test('links legacy Equals business account details to the exact budget', () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'AccountId': 'budget-b',
        'ParentAccountId': 'owner-a',
        'AccountType': 'BUDGET',
        'Provider': 'EqualsMoney',
        'AccountHolderName': 'Second Account Holder',
        'LinkedBankAccounts': [
          {
            'BankAccountId': 'budget-b',
            'Currency': 'EUR',
            'Iban': 'BE71 0961 2345 6769',
            'BankName': 'Second Bank',
            'Swift': 'GKCCBEBB',
          },
        ],
      }),
      _resource({
        'accountId': 'budget-a',
        'parentAccountId': 'owner-a',
        'accountType': 'BUDGET',
        'provider': 'EqualsMoney',
        'accountHolderName': 'First Account Holder',
        'linkedBankAccounts': [
          {
            'bankAccountId': 'budget-a',
            'currency': 'EUR',
            'iban': 'BE68 5390 0754 7034',
            'bankName': 'First Bank',
            'swift': 'BBRUBEBB',
          },
        ],
      }),
    ]);

    final first = receivingAccountForBudget(_budget('budget-a'), accounts,
        currency: 'EUR');
    final second = receivingAccountForBudget(_budget('budget-b'), accounts,
        currency: 'EUR');
    expect(first?.accountNumber, 'BE68539007547034');
    expect(first?.holder, 'First Account Holder');
    expect(first?.swift, 'BBRUBEBB');
    expect(first?.copyAll, contains('Account holder: First Account Holder'));
    expect(second?.accountNumber, 'BE71096123456769');
    expect(second?.holder, 'Second Account Holder');
    expect(second?.swift, 'GKCCBEBB');
    expect(
      receivingAccountForBudget(_budget('budget-c'), accounts, currency: 'EUR'),
      isNull,
      reason:
          'The shared parent, currency, and list order cannot link a budget.',
    );
    expect(
      receivingAccountForBudget(_budget('budget-a'), accounts, currency: 'GBP')
          ?.accountNumber,
      first?.accountNumber,
      reason:
          'A supported currency shares this explicitly linked account IBAN.',
    );
  });

  test('missing legacy linked bank numbers do not become receiving details',
      () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'accountId': 'budget-a',
        'parentAccountId': 'owner-a',
        'accountType': 'BUDGET',
        'accountHolderName': 'Example Holder',
        'linkedBankAccounts': [
          {
            'bankAccountId': 'budget-a',
            'currency': 'EUR',
            'iban': '',
            'bankName': 'Example Bank',
          },
        ],
      }),
    ]);
    expect(accounts, isEmpty);
    expect(receivingAccountForBudget(_budget('budget-a'), accounts), isNull);
  });

  test('merges currency duplicates without losing explicit budget links', () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'budgetId': 'budget-a',
        'accountNumber': 'BE68 5390 0754 7034',
        'currency': 'EUR',
      }),
      _resource({
        'budgetId': 'budget-b',
        'accountNumber': 'be68539007547034',
        'currency': 'RON',
        'swift': 'BBRUBEBB',
        'bankName': 'Example Bank',
      }),
    ]);

    expect(accounts, hasLength(1));
    expect(accounts.single.currencies, {'EUR', 'RON'});
    expect(accounts.single.scopeIds, {'budget-a', 'budget-b'});
    expect(accounts.single.swift, 'BBRUBEBB');
    expect(accounts.single.bankName, 'Example Bank');
    expect(receivingAccountForBudget(_budget('budget-b'), accounts),
        accounts.single);
    expect(
        receivingAccountForBudget(_budget('budget-b'), accounts,
            currency: 'EUR'),
        accounts.single);
    expect(
        receivingAccountForBudget(_budget('budget-a'), accounts,
            currency: 'RON'),
        isNull,
        reason: 'RON is not a supported currency of this budget.');
    expect(
        receivingAccountForBudget(_budget('budget-b'), accounts,
            currency: 'RON'),
        accounts.single);
  });

  test('identical local numbers at different banks keep their own routing', () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'budgetId': 'budget-a',
        'accountId': 'owner-a',
        'accountNumber': '12345678',
        'swift': 'BARCGB22',
        'bankName': 'Bank A',
        'userName': 'Holder A',
        'currency': 'GBP',
      }),
      _resource({
        'budgetId': 'budget-b',
        'accountId': 'owner-a',
        'accountNumber': '12345678',
        'swift': 'WESTGB2L',
        'bankName': 'Bank B',
        'userName': 'Holder B',
        'currency': 'GBP',
      }),
    ]);
    expect(accounts, hasLength(2));
    final selected = receivingAccountForBudget(_budget('budget-b'), accounts,
        currency: 'GBP');
    expect(selected?.swift, 'WESTGB2L');
    expect(selected?.bankName, 'Bank B');
    expect(selected?.holder, 'Holder B');
    expect(selected?.copyAll, isNot(contains('BARCGB22')));
  });

  test('missing local routing cannot borrow it from another budget', () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'budgetId': 'budget-a',
        'accountNumber': '12345678',
        'swift': 'BARCGB22',
        'bankName': 'Bank A',
        'currency': 'GBP',
      }),
      _resource({
        'budgetId': 'budget-b',
        'accountNumber': '12345678',
        'currency': 'GBP',
      }),
    ]);
    final selected = receivingAccountForBudget(_budget('budget-b'), accounts,
        currency: 'GBP');
    expect(selected?.swift, isEmpty);
    expect(selected?.bankName, isEmpty);
  });

  test('scope sets and result lists cannot be mutated by consumers', () {
    final sourceScopes = {'budget-a'};
    final account = ReceivingAccountDetails(
      accountNumber: '12345678',
      swift: '',
      bankName: '',
      holder: '',
      scopeIds: sourceScopes,
    );
    sourceScopes.add('budget-b');
    expect(account.scopeIds, {'budget-a'});
    expect(() => account.scopeIds.add('budget-b'), throwsUnsupportedError);
    expect(() => account.currencies.add('EUR'), throwsUnsupportedError);
    final accounts = receivingAccountsFromResources([_prefill('budget-a')]);
    expect(() => accounts.clear(), throwsUnsupportedError);
  });

  test('does not infer identity from titles, currencies, or malformed values',
      () {
    final accounts = receivingAccountsFromResources([
      _resource({'userId': 7, 'currency': 'EUR', 'title': 'BE68539007547034'}),
      _resource({
        'accountNumber': {'number': '12345678'}
      }),
      _resource({'accountNumber': ' ', 'iban': ''}),
      _resource({
        'routingCodes': [
          {'routingCodeType': 'iban'}
        ]
      }),
    ]);
    expect(accounts, isEmpty);
  });

  test('missing bank fields remain empty and are omitted from copy text', () {
    final account = receivingAccountsFromResources([
      _resource({'accountNumber': '12345678'}),
    ]).single;
    expect(account.swift, isEmpty);
    expect(account.bankName, isEmpty);
    expect(account.holder, isEmpty);
    expect(account.copyAll, 'Fiat account details\nAccount number: 12345678');
  });

  test('links exact budget IDs even if receiving accounts arrive out of order',
      () {
    final accounts = receivingAccountsFromResources([
      _prefill('budget-b', number: '12345678'),
      _prefill('budget-a'),
    ]);
    expect(receivingAccountForBudget(_budget('budget-a'), accounts),
        accounts.last);
  });

  test('does not assign the only receiving account without a proven link', () {
    final accounts = receivingAccountsFromResources([
      _resource({'accountNumber': '12345678', 'currency': 'EUR', 'userId': 7}),
    ]);
    expect(receivingAccountForBudget(_budget('budget-a'), accounts), isNull);
  });

  test('shared owner account ID cannot associate a specific budget', () {
    final accounts = receivingAccountsFromResources([
      _resource({'accountNumber': '12345678', 'accountId': 'owner-a'}),
    ]);
    expect(receivingAccountForBudget(_budget('budget-a'), accounts), isNull);
    expect(receivingAccountForBudget(_budget('budget-b'), accounts), isNull);
  });

  test('an explicit different budget never matches by the shared owner', () {
    final accounts = receivingAccountsFromResources([_prefill('budget-b')]);
    expect(receivingAccountForBudget(_budget('budget-a'), accounts), isNull);
  });

  test('can link a standalone account through its explicit account ID', () {
    final accounts = receivingAccountsFromResources([
      _resource({'accountNumber': '12345678', 'accountId': 'account-a'}),
    ]);
    final account = _resource({'accountId': 'account-a'});
    expect(receivingAccountForBudget(account, accounts), accounts.single);
  });

  test('matches an explicit identifier despite formatting differences', () {
    final accounts = receivingAccountsFromResources([_prefill('budget-a')]);
    final budget =
        _resource({'budgetId': 'budget-a', 'iban': 'be68 5390 0754 7034'});
    expect(receivingAccountForBudget(budget, accounts)?.accountNumber,
        accounts.single.accountNumber);
  });

  test('matches the API local account number alias when routing supplies IBAN',
      () {
    final accounts = receivingAccountsFromResources([
      _resource({
        'accountNumber': '539007547034',
        'routingCodes': [
          {'routingCodeType': 'iban', 'routingCodeValue': 'BE68539007547034'},
        ],
      }),
    ]);
    final budget = _resource({'accountNumber': '5390 0754 7034'});
    final matched = receivingAccountForBudget(budget, accounts);
    expect(matched?.accountNumber, '539007547034');
    expect(matched, isNotNull);
  });

  test('authoritative budget number takes priority over mismatched bank info',
      () {
    final accounts = receivingAccountsFromResources([_prefill('budget-a')]);
    final budget =
        _resource({'budgetId': 'budget-a', 'accountNumber': '98765432'});
    expect(
        receivingAccountForBudget(budget, accounts)?.accountNumber, '98765432');
  });

  test('ambiguous receiving numbers for one budget need a real currency match',
      () {
    final accounts = receivingAccountsFromResources([
      _prefill('budget-a', currency: 'EUR'),
      _prefill('budget-a', number: '12345678', currency: 'GBP'),
    ]);
    final budget = _budget('budget-a');
    expect(receivingAccountForBudget(budget, accounts), isNull);
    expect(receivingAccountForBudget(budget, accounts, currency: 'GBP'),
        accounts.last);
    expect(
        receivingAccountForBudget(budget, accounts, currency: 'USD'), isNull);
  });

  test('synthetic PlatformResource IDs do not establish account ownership', () {
    final accounts = receivingAccountsFromResources([
      _resource({'accountNumber': '12345678', 'accountId': 'EUR'}),
    ]);
    final budget = _resource({'currency': 'EUR'});
    expect(budget.id, 'EUR');
    expect(receivingAccountForBudget(budget, accounts), isNull);
  });

  test('reads exact currency settlement details from the budget API', () {
    final budget = _resource({
      'budgetId': 'budget-a',
      'accountId': 'owner-a',
      'settlementDetails': {
        'balanceReference': 'reference-a',
        'currencyDetails': [
          {
            'currencyCode': 'EUR',
            'local': {'accountIdentifier': ' '},
            'international': {
              'accountIdentifier': 'BE68539007547034',
              'bankIdentifier': 'BBRUBEBB',
              'payeeName': 'Example Holder',
              'bankName': 'Example Bank',
            },
          },
          {
            'currencyCode': 'GBP',
            'local': {
              'accountIdentifier': '12345678',
              'bankIdentifier': '123456',
              'payeeName': 'Example Holder',
            },
            'international': {
              'accountIdentifier': 'GB82WEST12345698765432',
              'bankIdentifier': 'WESTGB2L',
            },
          },
        ],
      },
    });
    final details = receivingAccountsFromResources([budget]);
    expect(details, hasLength(2));
    expect(details.first.swift, 'BBRUBEBB');
    expect(details.last.accountNumber, 'GB82WEST12345698765432');
    expect(details.last.swift, 'WESTGB2L');
    expect(details.first.scopeIds, {'budget-a', 'owner-a'});
    expect(details.last.currencies, {'GBP'});
    expect(receivingAccountForBudget(budget, details), isNull);
    expect(
        receivingAccountForBudget(budget, details, currency: 'EUR')
            ?.accountNumber,
        details.first.accountNumber);
    expect(
        receivingAccountForBudget(budget, details, currency: 'GBP')
            ?.accountNumber,
        details.last.accountNumber);
    final embeddedOnly =
        receivingAccountForBudget(budget, const [], currency: 'EUR');
    expect(embeddedOnly?.accountNumber, 'BE68539007547034');
    expect(embeddedOnly?.scopeIds, {'budget-a', 'owner-a'});
  });

  test('GBP local details do not hide a shared international IBAN', () {
    PlatformResource budget(String id, String iban) => _resource({
          'budgetId': id,
          'accountId': 'shared-owner',
          'currencies': ['AED', 'GBP'],
          'settlementDetails': {
            'currencyDetails': [
              {
                'currencyCode': 'GBP',
                'local': {
                  'accountIdentifier': '12345678',
                  'bankIdentifier': '12-34-56',
                  'payeeName': 'Example Holder',
                },
                'international': {
                  'accountIdentifier': iban,
                  'bankIdentifier': 'WESTGB2L',
                  'payeeName': 'Example Holder',
                  'bankName': 'Example Bank',
                },
              },
              {
                'currencyCode': 'AED',
                'international': {
                  'accountIdentifier': iban,
                  'bankIdentifier': 'WESTGB2L',
                  'payeeName': 'Example Holder',
                  'bankName': 'Example Bank',
                },
              },
            ],
          },
        });
    final first = budget('budget-a', 'GB82WEST12345698765432');
    final second = budget('budget-b', 'GB29NWBK60161331926819');
    final accounts = receivingAccountsFromResources([first, second]);
    expect(accounts, hasLength(2));
    for (final selected in [first, second]) {
      final expected = selected == first
          ? 'GB82WEST12345698765432'
          : 'GB29NWBK60161331926819';
      for (final currency in [null, '', 'GBP', 'AED']) {
        final account =
            receivingAccountForBudget(selected, accounts, currency: currency);
        expect(account?.accountNumber, expected);
        expect(account?.isIban, isTrue);
        expect(account?.swift, 'WESTGB2L');
        expect(account?.copyAll, contains('IBAN: $expected'));
      }
    }
  });

  test('settlement details retain local routing when no IBAN is supplied', () {
    final budget = _resource({
      'budgetId': 'budget-local',
      'settlementDetails': {
        'currencyDetails': [
          {
            'currencyCode': 'GBP',
            'local': {
              'accountIdentifier': '12345678',
              'bankIdentifier': '12-34-56',
              'payeeName': 'Example Holder',
            },
            'international': {'accountIdentifier': null},
          },
        ],
      },
    });
    final account = receivingAccountForBudget(budget, const []);
    expect(account?.accountNumber, '12345678');
    expect(account?.isIban, isFalse);
    expect(account?.swift, isEmpty, reason: 'A sort code is not SWIFT.');
    expect(account?.holder, 'Example Holder');
  });
}

PlatformResource _resource(Map<String, dynamic> metadata) =>
    PlatformResource.fromJson(metadata);

PlatformResource _budget(String id) => _resource({
      'budgetId': id,
      'accountId': 'owner-a',
      'name': 'Account balance',
      'currencies': ['EUR', 'GBP'],
    });

PlatformResource _prefill(
  String budgetId, {
  String number = 'BE68539007547034',
  String currency = 'EUR',
}) =>
    _resource({
      'budgetId': budgetId,
      'accountId': 'owner-a',
      'accountNumber': number,
      'currency': currency,
    });

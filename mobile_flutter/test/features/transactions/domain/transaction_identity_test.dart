import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/transactions/domain/transaction_identity.dart';

void main() {
  final cards = [
    PaymentCard.fromJson({'id': '17', 'last4': '1462'}),
    PaymentCard.fromJson({'id': '18', 'last4': '8763'}),
  ];
  final accounts = [
    _account('account-eur', 'BE68539007547034', 'EUR'),
    _account('account-usd', 'GB29NWBK60161331926819', 'USD'),
  ];

  test('real card ID resolves its last four without guessing from title', () {
    final transaction = _transaction(cardId: '18', accountId: 'account-eur');
    expect(
      transactionIdentityLabel(transaction, cards: cards, accounts: accounts),
      'Card •••• 8763',
    );
    expect(
      transactionIdentityLabel(_transaction(cardId: 'missing'), cards: cards),
      isNull,
    );
  });

  test('card route identity resolves a resource that omits cardId', () {
    expect(
      transactionIdentityLabel(_transaction(), cards: cards, cardId: '17'),
      'Card •••• 1462',
    );
  });

  test('exact account reference selects real IBAN even across currencies', () {
    // The row is USD, but the reference is the EUR account. Currency must not
    // select another account and silently display somebody else's details.
    expect(
      transactionIdentityLabel(
        _transaction(accountId: 'account-eur'),
        accounts: accounts,
      ),
      'Account BE***7034',
    );
    expect(
        transactionIdentityLabel(_transaction(), accounts: accounts), isNull);
  });

  test('nested exact account metadata resolves without currency inference', () {
    expect(
      transactionIdentityLabel(
        _transaction(metadata: {
          'payment': {'source_account_id': 'account-usd'},
        }),
        accounts: accounts,
      ),
      'Account GB***6819',
    );
  });

  test('multiple matched accounts do not invent a single source identity', () {
    expect(
      transactionIdentityLabel(
        _transaction(metadata: {
          'sourceAccountId': 'account-eur',
          'destinationAccountId': 'account-usd',
        }),
        accounts: accounts,
      ),
      isNull,
    );
  });

  test('explicit source account number is usable without a roster', () {
    expect(
      transactionIdentityLabel(_transaction(metadata: {
        'sourceAccountNumber': '123456789',
      })),
      'Account ***6789',
    );
    expect(
      transactionIdentityLabel(_transaction(metadata: {
        'beneficiaryIban': 'BE68539007547034',
      })),
      isNull,
    );
  });

  test('receipt identity metadata is masked without altering amounts', () {
    expect(
      transactionMetadataDisplayValue(
          'beneficiary_iban', 'BE68 5390 0754 7034'),
      'BE***7034',
    );
    expect(
      transactionMetadataDisplayValue('CardNumber', '1234 5678 1234 1462'),
      '•••• 1462',
    );
    expect(transactionMetadataDisplayValue('accountNumber', '12345678'),
        '***5678');
    expect(transactionMetadataDisplayValue('amount', '12345678'), '12345678');
    expect(maskTransactionCardNumber('unavailable'), isNull);
    expect(maskTransactionAccountIdentifier('unknown'), isNull);
  });

  test('exact budget settlement linkage reaches transaction identity', () {
    final budgets = [
      _budget('budget-a', 'BE68539007547034'),
      _budget('budget-b', 'BE68539007549999'),
    ];
    expect(
      transactionIdentityLabel(
        _transaction(
          accountId: 'shared-owner',
          metadata: {'budgetId': 'budget-b'},
        ),
        budgets: budgets,
      ),
      'Account BE***9999',
    );
  });

  test('shared parent and same currency do not choose a budget identity', () {
    expect(
      transactionIdentityLabel(
        _transaction(accountId: 'shared-owner'),
        budgets: [_budget('budget-a', 'BE68539007547034')],
      ),
      isNull,
    );
    expect(
      transactionIdentityLabel(
        _transaction(
          accountId: 'shared-owner',
          metadata: {'budgetId': 'missing-budget'},
        ),
        accounts: [_account('shared-owner', 'BE68539007547034', 'USD')],
        budgets: [_budget('budget-a', 'BE68539007547034')],
      ),
      isNull,
      reason: 'A specific budget cannot fall back to its shared parent.',
    );
  });

  test('banking info augments only an exactly linked real budget', () {
    final budgets = [
      PlatformResource.fromJson({
        'budgetId': 'budget-a',
        'accountId': 'shared-owner',
      })
    ];
    final infos = [
      PlatformResource.fromJson({
        'budgetId': 'budget-a',
        'accountId': 'shared-owner',
        'accountNumber': 'BE68539007547034',
        'currency': 'USD',
      })
    ];
    expect(
      transactionIdentityLabel(
        _transaction(metadata: {'budgetId': 'budget-a'}),
        budgets: budgets,
        bankingInfo: infos,
      ),
      'Account BE***7034',
    );
    expect(
      transactionIdentityLabel(
        _transaction(metadata: {'budgetId': 'USD'}),
        budgets: [
          PlatformResource.fromJson({'currency': 'USD'})
        ],
        bankingInfo: infos,
      ),
      isNull,
      reason: 'A currency-derived PlatformResource.id is not a budget ID.',
    );
  });

  test('recipient card number cannot replace the account identity', () {
    expect(
      transactionIdentityLabel(
        _transaction(accountId: 'account-eur', metadata: {
          'recipients': [
            {'cardNumber': '1234567812341462'}
          ],
        }),
        accounts: accounts,
      ),
      'Account BE***7034',
    );
  });
}

LedgerTransaction _transaction({
  String cardId = '',
  String accountId = '',
  Map<String, dynamic> metadata = const {},
}) =>
    LedgerTransaction(
      id: 'transaction',
      title: 'Merchant 1462',
      subtitle: '',
      amount: const Money(currency: 'USD', minorUnits: -250),
      bookedAt: DateTime(2026, 9, 6, 10, 30),
      type: TransactionType.transfer,
      cardId: cardId,
      accountId: accountId,
      metadata: metadata,
    );

AccountBalance _account(String id, String iban, String currency) =>
    AccountBalance(
      id: id,
      name: 'Account',
      iban: iban,
      balance: Money(currency: currency, minorUnits: 0),
      available: Money(currency: currency, minorUnits: 0),
    );

PlatformResource _budget(String id, String iban) => PlatformResource.fromJson({
      'budgetId': id,
      'accountId': 'shared-owner',
      'settlementDetails': {
        'currencyDetails': [
          {
            'currencyCode': 'USD',
            'international': {'accountIdentifier': iban},
          },
        ],
      },
    });

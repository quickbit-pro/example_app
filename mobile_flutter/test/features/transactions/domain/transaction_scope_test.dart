import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/domain/transaction_scope.dart';

void main() {
  LedgerTransaction transaction({
    String accountId = '',
    String budgetId = '',
    Map<String, dynamic> metadata = const {},
  }) =>
      LedgerTransaction(
        id: 'transaction-1',
        title: 'Payment',
        subtitle: 'Completed',
        amount: const Money(currency: 'GBP', minorUnits: 100),
        bookedAt: DateTime(2026, 8, 31),
        type: TransactionType.payment,
        accountId: accountId,
        budgetId: budgetId,
        metadata: metadata,
      );

  test('matches a top-level budget identifier', () {
    expect(
      transactionMatchesScope(
        transaction(budgetId: 'F58977'),
        const ['f58977'],
      ),
      isTrue,
    );
  });

  test('matches nested provider metadata identifiers', () {
    expect(
      transactionMatchesScope(
        transaction(metadata: const {
          'provider': 'EqualsMoney',
          'transfer': {'destinationBudgetId': 'F58977'},
        }),
        const ['F58977'],
      ),
      isTrue,
    );
  });

  test('does not match unrelated metadata text', () {
    expect(
      transactionMatchesScope(
        transaction(metadata: const {
          'description': 'Payment for budget F58977',
        }),
        const ['F58977'],
      ),
      isFalse,
    );
  });
}

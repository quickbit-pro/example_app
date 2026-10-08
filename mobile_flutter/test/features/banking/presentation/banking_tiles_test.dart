import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/presentation/widgets/banking_tiles.dart';

void main() {
  testWidgets('recent transaction tile opens its details', (tester) async {
    var opened = false;
    final transaction = LedgerTransaction(
      id: 'txn-1',
      title: 'Card payment',
      subtitle: 'Completed',
      amount: const Money(currency: 'USD', minorUnits: -1250),
      bookedAt: DateTime(2026, 8, 31),
      type: TransactionType.card,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionTile(
            transaction: transaction,
            onTap: () => opened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Card payment'));

    expect(opened, isTrue);
  });
}

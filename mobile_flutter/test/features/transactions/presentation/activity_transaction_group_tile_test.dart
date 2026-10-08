import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/group_activity_transactions.dart';
import 'package:mobile_flutter/features/transactions/presentation/activity_transaction_group_tile.dart';

void main() {
  for (final width in [375.0, 1200.0]) {
    testWidgets('related records expand, collapse and open receipts at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final primary = LedgerTransaction.fromJson({
        'id': 'card',
        'type': 'card_unload',
        'title': 'Card Unload',
        'amount': 12,
      });
      final child = LedgerTransaction.fromJson({
        'id': 'wallet',
        'type': 'wallet_debit',
        'title': 'Wallet debit',
        'amount': 12,
      });
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: ActivityTransactionGroupTile(
          group: ActivityTransactionGroup(primary, [primary, child]),
          rowBuilder: (row) => ListTile(
            title: Text(row.title),
            onTap: () => opened.add(row.id),
          ),
        ),
      )));
      expect(find.text('Card Unload'), findsOneWidget);
      expect(find.text('Wallet debit'), findsNothing);
      await tester.tap(find.text('Card Unload'));
      expect(opened, ['card']);
      await tester.tap(find.text('Show 2 entries'));
      await tester.pumpAndSettle();
      expect(find.text('Card Unload'), findsNWidgets(2));
      expect(find.text('Wallet debit'), findsOneWidget);
      await tester.tap(find.text('Wallet debit'));
      expect(opened, ['card', 'wallet']);
      await tester.tap(find.text('Hide 2 entries'));
      await tester.pumpAndSettle();
      expect(find.text('Wallet debit'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

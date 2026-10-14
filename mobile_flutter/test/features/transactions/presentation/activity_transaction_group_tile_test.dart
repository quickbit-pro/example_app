import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/group_activity_transactions.dart';
import 'package:mobile_flutter/features/transactions/presentation/activity_transaction_group_tile.dart';

void main() {
  testWidgets('BoomFi group exposes action required before expansion', (tester) async {
    final primary = LedgerTransaction.fromJson({'id': '1', 'type': 'crypto_deposit', 'amount': 12, 'status': 'completed'});
    final child = LedgerTransaction.fromJson({'id': '2', 'type': 'withdrawal', 'amount': -12, 'status': 'requires_action', 'metadata': {'provider': 'BoomFi'}});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActivityTransactionGroupTile(
      group: ActivityTransactionGroup(primary, [primary, child]),
      rowBuilder: (row) => Text('Payment ${row.id}'),
    ))));
    expect(find.text('Verification required — open the related payment'), findsOneWidget);
    expect(find.text('Payment 2'), findsNothing);
    await tester.tap(find.text('Show 2 entries'));
    await tester.pumpAndSettle();
    expect(find.text('Payment 2'), findsOneWidget);
  });

  testWidgets('BoomFi expansion shows the linked payout without repeating conversion', (tester) async {
    final primary = LedgerTransaction.fromJson({'id': 'trade', 'type': 'exchange',
      'currency': 'USDC', 'amount': 15.9, 'metadata': {'provider': 'boomfi',
      'sellCurrency': 'USDC', 'buyCurrency': 'EUR', 'buyAmount': '13.92'}});
    final payout = LedgerTransaction.fromJson({'id': 'payout', 'type': 'withdrawal',
      'currency': 'EUR', 'amount': -13.92, 'metadata': {'provider': 'BoomFi'}});
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ActivityTransactionGroupTile(
      group: ActivityTransactionGroup(primary, [payout, primary]),
      rowBuilder: (row) => ListTile(title: Text(row.title), onTap: () => opened.add(row.id)),
    ))));
    await tester.tap(find.text('Show related transactions'));
    await tester.pumpAndSettle();
    expect(find.text('USDC → EUR'), findsOneWidget);
    expect(find.text('Bank withdrawal'), findsOneWidget);
    await tester.tap(find.text('Bank withdrawal'));
    expect(opened, ['payout']);
    await tester.tap(find.text('Hide related transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Bank withdrawal'), findsNothing);
  });

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

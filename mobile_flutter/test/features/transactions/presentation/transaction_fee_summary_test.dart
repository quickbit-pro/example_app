import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_fee_summary.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets('account fees fit and stay inset at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transaction = LedgerTransaction.fromJson({
        'id': 91191, 'type': 'payout', 'amount': -10, 'currency': 'EUR',
      }).withCardFees([LedgerTransaction.fromJson({
        'id': 91192, 'type': 'fee', 'amount': -.25,
        'currency': 'EUR', 'status': 'completed', 'title': 'Fee'
      })]);
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(width == 320 ? 1.5 : 1)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(16),
          child: TransactionFeeSummary(transaction: transaction))))));
      expect(find.text('Transaction fees'), findsOneWidget);
      expect(find.text('Card fees'), findsNothing);
      expect(find.text('Amount before fees'), findsOneWidget);
      expect(find.text('-€10.25'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Amount before fees')).dx, greaterThanOrEqualTo(32));
      final feeRight = tester.getBottomRight(find.text('EUR 0.25 · Charged')).dx;
      final totalRight = tester.getBottomRight(find.text('-€10.25')).dx;
      expect(feeRight, closeTo(totalRight, 1));
      expect(feeRight, lessThanOrEqualTo(width - 32));
      expect(tester.takeException(), isNull);
    });
  }
}

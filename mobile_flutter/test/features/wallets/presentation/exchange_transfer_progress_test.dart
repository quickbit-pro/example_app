import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';

void main() {
  for (final example in [false, true]) {
    for (final width in [375.0, 1440.0]) {
      testWidgets('settled bank flow and details at $width, Example $example', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transfer = BoomFiTransfer.fromJson({
          'id': 2, 'status': 'exchange_submitted', 'transferDirection': 'exchange_to_bank',
          'cryptoAmount': '12.58', 'cryptoCurrency': 'USDC', 'fiatCurrency': 'EUR',
          'fiatSettledAt': '2026-10-09T16:31:11.936Z',
          'fiatWithdrawalDeadlineAt': '2026-10-10T16:31:11.936Z',
          'boomFiOrderId': 'order_test', 'boomFiQuoteId': 'quote_test',
          'completionMessage': 'Conversion completed. Bank withdrawal is waiting for BoomFi to confirm the final settlement details. No withdrawal has been submitted.',
        });
        await tester.pumpWidget(ProviderScope(child: MaterialApp(
          theme: example ? ThemeData.dark().copyWith(extensions: [const ExampleBrand()]) : null,
          home: Scaffold(body: SingleChildScrollView(child: ExchangeTransferProgressCard(
            transfer: transfer, outflowsEnabled: false,
          ))),
        )));
        await tester.pumpAndSettle();
        expect(find.text('USDC → EUR → Bank account'), findsOneWidget);
        expect(find.text('Awaiting provider details'), findsOneWidget);
        expect(find.text('Withdraw to\nbank'), findsOneWidget);
        expect(find.textContaining('Crypto cards'), findsNothing);
        expect(find.textContaining('2026-10-10T'), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('View details'));
        await tester.pumpAndSettle();
        expect(find.text('Exchange ID: order_test'), findsOneWidget);
        expect(find.text('Conversion: completed'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

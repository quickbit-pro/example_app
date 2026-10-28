import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_deposit_history.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';

void main() {
  final completed = BoomFiTransfer.fromJson({
    'id': 133, 'status': 'completed', 'transferDirection': 'equals_to_interlace',
    'boomFiDepositPaymentId':'pay_linked', 'cryptoCurrency':'USDC',
    'cryptoAmount':'11.073355','fiatCurrency':'EUR', 'createdAt':'2026-10-26T19:21:00Z'
  });
  BoomFiDeposit deposit(String id, [String status = 'completed']) => BoomFiDeposit.fromJson({
    'id':1,'paymentId':id,'amount':'10','currency':'EUR','status':status,
  });
  testWidgets('linked funding is inside the journey and external deposit remains separate on mobile', (tester) async {
    tester.view.physicalSize = const Size(320, 1400); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [exchangeTransfersProvider.overrideWith((ref) async => [completed])],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [
        ExchangeDepositHistory(transfers:[completed], deposits: [deposit('pay_linked'),deposit('pay_external')]),
        ExchangeTransferProgressCard(transfer:completed, fundingDeposit:deposit('pay_linked'), outflowsEnabled:false),
      ]))))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deposit-pay_linked')), findsNothing);
    expect(find.byKey(const ValueKey('deposit-pay_external')), findsOneWidget);
    expect(find.text('Fiat account → Crypto card'), findsOneWidget);
    expect(find.text('Received by Exchange: 10 EUR'), findsOneWidget);
    expect(find.textContaining('11.073355'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
  testWidgets('unresolved verification stays visible even for linked funding', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [exchangeTransfersProvider.overrideWith((ref) async => [completed])],
      child: MaterialApp(home: Scaffold(body: ExchangeDepositHistory(transfers:[completed], deposits:[deposit('pay_linked','requires_action')])))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deposit-pay_linked')), findsOneWidget);
    expect(find.text('Verify the source of funds'), findsOneWidget);
  });
}

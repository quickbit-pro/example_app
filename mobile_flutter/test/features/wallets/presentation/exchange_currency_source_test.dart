import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';
import 'exchange_delivery_destinations_test.dart' show FlowApi;

void main() {
  for (final flow in [ExchangeFlow.convert, ExchangeFlow.withdraw]) {
    testWidgets('shared source balance retains required routes for $flow', (tester) async {
      tester.view.physicalSize = const Size(1200, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final overview = BoomFiExchangeOverview.fromJson({
        'balances': {'balances': [
          for (final chain in [(1399811149, 'Solana'), (1, 'Ethereum Mainnet'), (728126428, 'Tron')])
            {'account_id': chain.$1, 'currency': 'USDC', 'amount': '0.002487', 'chain': {'id': chain.$1, 'name': chain.$2}},
          {'account_id': 138, 'currency': 'EUR', 'amount': '0.53'},
        ]},
      });
      await tester.pumpWidget(ProviderScope(overrides: [
        mobilePlatformApiProvider.overrideWithValue(FlowApi()),
        exchangeCardDepositAddressesProvider.overrideWith((ref) async => []),
        payeesProvider.overrideWith((ref) async => []),
      ], child: MaterialApp(home: Scaffold(body: ExchangeFlowDialog(
        flow: flow, overview: overview, outflowsEnabled: true,
      )))));
      await tester.pumpAndSettle();
      DropdownButton<String> source() => tester.widgetList<DropdownButton<String>>(
        find.byType(DropdownButton<String>)).first;
      final usdc = source().items!.where((item) => item.value!.contains(':USDC:')).toList();
      expect(usdc.length, flow == ExchangeFlow.convert ? 1 : 3);
      expect(source().items!.where((item) => item.value!.contains(':EUR:')).length, 1);
      // Grouping retains a valid provider account/chain key and never sums the balance.
      expect(source().value, overview.balances.first.key);
      if (flow == ExchangeFlow.convert) {
        expect((usdc.single.child as Text).data, 'USDC · 0.002487');
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('EUR · 0.53').last);
        await tester.pumpAndSettle();
        final target = tester.widgetList<DropdownButton<String>>(
          find.byType(DropdownButton<String>)).elementAt(1);
        expect(target.items!.length, 3);
        expect(target.items!.map((item) => (item.child as Text).data), [
          'USDC · Solana · 0.002487',
          'USDC · Ethereum Mainnet · 0.002487',
          'USDC · Tron · 0.002487',
        ]);
      } else {
        expect((usdc.first.child as Text).data, 'USDC · Solana · 0.002487');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

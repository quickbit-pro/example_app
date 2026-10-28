import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_panel.dart';

void main() {
  Future<void> showOverview(WidgetTester tester,
      {required double amount,
      required bool outflows,
      bool compatibleCurrency = true}) async {
    final overview = BoomFiExchangeOverview(
      accountId: 1,
      accountName: 'Exchange',
      accountEnabled: true,
      accountState: 'ready',
      balances: [
        BoomFiExchangeBalance(
            accountId: 1,
            currency: 'USDC',
            amount: amount,
            pendingAmount: 0,
            chainId: 137,
            chainName: 'Polygon',
            tokenAddress: ''),
        if (compatibleCurrency)
          const BoomFiExchangeBalance(
              accountId: 2,
              currency: 'EUR',
              amount: 0,
              pendingAmount: 0,
              chainId: 0,
              chainName: '',
              tokenAddress: ''),
      ],
      settlementAccounts: const [],
      subAccounts: const [],
      fiatFundingCurrencies: const ['EUR'],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        exchangeOverviewProvider.overrideWith((ref) async => overview)
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExchangePanel(
              config: MobileTenantConfig.fromJson({
                'features': {'walletOutflowsEnabled': outflows},
              }),
              budgets: const [],
              wallets: const [],
              transferSection: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final outflows in [false, true]) {
    testWidgets('empty account has no warning with outflows $outflows',
        (tester) async {
      await showOverview(tester, amount: 0, outflows: outflows);
      expect(find.textContaining('Withdrawals are currently unavailable'),
          findsNothing);
      expect(find.textContaining('Deposit funds to start'), findsNothing);
      expect(find.textContaining('Conversion will be available'), findsNothing);
      for (final label in ['Withdraw', 'Convert']) {
        expect(
            tester
                .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, label))
                .onPressed,
            isNull);
      }
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Deposit'))
              .onPressed,
          isNotNull);
    });
  }

  testWidgets('funded account retains its actual withdrawal restriction',
      (tester) async {
    await showOverview(tester, amount: 25, outflows: false);
    expect(find.text('Withdrawals are currently unavailable for this account.'),
        findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Withdraw'))
            .onPressed,
        isNull);
  });

  testWidgets('funded account can withdraw when enabled', (tester) async {
    await showOverview(tester, amount: 25, outflows: true);
    expect(find.textContaining('Withdrawals are currently unavailable'),
        findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Withdraw'))
            .onPressed,
        isNotNull);
  });

  testWidgets('funded account retains missing conversion currency guidance',
      (tester) async {
    await showOverview(tester,
        amount: 25, outflows: true, compatibleCurrency: false);
    expect(
        find.text(
            'Conversion will be available when a compatible currency account is ready.'),
        findsOneWidget);
  });
}

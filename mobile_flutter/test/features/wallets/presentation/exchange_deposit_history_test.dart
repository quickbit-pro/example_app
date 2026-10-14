import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_deposit_history.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_detail_screen.dart';

Map<String, dynamic> fixture([String status = 'requires_action']) => {
      'id': 88664,
      'paymentId': 'pay_test',
      'amount': '12.582916',
      'currency': 'USDC',
      'chainId': 1,
      'status': status,
      'providerStatus': 'RequiresAction',
      'createdAt': '2026-10-09T11:58:51Z',
      'updatedAt': '2026-10-09T15:22:11Z',
      'transactionHash': '0xtest',
      'actionUrl': 'https://www.zbx.com/html/verify-transaction.html?token=test'
    };

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets('details stay compact and copy the complete hash at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const hash =
          '0xd06ed6b43b983142605a3950504fc30572da4905ff93038b97484f355d6115d0';
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ExchangeDepositCard(
        deposit: BoomFiDeposit.fromJson({
          ...fixture(),
          'transactionHash': hash,
          'settlementTransactionHash': hash
        }),
      )))));
      await tester.tap(find.text('Transaction details'));
      await tester.pumpAndSettle();
      expect(find.text('Blockchain transaction'), findsOneWidget);
      expect(find.text(hash), findsNothing);
      await tester.tap(find.byTooltip('Copy Blockchain transaction'));
      await tester.pumpAndSettle();
      expect(copied, hash);
      expect(find.text('Blockchain transaction copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final example in [false, true]) {
    testWidgets('deposit action and precise amount (Example $example)',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: example
              ? ThemeData.dark().copyWith(extensions: [const ExampleBrand()])
              : null,
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ExchangeDepositHistory(
                      deposits: [BoomFiDeposit.fromJson(fixture())])))));
      expect(find.text('12.582916 USDC'), findsOneWidget);
      expect(find.text('Verification required'), findsOneWidget);
      expect(find.text('Verify deposit'), findsOneWidget);
      expect(find.textContaining('Ethereum'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Activity deposit receipt uses current action (Example $example)',
        (tester) async {
      final deposit = BoomFiDeposit.fromJson(fixture());
      final tx = LedgerTransaction.fromJson({
        'id': 88664,
        'type': 'crypto_deposit',
        'amount': '12.582916',
        'currency': 'USDC',
        'status': 'requires_action',
        'metadata': {
          'boomFiDeposit': {...fixture(), 'actionUrl': null}
        }
      });
      await tester.pumpWidget(ProviderScope(
          overrides: [
            activityTransactionsProvider.overrideWith((ref) async => [tx]),
            exchangeOverviewProvider.overrideWith((ref) async =>
                BoomFiExchangeOverview(
                    accountId: 138,
                    accountName: 'Test',
                    accountEnabled: true,
                    accountState: 'Ready',
                    balances: [],
                    settlementAccounts: [],
                    subAccounts: [],
                    fiatFundingCurrencies: [],
                    deposits: [deposit])),
          ],
          child: MaterialApp(
              theme: example
                  ? ThemeData.dark().copyWith(extensions: [const ExampleBrand()])
                  : null,
              home: const TransactionDetailScreen(transactionId: '88664'))));
      await tester.pumpAndSettle();
      expect(find.text('12.582916 USDC'), findsOneWidget);
      expect(find.text('Verify deposit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final status in ['pending', 'completed', 'failed', 'cancelled']) {
    testWidgets('$status never exposes stale verification action',
        (tester) async {
      final deposit = BoomFiDeposit.fromJson(fixture(status));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ExchangeDepositCard(deposit: deposit))));
      expect(find.text(deposit.statusLabel), findsOneWidget);
      expect(find.text('Verify deposit'), findsNothing);
    });
  }
  test('rejects unsafe action links', () {
    for (final url in [
      'http://www.zbx.com/verify',
      'https://zbx.com.evil.test/',
      'https://www.zbx.com@evil.test/',
      'javascript:alert(1)'
    ]) {
      expect(
          BoomFiDeposit.fromJson({...fixture(), 'actionUrl': url})
              .verificationUrl,
          isNull);
    }
  });
}

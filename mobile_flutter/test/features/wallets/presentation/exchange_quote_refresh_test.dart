import 'dart:async';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_support.dart';
import 'exchange_account_transfers_test.dart' as fixtures;

class RefreshApi extends fixtures.TransferApi {
  int quotes = 0;
  bool failNext = false, failFunding = false;
  final fundingRequests = <Map<String, dynamic>>[];
  Map<String, dynamic> changes = {};
  Map<String, dynamic> fundingResult = {};
  Completer<Map<String, dynamic>>? pendingQuote, pendingFunding;
  final amounts = <String>[];
  Map<String, dynamic> result() => {
    'session': 'quote-$quotes',
    'expiry': DateTime.now().add(const Duration(seconds: 20)).toIso8601String(),
    'buy_amount': '11', 'buy_currency': 'USDC', 'rate': '1.1',
    'fees': {'total_fee': '0.1', 'fee_ccy': 'USDC'}, ...changes,
  };
  @override
  Future<Map<String, dynamic>> getExchangeQuote({required BoomFiExchangeBalance source,
    required BoomFiExchangeBalance destination, required String sellAmount,
    Map<String, dynamic>? bankWithdrawal, String? interlaceDestinationAddress}) async {
    quotes++;
    amounts.add(sellAmount);
    if (failNext) { failNext = false; throw StateError('Quote service unavailable'); }
    return pendingQuote == null ? result() : pendingQuote!.future;
  }
  @override
  Future<Map<String, dynamic>> fundExchange(Map<String, dynamic> request) async {
    submissions++;
    fundingRequests.add(Map.of(request));
    if (failFunding) throw StateError('Funding rejected');
    return pendingFunding == null ? fundingResult : pendingFunding!.future;
  }
}

void main() {
  Future<void> host(WidgetTester tester, RefreshApi api, {ExchangeFlow flow = ExchangeFlow.fund, List<PlatformResource>? budgets}) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overview = BoomFiExchangeOverview.fromJson({
      'fiatFundingCurrencies': ['EUR'],
      'balances': {'balances': [
        {'accountId': 1, 'currency': 'EUR', 'amount': 100},
        {'accountId': 2, 'currency': 'USDC', 'amount': 0, 'chain': {'id': 137, 'name': 'Polygon'}},
      ]},
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      mobilePlatformApiProvider.overrideWithValue(api),
      exchangeCardDepositAddressesProvider.overrideWith((ref) async => fixtures.addresses),
      payeesProvider.overrideWith((ref) async => []),
    ], child: MaterialApp(home: Scaffold(body: ExchangeFlowDialog(
      flow: flow, overview: overview, outflowsEnabled: true,
      budgets: budgets ?? [fixtures.budget(50)], wallets: fixtures.assets,
    )))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('exchange-amount')), '10');
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    expect(api.quotes, 1);
    expect(find.text('Quote refreshes automatically.'), findsOneWidget);
  }
  Future<void> agree(WidgetTester tester) async {
    tester.widget<ExchangeTerms>(find.byType(ExchangeTerms)).onChanged(true);
    await tester.pump();
  }
  FilledButton confirm(WidgetTester tester, [String label = 'Confirm and fund']) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  testWidgets('quote result and funding error scroll to the bottom on mobile', (tester) async {
    final api = RefreshApi();
    await host(tester, api);
    tester.view.physicalSize = const Size(390, 700);
    await tester.pumpAndSettle();
    final dialog = tester.widget<ExchangeDialog>(find.byType(ExchangeDialog));
    final scroll = dialog.scrollController!;
    scroll.jumpTo(0);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
    expect(scroll.offset, greaterThan(0));
    scroll.jumpTo(0);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    await agree(tester);
    api.failFunding = true;
    await tester.tap(find.text('Confirm and fund'));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
    expect(find.text('Get quote'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final flow in [ExchangeFlow.fund, ExchangeFlow.convert]) {
    testWidgets('refreshes $flow automatically without clearing the form or unchanged agreement', (tester) async {
      final api = RefreshApi();
      await host(tester, api, flow: flow);
      await agree(tester);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(api.quotes, 2);
      expect(api.amounts, ['10', '10']);
      expect(tester.widget<ExchangeTerms>(find.byType(ExchangeTerms)).accepted, isTrue);
      expect(confirm(tester, flow == ExchangeFlow.fund ? 'Confirm and fund' : 'Confirm exchange').onPressed, isNotNull);
      expect(api.submissions, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final change in [
    {'buy_amount': '10.9'}, {'rate': '1.09'},
    {'fees': {'total_fee': '0.2', 'fee_ccy': 'USDC'}},
  ]) {
    testWidgets('changed quote requires review: $change', (tester) async {
      final api = RefreshApi();
      await host(tester, api);
      await agree(tester);
      api.changes = change;
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(api.quotes, 2);
      expect(tester.widget<ExchangeTerms>(find.byType(ExchangeTerms)).accepted, isFalse);
      expect(find.textContaining('The rate or fees changed.'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
      expect(api.submissions, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('failed refresh blocks confirmation and retries in place', (tester) async {
    final api = RefreshApi();
    await host(tester, api);
    await agree(tester);
    api.failNext = true;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(api.quotes, 2);
    expect(find.text('Quote refresh failed. Retrying automatically…'), findsOneWidget);
    expect(tester.widget<ExchangeTerms>(find.byType(ExchangeTerms)).enabled, isFalse);
    expect(confirm(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(api.quotes, 3);
    expect(find.text('Quote refreshes automatically.'), findsOneWidget);
    expect(api.amounts, ['10', '10', '10']);
    expect(tester.widget<ExchangeTerms>(find.byType(ExchangeTerms)).accepted, isFalse);
    await agree(tester);
    expect(confirm(tester).onPressed, isNotNull);
    expect(api.submissions, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('refresh cannot overlap, confirm, or update a closed dialog', (tester) async {
    final api = RefreshApi();
    await host(tester, api);
    await agree(tester);
    api.pendingQuote = Completer();
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(api.quotes, 2);
    expect(find.text('Updating quote…'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 30));
    expect(api.quotes, 2);
    await tester.pumpWidget(const SizedBox());
    api.pendingQuote!.complete(api.result());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('editing cancels automatic refreshing', (tester) async {
    final api = RefreshApi();
    await host(tester, api);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(api.quotes, 1);
    expect(find.text('Get quote'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('funding uses the selected budget ID and preserves it after rejection', (tester) async {
    final api = RefreshApi()..failFunding = true;
    PlatformResource account(String id, String name) => PlatformResource.fromJson({
      'budgetId': id, 'accountId': 'shared-parent-account', 'name': name,
      'balances': [{'currency': 'EUR', 'availableBalance': 44.89}],
    });
    final selected = account('selected-eur-budget', 'Selected account');
    final other = account('other-eur-budget', 'Other account');
    await host(tester, api, budgets: [selected, other]);
    await agree(tester);
    await tester.tap(find.text('Confirm and fund'));
    await tester.pumpAndSettle();
    expect(api.fundingRequests.single['sourceBudgetId'], 'selected-eur-budget');
    expect(api.fundingRequests.single['fiatAmount'], 10);
    expect(find.textContaining('Funding rejected'), findsOneWidget);
    expect(find.text('Get quote'), findsOneWidget);
    expect(find.text('Updating expired quote…'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(api.quotes, 1);
    expect(api.submissions, 1);
    expect(find.textContaining('Funding rejected'), findsOneWidget);
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    await agree(tester);
    api.failFunding = false;
    api.pendingFunding = Completer();
    await tester.tap(find.text('Confirm and fund'));
    await tester.pump();
    expect(api.fundingRequests.last['sourceBudgetId'], 'selected-eur-budget');
    expect(api.fundingRequests.last['idempotencyKey'], api.fundingRequests.first['idempotencyKey']);
    expect(api.amounts, ['10', '10']);
    await tester.pumpWidget(const SizedBox());
    api.pendingFunding!.complete({});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved unfunded failure stays inline and permits a fresh manual attempt', (tester) async {
    final api = RefreshApi()..fundingResult = {
      'success': false, 'message': 'No payment was submitted.',
      'transfer': {'status': 'failed', 'sourceTransferId': null},
    };
    await host(tester, api);
    await agree(tester);
    await tester.tap(find.text('Confirm and fund'));
    await tester.pumpAndSettle();
    expect(find.byType(ExchangeFlowDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('No payment was submitted.'), findsOneWidget);
    expect(find.text('Get quote'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(api.submissions, 1);
    await tester.tap(find.text('Get quote'));
    await tester.pumpAndSettle();
    await agree(tester);
    api.pendingFunding = Completer();
    await tester.tap(find.text('Confirm and fund'));
    await tester.pump();
    expect(api.fundingRequests.last['idempotencyKey'], isNot(api.fundingRequests.first['idempotencyKey']));
    await tester.pumpWidget(const SizedBox());
    api.pendingFunding!.complete({});
    await tester.pump();
  });
  testWidgets('uncertain saved funding response cannot start another payment', (tester) async {
    final api = RefreshApi()..fundingResult = {
      'success': false, 'transfer': {'status': 'source_transfer_review_required'},
    };
    await host(tester, api);
    await agree(tester);
    await tester.tap(find.text('Confirm and fund'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Refresh transfers before sending again.'), findsOneWidget);
    expect(find.text('Confirm and fund'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(api.submissions, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('fund submission cancels automatic refreshing', (tester) async {
    final api = RefreshApi();
    await host(tester, api);
    await agree(tester);
    api.pendingFunding = Completer();
    await tester.tap(find.text('Confirm and fund'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(api.submissions, 1);
    expect(api.quotes, 1);
    await tester.pumpWidget(const SizedBox());
    api.pendingFunding!.complete({});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

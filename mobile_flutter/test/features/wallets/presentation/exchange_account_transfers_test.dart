import 'package:mobile_flutter/features/money/presentation/accounts_hub_header.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_transfer_routes.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_panel.dart';
import 'package:mobile_flutter/features/crypto/presentation/crypto_trade_screen.dart';

HoppaWalletAsset wallet(String network, {String symbol = 'USDC', double amount = 0, String address = ''}) =>
    HoppaWalletAsset(symbol: symbol, name: symbol, network: network, amount: amount,
        fiatValue: 0, address: address, tint: Colors.blue, walletId: 'same-wallet');
final addresses = [wallet('ETH', address: '0xowned'), wallet('MATIC', address: '0xowned')];
final assets = [wallet('', amount: 10), wallet('QuantumAccount', symbol: 'USD', amount: 50)];
PlatformResource budget(double euros) => PlatformResource(id: 'equals', title: 'My Equals account', subtitle: '', metadata: {
  'accountId': 'parent', 'currency': 'USD', 'supportedCurrencies': ['USD', 'EUR'],
  'balances': [{'currency': 'USD', 'available': 50}, {'currency': 'EUR', 'available': euros}],
});
BoomFiExchangeOverview overview({bool eurFunding = true, bool restricted = false, bool includeUsdt = false}) => BoomFiExchangeOverview.fromJson({
  'restrictedTradingCurrencies': restricted ? ['USDT'] : [],
  'account': {'id': 1, 'enabled': true, 'state': 'ready'},
  'balances': {'balances': [
    {'accountId': 1, 'currency': 'USDC', 'amount': 0, 'chain': {'id': 1, 'name': 'Ethereum'}},
    {'accountId': 2, 'currency': 'USDC', 'amount': 0, 'chain': {'id': 137, 'name': 'Polygon'}},
    {'accountId': 3, 'currency': 'EUR', 'amount': 0},
    if (includeUsdt) ...[
      {'accountId': 4, 'currency': 'USDT', 'amount': 0, 'chain': {'id': 1, 'name': 'Ethereum'}},
      {'accountId': 5, 'currency': 'USDT', 'amount': 0, 'chain': {'id': 137, 'name': 'Polygon'}},
    ],
  ]},
  'fiatFundingCurrencies': eurFunding ? ['EUR'] : [],
});

class TransferApi extends MobilePlatformApi {
  TransferApi() : super(Dio());
  Map<String, Object?>? sellRequest;
  BoomFiExchangeBalance? source, destination;
  int submissions = 0;
  @override
  Future<List<Map<String, dynamic>>> getExchangeDestinations({String? type}) async => [];
  @override
  Future<List<PlatformResource>> getEqualsBankingInfos() async => [];
  @override
  Future<Map<String, dynamic>> getInterlaceToEqualsQuote(Map<String, Object?> request) async {
    sellRequest = request;
    return {'rate': '1', 'buyAmount': '9', 'buyCurrency': 'EUR'};
  }
  @override
  Future<Map<String, dynamic>> getExchangeQuote({required BoomFiExchangeBalance source,
    required BoomFiExchangeBalance destination, required String sellAmount,
    Map<String, dynamic>? bankWithdrawal, String? interlaceDestinationAddress}) async {
    this.source = source; this.destination = destination;
    return {'session': 'quote', 'buyAmount': '9', 'buyCurrency': 'USDC', 'expiry': DateTime.now().add(const Duration(minutes: 2)).toIso8601String()};
  }
  @override
  Future<Map<String, dynamic>> fundExchange(Map<String, dynamic> request) async {
    submissions++;
    return {};
  }
}

void main() {
  test('overview reads camel-case funding currencies and account IDs', () {
    final result = overview();
    expect(result.fiatFundingCurrencies, ['EUR']);
    expect(result.balances.map((b) => b.accountId), [1, 2, 3]);
  });
  test('networkless balances are shared across exact routes, with Polygon first', () {
    final routes = exchangeTransferRoutes(addresses, assets);
    expect(routes.map((w) => exchangeChainId(w.network)), [137, 1]);
    expect(routes.map((w) => w.amount), [10, 10]);
    expect(routes.map(exchangeRouteKey).toSet(), hasLength(2));
    expect(exchangeTransferRoutes([wallet('ETH / MATIC', address: '0xowned')], assets), isEmpty);
    expect(exchangeTransferRoutes([addresses.first], assets).single.network, 'ETH');
  });

  Future<void> host(WidgetTester tester, TransferApi api, {
    bool outflows = true, bool eurFunding = true, double euros = 20,
    double width = 1200, double scale = 1,
    bool restricted = false, bool includeUsdt = false,
    Future<List<HoppaWalletAsset>>? addressFuture,
    Future<void> Function(PlatformResource)? convert,
    List<PlatformResource> Function()? freshBudgets,
  }) async {
    final testAssets = [...assets, if (includeUsdt) wallet('', symbol: 'USDT', amount: 20)];
    tester.view.physicalSize = Size(width, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: [
      exchangeOverviewProvider.overrideWith((ref) async => overview(eurFunding: eurFunding, restricted: restricted, includeUsdt: includeUsdt)),
      exchangeCardDepositAddressesProvider.overrideWith((ref) => addressFuture ?? Future.value(addresses)),
      hoppaWalletAssetsProvider.overrideWith((ref) async => testAssets),
      mobilePlatformApiProvider.overrideWithValue(api),
      budgetsProvider.overrideWith((ref) async => freshBudgets?.call() ?? [budget(euros)]),
      payeesProvider.overrideWith((ref) async => []),
    ], child: MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      AccountsHubHeader(selected: AccountsHubSection.exchange, showCrypto: true, showExchange: true,
        transferActions: ExchangeAccountTransferActions(
          config: MobileTenantConfig.fromJson({'features': {'walletOutflowsEnabled': outflows}}),
          budgets: [budget(euros)], wallets: testAssets, onConvertToEur: convert)),
      ExchangePanel(
        config: MobileTenantConfig.fromJson({'features': {'walletOutflowsEnabled': outflows}}),
        budgets: [budget(euros)], wallets: testAssets, onConvertToEur: convert,
        transferSection: const SizedBox.shrink()),
    ])))))));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('transfer tab row fits $width at $scale', (tester) async {
        await host(tester, TransferApi(), width: width, scale: scale);
        expect(tester.takeException(), isNull);
        final tabs = tester.getRect(find.byType(AccountsHubHeader));
        final funding = tester.getRect(find.widgetWithText(OutlinedButton, 'Fiat account to Crypto card'));
        final selling = tester.getRect(find.widgetWithText(OutlinedButton, 'Crypto card to Fiat account'));
        expect(funding.left, greaterThanOrEqualTo(0));
        expect(selling.right, lessThanOrEqualTo(width));
        expect(funding.height, greaterThanOrEqualTo(48));
        expect(tabs.contains(funding.center), isTrue);
        expect(tabs.contains(selling.center), isTrue);
        expect(find.text('Move money between your accounts'), findsNothing);
      });
    }
  }

  testWidgets('both directions open for networkless crypto balances; sell defaults to Polygon and EUR', (tester) async {
    final api = TransferApi();
    await host(tester, api);
    for (final title in ['Fiat account to Crypto card', 'Crypto card to Fiat account']) {
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, title)).onPressed, isNotNull);
    }
    await tap(tester, 'Crypto card to Fiat account');
    expect(find.textContaining('Available across networks: 10.000000 USDC'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Amount (USDC)'), '5');
    await tap(tester, 'Get quote');
    expect(api.sellRequest?['chainId'], 137);
    expect(api.sellRequest?['fiatCurrency'], 'EUR');
    expect(api.submissions, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('insufficient crypto offers Quantum conversion and does not request a transfer quote', (tester) async {
    final api = TransferApi();
    await host(tester, api);
    await tap(tester, 'Crypto card to Fiat account');
    await tester.enterText(find.widgetWithText(TextField, 'Amount (USDC)'), '15');
    await tester.pumpAndSettle();
    expect(find.text('Convert Quantum USD to USDC'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Get quote')).onPressed, isNull);
    await tap(tester, 'Convert Quantum USD to USDC');
    expect(tester.widget<CryptoTradeScreen>(find.byType(CryptoTradeScreen)).initialAsset, 'USDC');
    expect(api.sellRequest, isNull);
    expect(api.submissions, 0);
    await tester.pumpWidget(const SizedBox());
  });

  test('currency routes select Polygon, deduplicate, restrict USDT, and fall back to a supported network', () {
    final routes = [
      wallet('ETH', address: '0xeth'),
      wallet('MATIC', address: '0xpolygon'),
      wallet('ARB', address: '0xarb'),
      wallet('ETH', symbol: 'USDT', address: '0xeth'),
      wallet('MATIC', symbol: 'USDT', address: '0xpolygon'),
      wallet('ETH', symbol: 'BTC', address: '0xbtc'),
    ];
    final choices = exchangeTransferCurrencyRoutes(routes, canTrade: (_) => true);
    expect(choices.map((w) => w.symbol), ['USDC', 'USDT']);
    expect(choices.map((w) => exchangeChainId(w.network)), [137, 137]);
    expect(exchangeTransferCurrencyRoutes(routes, canTrade: (c) => c != 'USDT')
        .map((w) => w.symbol), ['USDC']);
    expect(exchangeTransferCurrencyRoutes([routes.first], canTrade: (_) => true)
        .single.network, 'ETH');
  });

  for (final restricted in [false, true]) {
    for (final funding in [false, true]) {
      testWidgets('currency-only choices restricted=$restricted funding=$funding', (tester) async {
        final api = TransferApi();
        await host(tester, api, restricted: restricted, includeUsdt: true,
          addressFuture: Future.value([
            ...addresses,
            wallet('ETH', symbol: 'USDT', address: '0xusdt'),
            wallet('MATIC', symbol: 'USDT', address: '0xusdt'),
          ]));
        await tap(tester, funding ? 'Fiat account to Crypto card' : 'Crypto card to Fiat account');
        final dropdown = tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .firstWhere((d) => d.items!.any((i) => i.child is Text
                ? (i.child as Text).data == 'USDC'
                : (i.value == 'USDC')));
        expect(dropdown.items, hasLength(restricted ? 1 : 2));
        expect(find.textContaining('USDC ·'), findsNothing);
        expect(find.textContaining('USDT ·'), findsNothing);
        if (!restricted) {
          dropdown.onChanged!(dropdown.items!.last.value);
          await tester.pumpAndSettle();
        }
        final currency = restricted ? 'USDC' : 'USDT';
        await tester.enterText(funding ? find.byType(TextField).first
            : find.widgetWithText(TextField, 'Amount ($currency)'), '5');
        await tap(tester, 'Get quote');
        if (funding) {
          expect(api.destination?.currency, currency);
          expect(api.destination?.chainId, 137);
        } else {
          expect(api.sellRequest?['currency'], currency);
          expect(api.sellRequest?['chainId'], 137);
        }
        expect(api.submissions, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('Move menu entry opens funding for the selected Fiat account, not the Exchange balance', (tester) async {
    final api = TransferApi();
    final selected = PlatformResource(id: 'selected', title: 'Selected Fiat account',
        subtitle: '', metadata: budget(44.89).metadata);
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: [
      mobileTenantConfigProvider.overrideWith((ref) async => MobileTenantConfig.fromJson({
        'features': {'boomFiExchangeEnabled': true, 'equalsMoneyEnabled': true, 'walletOutflowsEnabled': true},
      })),
      exchangeOverviewProvider.overrideWith((ref) async => overview()),
      exchangeCardDepositAddressesProvider.overrideWith((ref) async => addresses),
      hoppaWalletAssetsProvider.overrideWith((ref) async => assets),
      mobilePlatformApiProvider.overrideWithValue(api),
      payeesProvider.overrideWith((ref) async => []),
      budgetsProvider.overrideWith((ref) async => [budget(20), selected]),
    ], child: MaterialApp(home: Scaffold(body: Consumer(builder: (context, ref, _) => TextButton(
      onPressed: () => showFiatAccountToCryptoCardTransfer(context, ref,
          sourceBudget: selected, budgets: [budget(20), selected],
          onConvertToEur: (_) async {}),
      child: const Text('Open selected account transfer'),
    ))))));
    await tap(tester, 'Open selected account transfer');
    expect(find.text('Fiat account to Crypto card'), findsOneWidget);
    expect(find.text('Available in Fiat account: 44.89 EUR'), findsOneWidget);
    expect(find.text('From'), findsNothing);
    expect(find.text('EUR · 0.0'), findsNothing);
    final accountChoice = tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .firstWhere((d) => d.items!.any((i) => i.value == 'selected'));
    expect(accountChoice.value, 'selected');
    await tap(tester, 'Convert to EUR');
    expect(find.text('Available in Fiat account: 44.89 EUR'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '40');
    await tap(tester, 'Get quote');
    expect(api.source?.accountId, 3);
    expect(api.destination?.chainId, 137);
    expect(api.submissions, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Equals needs EUR; conversion refreshes the balance before the Polygon quote', (tester) async {
    final api = TransferApi();
    var converted = false;
    await host(tester, api, euros: 0,
      convert: (_) async { converted = true; },
      freshBudgets: () => [budget(converted ? 20 : 0)]);
    await tap(tester, 'Fiat account to Crypto card');
    await tester.enterText(find.byType(TextField).first, '5');
    await tap(tester, 'Get quote');
    expect(api.source, isNull);
    expect(find.textContaining('Convert funds to EUR'), findsOneWidget);
    await tap(tester, 'Convert to EUR');
    expect(converted, isTrue);
    expect(find.text('Available in Fiat account: 20.00 EUR'), findsOneWidget);
    expect(find.text('From'), findsNothing);
    await tap(tester, 'Get quote');
    expect(api.source?.currency, 'EUR');
    expect(api.destination?.chainId, 137);
    expect(api.submissions, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loading addresses recovers without requiring a balance network', (tester) async {
    final pending = Completer<List<HoppaWalletAsset>>();
    await host(tester, TransferApi(), addressFuture: pending.future);
    expect(find.text('Loading your Crypto card transfer networks…'), findsOneWidget);
    pending.complete(addresses);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Crypto card to Fiat account')).onPressed, isNotNull);
  });

  testWidgets('funding and withdrawal restrictions have visible reasons', (tester) async {
    await host(tester, TransferApi(), eurFunding: false);
    expect(find.textContaining('BoomFi has not provided EUR'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Fiat account to Crypto card')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Crypto card to Fiat account')).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await host(tester, TransferApi(), outflows: false);
    expect(find.text('Transfers are currently unavailable for this account.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Crypto card to Fiat account')).onPressed, isNull);
  });
}

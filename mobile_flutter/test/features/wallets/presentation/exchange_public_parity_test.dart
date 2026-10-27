import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_support.dart';

const overview = BoomFiExchangeOverview(
    accountId: 1,
    accountName: 'Exchange',
    accountEnabled: true,
    accountState: 'ready',
    balances: [
      BoomFiExchangeBalance(
          accountId: 1,
          currency: 'EUR',
          amount: 500,
          pendingAmount: 0,
          chainId: 0,
          chainName: '',
          tokenAddress: ''),
      BoomFiExchangeBalance(
          accountId: 2,
          currency: 'USDC',
          amount: 500,
          pendingAmount: 0,
          chainId: 137,
          chainName: 'Polygon',
          tokenAddress: 'token'),
    ],
    settlementAccounts: [],
    subAccounts: [],
    fiatFundingCurrencies: [
      'EUR'
    ]);
const budget = PlatformResource(
    id: 'budget-1',
    title: 'EUR account',
    subtitle: 'EUR',
    metadata: {'currency': 'EUR'});
const wallet = HoppaWalletAsset(
    symbol: 'USDC',
    name: 'USDC',
    network: 'Polygon',
    amount: 10,
    fiatValue: 10,
    address: '0x123',
    tint: Colors.blue,
    walletId: 'w1');

class FakeExchangeApi extends MobilePlatformApi {
  FakeExchangeApi() : super(Dio());
  final pending = Completer<Map<String, dynamic>>();
  int accepts = 0, funds = 0, overviews = 0;
  @override
  Future<List<Map<String, dynamic>>> getExchangeDestinations() async => [];
  @override
  Future<List<PlatformResource>> getEqualsBankingInfos() async => [];
  @override
  Future<Map<String, dynamic>> getExchangeQuote(
          {required BoomFiExchangeBalance source,
          required BoomFiExchangeBalance destination,
          required String sellAmount,
          Map<String, dynamic>? bankWithdrawal, String? interlaceDestinationAddress}) =>
      pending.future;
  @override
  Future<ActionResult> acceptExchangeQuote(String id) async {
    accepts++;
    return const ActionResult(message: 'Submitted');
  }

  @override
  Future<Map<String, dynamic>> fundExchange(
      Map<String, dynamic> request) async {
    funds++;
    return {'message': 'Submitted'};
  }

  @override
  Future<Map<String, dynamic>> getExchangeVerification() async =>
      {'status': 'not_started', 'eligible': true, 'hasProviderAccount': false};
  @override
  Future<BoomFiExchangeOverview> getExchangeOverview() async {
    overviews++;
    return overview;
  }

  void resolve({bool expired = false}) => pending.complete({
        'session': 'q1',
        'sell_amount': '25',
        'sell_currency': 'EUR',
        'buy_amount': '26',
        'buy_currency': 'USDC',
        'rate': '1.04',
        'fees': {'total_fee': '0.10', 'fee_ccy': 'EUR'},
        'expiry': DateTime.now()
            .add(Duration(seconds: expired ? -5 : 60))
            .toIso8601String()
      });
}

Future<void> host(WidgetTester tester, FakeExchangeApi api,
    {ExchangeFlow flow = ExchangeFlow.convert, bool outflows = true}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
      overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
      child: MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ExchangeFlowDialog(
                              flow: flow,
                              overview: overview,
                              outflowsEnabled: outflows,
                              budgets: const [budget],
                              wallets: const [wallet])),
                      child: const Text('Open')))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> quote(WidgetTester tester, FakeExchangeApi api,
    {bool expired = false}) async {
  await tester.enterText(find.byKey(const ValueKey('exchange-amount')), '25');
  await tester.tap(find.text('Get quote'));
  await tester.pump();
  api.resolve(expired: expired);
  await tester.pumpAndSettle();
}

class RecordingExchangeAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('saved Sumsub application requests server extraction without sending answers', () async {
    final adapter = RecordingExchangeAdapter();
    final api = MobilePlatformApi(Dio()..httpClientAdapter = adapter);
    await api.submitExchangeApplicationFromSumsub();
    expect(adapter.requests.single.path, '/api/v1/mobile/exchange/verification/application');
    expect(adapter.requests.single.data, {'answers': <String, String>{}, 'useSumsubAnswers': true});
  });

  test(
      'mobile exchange requests preserve the public verification and bank contracts',
      () async {
    final adapter = RecordingExchangeAdapter();
    final api = MobilePlatformApi(Dio()..httpClientAdapter = adapter);
    await api.submitExchangeApplication({'sdd_country_select': 'SI'});
    await api.getExchangeQuote(
        source: overview.balances.last,
        destination: overview.balances.first,
        sellAmount: '25',
        bankWithdrawal: {'accountNumber': 'DE89370400440532013000'});
    await api.fundExchange({'idempotencyKey': 'stable', 'fiatCurrency': 'EUR'});
    expect(adapter.requests.map((r) => r.path), [
      '/api/v1/mobile/exchange/verification/application',
      '/api/v1/mobile/exchange/quote',
      '/api/v1/mobile/exchange/equals-to-interlace/fund'
    ]);
    expect(
        jsonDecode(jsonEncode(adapter.requests.first.data))['answers']
            ['sdd_country_select'],
        'SI');
    expect(
        jsonDecode(jsonEncode(adapter.requests[1].data))['bankWithdrawal']
            ['accountNumber'],
        'DE89370400440532013000');
  });

  test('provider field casing, safe URLs, IBAN and keep policy', () {
    expect(exchangeText({'chain_id': 137}, 'chainId'), '137');
    expect(exchangeText({'BuyAmount': '12'}, 'buy_amount'), '12');
    expect(exchangeSafeUrl('https://user:pass@example.com'), isNull);
    expect(
        exchangeActionUrl(
            {'next_action': 'kyc_required:https://example.com/verify'}),
        'https://example.com/verify');
    expect(
        exchangeBankComplete({
          'accountNumber': 'DE89370400440532013000',
          'name': 'Payee',
          'bankName': 'Bank',
          'accountHolderName': 'Test',
          'country': 'DE'
        }),
        isTrue);
    expect(
        BoomFiTransfer.fromJson({
          'Status': 'awaiting_funds_decision',
          'TransferDirection': 'equals_to_interlace'
        }).canKeepFunds,
        isFalse);
  });
  test('new users cannot request balances before provider approval', () async {
    final api = FakeExchangeApi();
    final container = ProviderContainer(
        overrides: [mobilePlatformApiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    final result = await container.read(exchangeOverviewProvider.future);
    expect(result.isReady, isFalse);
    expect(api.overviews, 0);
  });
  testWidgets('quote request locks inputs and confirmation requires terms',
      (tester) async {
    final api = FakeExchangeApi();
    await host(tester, api);
    await tester.enterText(find.byKey(const ValueKey('exchange-amount')), '25');
    await tester.tap(find.text('Get quote'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('exchange-amount')))
            .enabled,
        isFalse);
    api.resolve();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm exchange'))
            .onPressed,
        isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Confirm exchange'));
    await tester.pumpAndSettle();
    expect(api.accepts, 1);
  });
  testWidgets('expired quote cannot be accepted', (tester) async {
    final api = FakeExchangeApi();
    await host(tester, api);
    await quote(tester, api, expired: true);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm exchange'))
            .onPressed,
        isNull);
    expect(api.accepts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets('funding requires quote review then explicit confirmation',
      (tester) async {
    final api = FakeExchangeApi();
    await host(tester, api, flow: ExchangeFlow.fund);
    await quote(tester, api);
    expect(api.funds, 0);
    expect(find.text('You receive 26 USDC'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Confirm and fund'));
    await tester.pumpAndSettle();
    expect(api.funds, 1);
  });
  testWidgets('disabled outflows allow quotes but never confirmation',
      (tester) async {
    final api = FakeExchangeApi();
    await host(tester, api, outflows: false);
    await quote(tester, api);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm exchange'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}

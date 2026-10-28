import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';

class FeesApi extends MobilePlatformApi {
  FeesApi() : super(Dio());
  int quotes = 0, payouts = 0, funding = 0;
  String buyAmount = '10';
  @override
  Future<List<Map<String, dynamic>>> getExchangeDestinations() async => [];
  @override
  Future<List<PlatformResource>> getEqualsBankingInfos() async => [];
  @override
  Future<Map<String, dynamic>> getExchangeQuote(
      {required BoomFiExchangeBalance source,
      required BoomFiExchangeBalance destination,
      required String sellAmount,
      Map<String, dynamic>? bankWithdrawal,
      String? interlaceDestinationAddress}) async {
    quotes++;
    return {
      'session': 'q',
      'expiry':
          DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      'buy_amount': buyAmount,
      'buy_currency': destination.currency
    };
  }

  @override
  Future<Map<String, dynamic>> withdrawExchangeCrypto(
      Map<String, dynamic> request) async {
    payouts++;
    return {};
  }

  @override
  Future<Map<String, dynamic>> fundExchange(
      Map<String, dynamic> request) async {
    funding++;
    return {};
  }
}

const wallet = HoppaWalletAsset(
    symbol: 'USDC',
    name: 'USD Coin',
    network: 'Ethereum',
    walletId: 'owned',
    amount: 0,
    fiatValue: 0,
    address: '0x1111111111111111111111111111111111111111',
    tint: Colors.blue);

Future<void> mount(WidgetTester tester, FeesApi api, ExchangeFlow flow) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overview = BoomFiExchangeOverview.fromJson({
    'fiat_funding_currencies': ['EUR'],
    'fiat_funding_fees_and_limits': {
      'EUR': {'min_deposit': '2', 'max_deposit': '50'}
    },
    'balances': {
      'balances': [
        {
          'account_id': 20,
          'currency': 'USDC',
          'amount': '200',
          'chain': {'id': 1, 'name': 'Ethereum'},
          'fees_and_limits': {
            'min_deposit': '99',
            'min_withdraw': '5',
            'max_withdraw': '100',
            'withdraw_fee': '1',
            'withdraw_fee_rate': '0'
          }
        },
        {
          'account_id': 10,
          'currency': 'EUR',
          'amount': '0',
          'fees_and_limits': {'min_deposit': '999'}
        },
      ]
    },
  });
  await tester.pumpWidget(ProviderScope(
      overrides: [
        mobilePlatformApiProvider.overrideWithValue(api),
        payeesProvider.overrideWith((ref) async => []),
        exchangeCardDepositAddressesProvider
            .overrideWith((ref) async => [wallet]),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: ExchangeFlowDialog(
        flow: flow,
        overview: overview,
        outflowsEnabled: true,
        wallets: const [wallet],
        budgets: const [
          PlatformResource(
              id: 'budget',
              title: 'EUR account',
              subtitle: '',
              metadata: {'currency': 'EUR', 'availableBalance': 100})
        ],
      )))));
  await tester.pumpAndSettle();
}

Future<void> enterAndPrepare(
    WidgetTester tester, String amount, String button) async {
  await tester.enterText(find.byKey(const ValueKey('exchange-amount')), amount);
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'withdrawal displays provider fees and blocks below/above limits before review',
      (tester) async {
    final api = FeesApi();
    await mount(tester, api, ExchangeFlow.withdraw);
    expect(find.text('Fixed withdrawal fee: 1 USDC'), findsOneWidget);
    expect(find.text('Minimum withdrawal: 5 USDC'), findsOneWidget);
    await enterAndPrepare(tester, '4.999999999999999999', 'Review withdrawal');
    expect(find.text('Minimum withdrawal is 5 USDC.'), findsOneWidget);
    await enterAndPrepare(
        tester, '100.000000000000000001', 'Review withdrawal');
    expect(find.text('Maximum withdrawal is 100 USDC.'), findsOneWidget);
    expect(api.payouts, 0);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Ethereum address'),
        wallet.address);
    await enterAndPrepare(tester, '5', 'Review withdrawal');
    expect(find.text('Confirm withdrawal'), findsOneWidget);
    expect(api.payouts, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'funding checks actual deposit rail before quote and delivery limit after quote',
      (tester) async {
    final api = FeesApi();
    await mount(tester, api, ExchangeFlow.fund);
    expect(find.text('Minimum deposit: 2 EUR'), findsOneWidget);
    expect(find.text('Maximum deposit: 50 EUR'), findsOneWidget);
    await enterAndPrepare(tester, '1', 'Get quote');
    expect(find.text('Minimum deposit is 2 EUR.'), findsOneWidget);
    await enterAndPrepare(tester, '51', 'Get quote');
    expect(find.text('Maximum deposit is 50 EUR.'), findsOneWidget);
    expect(api.quotes, 0);
    api.buyAmount = '4.99';
    await enterAndPrepare(tester, '2', 'Get quote');
    expect(find.text('Minimum withdrawal is 5 USDC.'), findsOneWidget);
    expect(find.text('Confirm and fund'), findsNothing);
    expect(api.quotes, 1);
    expect(api.funding, 0);
    api.buyAmount = '5';
    await enterAndPrepare(tester, '2', 'Get quote');
    expect(find.text('Confirm and fund'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

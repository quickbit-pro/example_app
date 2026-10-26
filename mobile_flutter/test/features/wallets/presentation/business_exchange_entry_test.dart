import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/money/presentation/accounts_hub_header.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';

import 'exchange_business_onboarding_test.dart' show BusinessApi;

class _Api extends BusinessApi {
  int verificationReads = 0;
  @override
  Future<Map<String, dynamic>> getExchangeVerification() {
    verificationReads++;
    return super.getExchangeVerification();
  }
}

Future<void> _pump(WidgetTester tester) async {
  // Other providers deliberately remain loading: onboarding must not wait on
  // the unrelated crypto or Equals requests, even while they animate.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Api> _mount(WidgetTester tester,
    {double width = 1200,
    bool enabled = true,
    bool bankReady = true,
    bool moneyPage = false,
    String budgetsState = 'ready'}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mobilePlatformApiProvider.overrideWithValue(api),
      mobileTenantConfigProvider.overrideWith((ref) async =>
          MobileTenantConfig.fromJson({
            'features': {
              'boomFiExchangeEnabled': enabled,
              'equalsMoneyEnabled': true,
              'walletOutflowsEnabled': false,
            },
          })),
      dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
            profile: UserProfile.fromJson({
              'accountType': 'business',
              'onboardingStatus': bankReady ? 'approved' : 'pending',
            }),
            accounts: const [],
            cards: const [],
            transactions: const [],
            onboarding: const [],
          )),
      hoppaWalletAssetsProvider.overrideWith(
          (ref) => Completer<List<HoppaWalletAsset>>().future),
      hoppaWalletAddressesProvider.overrideWith((ref) async => const []),
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) {
        if (budgetsState == 'loading') {
          return Completer<List<PlatformResource>>().future;
        }
        if (budgetsState == 'error') throw StateError('Equals unavailable');
        return Future.value(moneyPage ? <PlatformResource>[
          const PlatformResource(id: 'budget-1', title: 'Account balance', subtitle: 'Equals Money', metadata: {
            'provider': 'EqualsMoney', 'accountId': 'eq-1',
            'supportedCurrencies': ['EUR', 'USD'],
            'balances': [{'currency': 'EUR', 'amount': 100}, {'currency': 'USD', 'amount': 0}],
          }),
        ] : <PlatformResource>[]);
      }),
      kycDetailedStatusProvider.overrideWith((ref) async => const KycDetailedStatus(
        hoppaStatus: 'approved', bankStatus: 'approved', cardIssuerStatus: 'approved',
        nextAction: '', equalsMoneyAccountId: 'eq-1', equalsMoneyApproved: true,
      )),
      portfolioEstimateProvider.overrideWith((ref) async => PortfolioEstimate.fromJson({})),
      accountsProvider.overrideWith((ref) async => const []),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      payeesProvider.overrideWith((ref) async => const []),
      exchangeTransfersProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp(
      home: moneyPage ? const MoneyScreen() : const WalletsScreen(initialView: WalletView.exchange),
    ),
  ));
  await _pump(tester);
  return api;
}

void main() {
  testWidgets('Equals conversion remains on Money even with BoomFi disabled', (tester) async {
    final api = await _mount(tester, moneyPage: true, enabled: false);
    expect(find.text('Convert'), findsOneWidget);
    expect(find.text('Review business details'), findsNothing);
    await tester.tap(find.text('Convert'));
    await _pump(tester);
    expect(find.text('Convert funds'), findsOneWidget);
    expect(api.verificationReads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('company Accounts screen opens saved CORP details at $width',
        (tester) async {
      final api = await _mount(tester, width: width);
      expect(find.text('Review business details'), findsOneWidget);
      expect(find.text('Convert funds'), findsNothing);
      expect(find.text('Activate Exchange'), findsNothing);
      await tester.tap(find.text('Review business details'));
      await _pump(tester);
      expect(find.text('Saved Equals Company Ltd'), findsOneWidget);
      expect(api.starts, 0);
      expect(api.legacyCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('company Exchange is reachable before Equals banking is ready',
      (tester) async {
    await _mount(tester, bankReady: false);
    expect(tester.widget<AccountsHubHeader>(find.byType(AccountsHubHeader))
        .showExchange, isTrue);
    expect(find.text('Review business details'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final state in ['loading', 'error']) {
    testWidgets('Equals $state does not block company Exchange onboarding',
        (tester) async {
      await _mount(tester, budgetsState: state);
      expect(find.text('Review business details'), findsOneWidget);
      await tester.tap(find.text('Review business details'));
      await _pump(tester);
      expect(find.text('Saved Equals Company Ltd'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('disabled BoomFi hides Exchange navigation and does not show Equals conversion',
      (tester) async {
    final api = await _mount(tester, enabled: false);
    expect(find.text('Convert funds'), findsNothing);
    expect(find.text('Review business details'), findsNothing);
    expect(api.verificationReads, 0);
    expect(find.text('Exchange is not enabled for your account.'), findsOneWidget);
    expect(tester.widget<AccountsHubHeader>(find.byType(AccountsHubHeader))
        .showExchange, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart'
    as banking;
import 'package:mobile_flutter/features/dashboard/data/dashboard_providers.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/presentation/example_dashboard.dart';
import 'package:mobile_flutter/features/dashboard/presentation/widgets/example_balance_chart.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mobile_flutter/features/notifications/notifications.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  testWidgets(
      'Home top-up survives wallet dependency reload and opens fresh balances',
      (tester) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final refreshed = Completer<List<PlatformResource>>();
    var requests = 0;
    final container = _container(_CardApi(), assets: () {
      requests++;
      return requests == 1 ? Future.value([_wallet(100)]) : refreshed.future;
    });
    addTearDown(container.dispose);
    addTearDown(() {
      if (!refreshed.isCompleted) refreshed.complete([_wallet(250)]);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildAppThemes(_branding).light,
          home: const DashboardScreen()),
    ));
    await tester.pumpAndSettle();
    final home = tester.element(find.byType(ExampleDashboard));
    await tester.ensureVisible(find.text('Top up card'));
    await tester.tap(find.text('Top up card'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(requests, 2);
    expect(container.read(hoppaDashboardProvider).isReloading, isTrue);
    expect(find.byType(ExampleDashboard), findsOneWidget,
        reason:
            'Reloading wallet dependencies must not dispose the top-up caller.');
    expect(tester.element(find.byType(ExampleDashboard)), same(home));

    refreshed.complete([_wallet(250)]);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Manage balance'), findsOneWidget);
    expect(find.text('Crypto card balances'), findsOneWidget);
    expect(container.read(hoppaWalletAssetsProvider).requireValue.single.amount,
        250);
    expect(tester.element(find.byType(ExampleDashboard)), same(home));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Manage balance'), findsNothing);
    expect(find.text('Top up card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final remaining in [0.0, 3.0]) {
    test('Home keeps refreshed asset balance $remaining over stale fallbacks',
        () async {
      var available = 247.0;
      final container = _container(
        _CardApi(),
        assets: () async => [_wallet(available, currency: 'USDT')],
        walletFallback: [_wallet(247, currency: 'USDT')],
        accountFallback: [
          AccountBalance.fromJson({
            'id': 'old-account',
            'name': 'Crypto card',
            'provider': 'Interlace',
            'balance': {'currency': 'USDT', 'minorUnits': 24700},
            'available': {'currency': 'USDT', 'minorUnits': 24700},
          })
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(hoppaDashboardProvider, (_, __) {});
      addTearDown(subscription.close);
      expect(
          (await container.read(hoppaDashboardProvider.future))
              .accounts
              .single
              .balance,
          247);
      available = remaining;
      await container.refresh(userAssetsProvider.future);
      final updated = await container.read(hoppaDashboardProvider.future);
      expect(updated.accounts.single.balance, remaining);
      expect(updated.accounts.single.available, remaining);
    });
  }

  test('Home still uses wallet data when the asset currency is absent',
      () async {
    final container = _container(_CardApi(), walletFallback: [_wallet(12)]);
    addTearDown(container.dispose);
    expect(
        (await container.read(hoppaDashboardProvider.future))
            .accounts
            .single
            .balance,
        12);
  });

  test('card top-up refreshes the cached fallback accounts', () async {
    var calls = 0;
    final api = _TopUpApi();
    final container = ProviderContainer(overrides: [
      banking.mobileBankingApiProvider.overrideWithValue(api),
      banking.accountsProvider.overrideWith((ref) async {
        calls++;
        return [
          AccountBalance.fromJson({
            'id': 'wallet',
            'currency': 'USDT',
            'balance': api.toppedUp ? 0 : 247,
          })
        ];
      }),
    ]);
    addTearDown(container.dispose);
    await container.read(banking.accountsProvider.future);
    await container
        .read(banking.bankingActionControllerProvider.notifier)
        .topUpCard(
            cardId: 'first',
            amount: const Money(currency: 'USD', minorUnits: 24700));
    await container.read(banking.accountsProvider.future);
    expect(api.toppedUp, isTrue);
    expect(container.read(banking.bankingActionControllerProvider).hasError,
        isFalse);
    expect(calls, 2,
        reason: 'Top-up must discard the cached account snapshot.');
  });

  test('Home uses card detail balances and preserves a reported zero',
      () async {
    final api = _CardApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final home = await container.read(hoppaDashboardProvider.future);
    expect(home.cards.map((card) => card.balance.minorUnits), [7348, 0]);
    expect(home.cardBalancesAvailable, isTrue);
    expect(home.cards.first.balance,
        (await container.read(cardDetailProvider('first').future)).balance);
    expect(api.calls, {'first': 1, 'second': 1});
  });

  test('Home reacts when the Cards screen refreshes a balance', () async {
    final api = _CardApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final subscription = container.listen(hoppaDashboardProvider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(hoppaDashboardProvider.future);
    api.amount = '0.00';
    await container.refresh(cardDetailProvider('first').future);
    final home = await container.read(hoppaDashboardProvider.future);
    expect(home.cards.first.balance.minorUnits, 0);
    expect(home.cardBalancesAvailable, isTrue);
  });

  test('Home refresh fetches fresh card details with wallet valuation',
      () async {
    final api = _CardApi();
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(hoppaDashboardProvider.future);
    api.amount = '23.48';
    await container.read(refreshHoppaDashboardProvider)();
    final home = await container.read(hoppaDashboardProvider.future);
    expect(home.cards.first.balance.minorUnits, 2348);
    expect(home.cardBalancesAvailable, isTrue);
    expect(api.calls['first'], greaterThan(1));
    expect(api.calls['second'], greaterThan(1));
  });

  for (final mode in ['error', 'missing', 'wrong-card']) {
    test('A $mode detail cannot silently inflate Home with list balance',
        () async {
      final api = _CardApi()..mode = mode;
      final container = _container(api);
      addTearDown(container.dispose);
      final home = await container.read(hoppaDashboardProvider.future);
      expect(home.cardBalancesAvailable, isFalse);
      expect(home.cards, hasLength(2));
      api.mode = 'ok';
      await container.read(refreshHoppaDashboardProvider)();
      expect(
          (await container.read(hoppaDashboardProvider.future))
              .cardBalancesAvailable,
          isTrue);
    });
  }

  test('Cancelled cards do not require a live balance', () async {
    final api = _CardApi();
    final container = _container(api, cancelled: true);
    addTearDown(container.dispose);
    final home = await container.read(hoppaDashboardProvider.future);
    expect(home.cardBalancesAvailable, isTrue);
    expect(api.calls.keys, ['first']);
    expect(home.cards.last.status, CardStatus.cancelled);
  });

  for (final width in [393.0, 1440.0]) {
    for (final available in [true, false]) {
      testWidgets(
          'Home total matches current cards at $width, available=$available',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final api = _CardApi()..mode = available ? 'ok' : 'error';
        final container = _container(api);
        addTearDown(container.dispose);
        final snapshot = await tester
            .runAsync(() => container.read(hoppaDashboardProvider.future));
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppThemes(_branding).dark,
            home: ExampleDashboard(
                snapshot: snapshot!,
                unreadNotifications: 0,
                animateChart: false,
                onRefresh: () async {}),
          ),
        ));
        await tester.pumpAndSettle();
        if (available) {
          final chart = tester
              .widget<ExampleBalanceChart>(find.byType(ExampleBalanceChart));
          expect(chart.series.last, closeTo(78.37961747, .00001));
        } else {
          expect(find.text('Card balances unavailable · pull to refresh'),
              findsOneWidget);
          expect(find.textContaining('172.88'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

ProviderContainer _container(
  _CardApi api, {
  bool cancelled = false,
  Future<List<PlatformResource>> Function()? assets,
  List<PlatformResource> walletFallback = const [],
  List<AccountBalance> accountFallback = const [],
}) {
  final cards = [
    _card('first', '167.98'),
    _card('second', '94.50', status: cancelled ? 'cancelled' : 'active'),
  ];
  return ProviderContainer(overrides: [
    appConfigProvider.overrideWithValue(const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'https://example.invalid',
        branding: _branding)),
    unreadNotificationCountProvider.overrideWith((ref) async => 0),
    walletsProvider.overrideWith((ref) async => const []),
    mobilePlatformApiProvider.overrideWithValue(api),
    banking.cardsProvider.overrideWith((ref) async => cards),
    banking.dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
          profile: UserProfile.fromJson(
              const {'name': 'Customer', 'kycStatus': 'approved'}),
          accounts: const [],
          cards: cards,
          transactions: const [],
          onboarding: const [],
        )),
    banking.accountsProvider.overrideWith((ref) async => accountFallback),
    userAssetsProvider.overrideWith(
        (ref) async => assets == null ? const [] : await assets()),
    userWalletsProvider.overrideWith((ref) async => walletFallback),
    budgetsProvider.overrideWith((ref) async => const []),
    mobileTenantConfigProvider
        .overrideWith((ref) async => MobileTenantConfig.fromJson(const {})),
    currentTierProvider.overrideWith((ref) async => const PlatformResource(
        id: 'tier',
        title: 'Standard',
        subtitle: 'active',
        metadata: {'tierId': 1})),
    portfolioEstimateProvider.overrideWith((ref) async =>
        PortfolioEstimate.fromJson({'currency': 'USD', 'total': 4.89961747})),
  ]);
}

PaymentCard _card(String id, String amount, {String status = 'active'}) =>
    PaymentCard.fromJson({
      'id': id,
      'status': status,
      'balance': {'currency': 'USD', 'available': amount},
    });

class _CardApi extends MobilePlatformApi {
  _CardApi() : super(Dio());
  String amount = '73.48';
  String mode = 'ok';
  final calls = <String, int>{};
  @override
  Future<PaymentCard> getCardDetail(String cardId) async {
    calls.update(cardId, (value) => value + 1, ifAbsent: () => 1);
    if (cardId == 'second') return _card(cardId, '0.00');
    if (mode == 'error') {
      throw DioException(
          requestOptions: RequestOptions(path: '/cards/$cardId'));
    }
    if (mode == 'missing') return PaymentCard.fromJson({'id': cardId});
    return _card(mode == 'wrong-card' ? 'other' : cardId, amount);
  }
}

const _branding = AppBranding(
  brandId: 'example',
  appName: 'EXAMPLE',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

PlatformResource _wallet(double balance, {String currency = 'USD'}) =>
    PlatformResource(
      id: currency,
      title: currency,
      subtitle: '',
      metadata: {
        'currency': currency,
        'balance': balance,
        'balanceType': 'QuantumAccount',
      },
    );

class _TopUpApi extends MobileBankingApi {
  _TopUpApi() : super(Dio());
  bool toppedUp = false;

  @override
  Future<void> topUpCard(
      {required String cardId, required Money amount, String? token}) async {
    toppedUp = true;
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/brands/example/example_tokens.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/data/display_currency_provider.dart';
import 'package:mobile_flutter/features/dashboard/presentation/widgets/example_balance_chart.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/dashboard/presentation/example_dashboard.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/auth/application/biometric_providers.dart';
import 'package:mobile_flutter/features/auth/data/biometric_authenticator.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

const _tier = PlatformResource(
  id: 'tier-1',
  title: 'Standard',
  subtitle: 'active',
  metadata: {'tierId': 1, 'tierName': 'Standard'},
);

/// Every provider Home reads that would otherwise leave the test: the tenant
/// config behind the safeguarding statement (`GET /api/v1/mobile/config`) and
/// the biometric nudge's platform channels. Pinning them keeps the golden
/// hermetic and its pixels deterministic.
List<Override> _hermeticOverrides() => [
      currentTierProvider.overrideWith((ref) async => _tier),
      mobileTenantConfigProvider.overrideWith(
        (ref) async => MobileTenantConfig.fromJson(const {
          'company': {'name': 'Example'},
          'features': {'equalsMoneyEnabled': true},
        }),
      ),
      biometricCapabilityProvider.overrideWith(
        (ref) async => const BiometricCapability(
          available: false,
          types: [],
          reason: BiometricUnavailableReason.none,
        ),
      ),
      biometricEnrollmentProvider.overrideWith(
        (ref) async => const BiometricEnrollment(
          enabled: false,
          hasToken: false,
          email: '',
          userName: '',
          refreshToken: '',
        ),
      ),
    ];

void main() {
  for (final failedLookup in [false, true]) {
    testWidgets(
        'Home does not reopen setup for an existing tier or an unknown lookup: $failedLookup',
        (tester) async {
      final snapshot = HoppaDashboardSnapshot(
        customerName: _snapshot.customerName,
        accounts: _snapshot.accounts,
        holdings: _snapshot.holdings,
        activities: _snapshot.activities,
        cards: _snapshot.cards,
        onboardingProgress: _snapshot.onboardingProgress,
        marketSentiment: _snapshot.marketSentiment,
        requiresKyc: true,
        accountReady: _snapshot.accountReady,
        exchangeEnabled: _snapshot.exchangeEnabled,
        outflowsEnabled: _snapshot.outflowsEnabled,
        referralsEnabled: _snapshot.referralsEnabled,
        vouchersEnabled: _snapshot.vouchersEnabled,
        isBusinessAccount: false,
        portfolioEstimate: _snapshot.portfolioEstimate,
      );
      final router = GoRouter(initialLocation: '/home', routes: [
        GoRoute(
            path: '/home',
            builder: (_, __) => ExampleDashboard(
                snapshot: snapshot,
                unreadNotifications: 0,
                animateChart: false,
                onRefresh: () async {})),
        GoRoute(
            path: '/account-setup',
            builder: (_, __) =>
                const Scaffold(body: Text('Unexpected wizard'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            currentTierProvider.overrideWith((ref) async {
              if (failedLookup) throw StateError('Temporary outage');
              return _tier;
            }),
          ],
          child: MaterialApp.router(
              theme: buildAppThemes(_branding).light, routerConfig: router)));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('Unexpected wizard'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home currency selection converts the total and month graph',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentTierProvider.overrideWith((ref) async => _tier),
          homeDisplayRateProvider.overrideWith((ref) async {
            final currency = ref.watch(homeDisplayCurrencyProvider);
            return (currency: currency, rate: currency == 'USD' ? 1.0 : .5);
          }),
        ],
        child: MaterialApp(
            theme: buildAppThemes(_branding).light,
            home: ExampleDashboard(
                snapshot: _snapshot,
                unreadNotifications: 0,
                animateChart: false,
                onRefresh: () async {}))));
    await tester.pumpAndSettle();
    final original =
        tester.widget<ExampleBalanceChart>(find.byType(ExampleBalanceChart));
    await tester.tap(find.byTooltip('Balance currency'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'EUR'));
    await tester.pumpAndSettle();
    final converted =
        tester.widget<ExampleBalanceChart>(find.byType(ExampleBalanceChart));
    expect(converted.currency, 'EUR');
    expect(converted.series.last, closeTo(original.series.last * .5, .0001));
    expect(converted.series.delta, closeTo(original.series.delta * .5, .0001));
    expect(tester.takeException(), isNull);
  });

  for (final width in [393.0, 1000.0]) {
    testWidgets('Home top-up opens the displayed card directly at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var balanceRefreshes = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentTierProvider.overrideWith((ref) async => _tier),
          hoppaWalletAssetsProvider.overrideWith((ref) async {
            balanceRefreshes++;
            return [];
          }),
        ],
        child: MaterialApp(
          theme: buildAppThemes(_branding).light,
          home: ExampleDashboard(
            snapshot: _snapshot,
            unreadNotifications: 0,
            animateChart: false,
            onRefresh: () async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Top up card'));
      await tester.tap(find.text('Top up card'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      final dialog = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'NeoFullScreenDialog');
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Manage balance')),
          findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('EXAMPLE Card')),
          findsOneWidget);
      expect(find.textContaining('1234'), findsWidgets);
      expect(find.text('Crypto card balances'), findsOneWidget);
      expect(find.text('Available on card'), findsNothing);
      expect(balanceRefreshes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets('Home top-up reports the submitted result, fails=$fails',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = const Size(393, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _HomeBankingApi(fails: fails);
      final container = ProviderContainer(overrides: [
        currentTierProvider.overrideWith((ref) async => _tier),
        mobileBankingApiProvider.overrideWithValue(api),
        mobilePlatformApiProvider.overrideWithValue(_HomeEstimateApi()),
        hoppaWalletAssetsProvider.overrideWith((ref) async => const [
              HoppaWalletAsset(
                  symbol: 'USD',
                  name: 'USD',
                  network: '',
                  amount: 100,
                  fiatValue: 100,
                  address: '',
                  tint: Colors.grey,
                  walletId: 'usd'),
            ]),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildAppThemes(_branding).light,
            home: ExampleDashboard(
                snapshot: _snapshot,
                unreadNotifications: 0,
                animateChart: false,
                onRefresh: () async {})),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Top up card'));
      await tester.tap(find.text('Top up card'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.enterText(find.byType(TextField), '20');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.ensureVisible(find.text('Add to card'));
      await tester.tap(find.text('Add to card'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(api.cardId, _snapshot.cards.first.id);
      expect(api.amount?.minorUnits, 2000);
      expect(api.calls, 1);
      expect(
          find.text(fails
              ? 'We could not complete that request. Please try again.'
              : 'Card balance updated'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home card opens Cards with that card selected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (_, __) => ExampleDashboard(
              snapshot: _snapshot,
              unreadNotifications: 0,
              animateChart: false,
              onRefresh: () async {})),
      GoRoute(
          path: '/cards',
          builder: (_, state) =>
              Text(state.uri.queryParameters['cardId'] ?? 'none')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentTierProvider.overrideWith((ref) async => _tier),
        ],
        child: MaterialApp.router(
            routerConfig: router, theme: buildAppThemes(_branding).light)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('EXAMPLE Card'));
    await tester.tap(find.text('EXAMPLE Card'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/cards');
    expect(
        router
            .routerDelegate.currentConfiguration.uri.queryParameters['cardId'],
        'card-1');
  });

  test('Smart insights respects the original transaction status', () {
    final activity = HoppaActivity(
      id: 'declined',
      title: 'Card payment',
      subtitle: '',
      amount: -50,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: '',
      statusLabel: 'Completed',
      transaction: LedgerTransaction.fromJson({
        'id': 'declined',
        'amount': -50,
        'currency': 'USD',
        'status': 'DECLINED',
      }),
    );
    expect(activity.isCompletedOutgoing, isFalse);
  });

  testWidgets('Smart insights excludes unsuccessful outgoing payments',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final activities = [
      for (final status in [
        'Completed',
        'Declined',
        'Failed',
        'Rejected',
        'Cancelled',
        'Reversed',
        'Pending',
        'Processing',
        ''
      ])
        HoppaActivity(
          id: status,
          title: 'Purchase $status',
          subtitle: 'Card payment',
          amount: status == 'Completed' ? -10 : -100,
          currency: 'USD',
          kind: HoppaActivityKind.card,
          timeLabel: 'Today',
          statusLabel: status,
        ),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [currentTierProvider.overrideWith((ref) async => _tier)],
      child: MaterialApp(
          theme: buildAppThemes(_branding).light,
          home: ExampleDashboard(
              snapshot: _activitySnapshot(activities),
              animateChart: false,
              unreadNotifications: 0,
              onRefresh: () async {})),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Smart insights'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Spent this month'), findsOneWidget);
    expect(find.text('across 1 payment'), findsOneWidget);
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.text('Largest payment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [393.0, 1000.0]) {
    testWidgets('Home recent rows retain card and account identities at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = buildAppThemes(_branding).dark;
      final activities = [
        HoppaActivity(
          id: 'card-preview',
          title: 'Card purchase',
          subtitle: 'Card payment',
          amount: -9.99,
          currency: 'USD',
          kind: HoppaActivityKind.card,
          timeLabel: '6 Sep 2026 · 09:15',
          statusLabel: 'Completed',
          transaction: LedgerTransaction.fromJson({
            'id': 'card-preview',
            'cardId': 'card-1',
            'amount': -9.99,
            'currency': 'USD',
            'type': 'card_payment',
            'bookedAt': '2026-09-06T09:15:00Z',
          }),
        ),
        HoppaActivity(
          id: 'account-preview',
          title: 'Incoming transfer',
          subtitle: 'Transfer',
          amount: 42,
          currency: 'EUR',
          kind: HoppaActivityKind.transfer,
          timeLabel: 'Date unavailable',
          statusLabel: 'Completed',
          transaction: LedgerTransaction.fromJson({
            'id': 'account-preview',
            'accountId': 'eur-owned',
            'amount': 42,
            'currency': 'EUR',
            'type': 'transfer',
          }),
        ),
      ];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentTierProvider.overrideWith((ref) async => _tier),
          cardsProvider.overrideWith((ref) async => _snapshot.cards),
          accountsProvider.overrideWith((ref) async => const [
                AccountBalance(
                  id: 'eur-owned',
                  name: 'Euro',
                  iban: 'BE12345678901234',
                  balance: Money(currency: 'EUR', minorUnits: 42),
                  available: Money(currency: 'EUR', minorUnits: 42),
                ),
              ]),
        ],
        child: MaterialApp(
          theme: theme,
          home: ExampleDashboard(
            snapshot: _activitySnapshot(activities),
            animateChart: false,
            unreadNotifications: 0,
            onRefresh: () async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Card purchase'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Card •••• 1234'), findsOneWidget);
      expect(find.textContaining('6 Sep 2026 · 09:15'), findsOneWidget);
      expect(find.textContaining('Account BE***1234'), findsOneWidget);
      expect(find.textContaining('Date unavailable'), findsOneWidget);
      expect(find.textContaining('BE12345678901234'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('EXAMPLE home places its card shelf between balance and accounts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = buildAppThemes(_branding).dark;

    await tester.pumpWidget(
      ProviderScope(
        overrides: _hermeticOverrides(),
        child: MaterialApp(
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.dark,
          home: ExampleDashboard(
            animateChart: false,
            snapshot: _snapshot,
            unreadNotifications: 1,
            onRefresh: () async {},
            greetingTime: DateTime(2026, 1, 1, 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExampleWordmark), findsWidgets);
    expect(find.textContaining(', Naem'), findsOneWidget);
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Exchange'), findsAtLeastNWidgets(1));
    expect(find.text('USD Account'), findsOneWidget);
    expect(find.text('Fiat account US***5678'), findsOneWidget);
    expect(find.text('Euro Account'), findsOneWidget);
    expect(find.text('Fiat account EU***1234'), findsOneWidget);
    expect(find.text('Main account'), findsNothing);
    expect(find.textContaining('Main •'), findsNothing);
    expect(find.text('Crypto card'), findsNWidgets(3));
    expect(find.text('Crypto Wallet'), findsNothing);
    expect(find.text('1 asset'), findsNothing);
    final caption = find.text('Estimated · accounts and cards');
    expect(caption, findsOneWidget);
    expect(tester.widget<Text>(caption).style?.color,
        ExampleInk.primary(tester.element(caption)));
    expect(find.text('Estimated · some assets unavailable'), findsNothing);
    expect(find.text('Standard tier'), findsOneWidget);
    expect(find.text('EXAMPLE Card'), findsOneWidget);
    expect(find.text('Your card'), findsOneWidget);
    expect(find.text('All cards'), findsOneWidget);
    final balanceTop = tester.getTopLeft(find.text('Total balance')).dy;
    final cardTop = tester.getTopLeft(find.text('Your card')).dy;
    final accountsTop = tester.getTopLeft(find.text('Accounts')).dy;
    expect(cardTop, greaterThan(balanceTop));
    expect(accountsTop, greaterThan(cardTop));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(ExampleDashboard),
      matchesGoldenFile('goldens/example_home.png'),
    );
  });

  testWidgets('EXAMPLE home uses its desktop dashboard composition',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = buildAppThemes(_branding).dark;

    await tester.pumpWidget(
      ProviderScope(
        overrides: _hermeticOverrides(),
        child: MaterialApp(
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.dark,
          home: ExampleDashboard(
            animateChart: false,
            snapshot: _snapshot,
            unreadNotifications: 1,
            onRefresh: () async {},
            greetingTime: DateTime(2026, 1, 1, 9),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crypto card'), findsNWidgets(3));
    expect(find.text('3 balances'), findsNothing);
    expect(find.text('0.090899'), findsOneWidget);
    expect(find.text(r'$0.09 · Estimated'), findsOneWidget);
    expect(find.text(r'$1.30 · Estimated'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Send money'), findsOneWidget);
    // Quick actions are part of the desktop balance panel too.
    expect(find.text('Deposit'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recent activity'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final selection in const [
    (
      label: 'USD Account',
      currency: 'USD',
      budgetId: '',
    ),
    (
      label: 'Euro Account',
      currency: 'EUR',
      budgetId: 'equals/budget-eur',
    ),
  ]) {
    testWidgets('Home opens ${selection.currency} with its own account scope',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => ExampleDashboard(
              animateChart: false,
              snapshot: _snapshot,
              unreadNotifications: 0,
              onRefresh: () async {},
              greetingTime: DateTime(2026, 1, 1, 9),
            ),
          ),
          GoRoute(
            path: '/money',
            builder: (context, state) => const Scaffold(
              body: Text('Selected account'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final theme = buildAppThemes(_branding).dark;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentTierProvider.overrideWith((ref) async => _tier),
          ],
          child: MaterialApp.router(
            theme: theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.text(selection.label);
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      final location = router.routerDelegate.currentConfiguration.uri;
      expect(location.path, '/money');
      expect(location.queryParameters, {
        'currency': selection.currency,
        if (selection.budgetId.isNotEmpty) 'budgetId': selection.budgetId,
      });
      expect(find.text('Selected account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

const _branding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
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

final _snapshot = HoppaDashboardSnapshot(
  customerName: 'Naem',
  accounts: const [
    HoppaFiatAccount(
      id: 'usd',
      name: 'USD Account',
      currency: 'USD',
      balance: 4562.35,
      available: 4562.35,
      iban: 'US0012345678',
      tint: Colors.blue,
      provider: 'Equals Money',
      isPrimary: true,
    ),
    HoppaFiatAccount(
      id: 'eur',
      name: 'Euro Account',
      currency: 'EUR',
      balance: 6234.78,
      available: 6234.78,
      iban: 'EU0056781234',
      tint: Colors.blue,
      provider: 'Equals Money',
      budgetId: 'equals/budget-eur',
    ),
    HoppaFiatAccount(
      id: 'interlace-usd',
      name: 'USD balance',
      currency: 'USD',
      balance: 1.30,
      available: 1.30,
      iban: '',
      tint: Colors.purple,
      provider: 'Interlace',
    ),
    HoppaFiatAccount(
      id: 'interlace-usdc',
      name: 'USDC balance',
      currency: 'USDC',
      balance: .090899,
      available: .090899,
      iban: '',
      tint: Colors.blue,
      provider: 'Interlace',
    ),
    HoppaFiatAccount(
      id: 'interlace-usdt',
      name: 'USDT balance',
      currency: 'USDT',
      balance: .01,
      available: .01,
      iban: '',
      tint: Colors.green,
      provider: 'Interlace',
    ),
    HoppaFiatAccount(
      id: 'boom-eur',
      name: 'EUR balance',
      currency: 'EUR',
      balance: 63.25,
      available: 63.25,
      iban: '',
      tint: Colors.teal,
      provider: 'BoomFi',
    ),
  ],
  holdings: const [
    HoppaCryptoHolding(
      symbol: 'BTC',
      name: 'Bitcoin',
      amount: .1,
      fiatValue: 8987.25,
      price: 89872.5,
      changePercent: 8.7,
      tint: Colors.orange,
    ),
  ],
  activities: [
    HoppaActivity(
      id: 'tx-1',
      title: 'Spotify',
      subtitle: 'Card payment',
      amount: -9.99,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: 'Today, 09:15',
      bookedAt: DateTime(2026, 9, 7, 9, 15),
      statusLabel: 'Completed',
    ),
  ],
  cards: const [
    PaymentCard(
      id: 'card-1',
      label: 'EXAMPLE Card',
      last4: '1234',
      network: 'Mastercard',
      currency: 'USD',
      status: CardStatus.active,
      balance: Money(currency: 'USD', minorUnits: 456235),
      spendThisMonth: Money(currency: 'USD', minorUnits: 245075),
      limit: Money(currency: 'USD', minorUnits: 1000000),
      virtual: true,
    ),
  ],
  onboardingProgress: 1,
  marketSentiment: 'positive',
  requiresKyc: false,
  accountReady: true,
  exchangeEnabled: true,
  outflowsEnabled: true,
  referralsEnabled: true,
  vouchersEnabled: true,
  isBusinessAccount: false,
  portfolioEstimate: PortfolioEstimate(
    baseCurrency: 'USD',
    total: 24562.35,
    valuedAt: DateTime(2026, 9, 7, 13),
    isPartial: false,
    isStale: false,
    missingCurrencies: const [],
    providerTotals: const [
      PortfolioProviderTotal(
        provider: 'equalsmoney',
        total: 512.13,
        currency: 'USD',
        assetCount: 7,
        isAvailable: true,
        unpricedAssetCodes: [],
      ),
      PortfolioProviderTotal(
        provider: 'interlace',
        total: 2.29,
        currency: 'USD',
        assetCount: 5,
        isAvailable: true,
        unpricedAssetCodes: ['BTC', 'ETH'],
      ),
      PortfolioProviderTotal(
        provider: 'boomfi',
        total: 608.02,
        currency: 'USD',
        assetCount: 3,
        isAvailable: true,
        unpricedAssetCodes: [],
      ),
    ],
  ),
);

HoppaDashboardSnapshot _activitySnapshot(List<HoppaActivity> activities) =>
    HoppaDashboardSnapshot(
      customerName: 'Customer',
      accounts: const [],
      holdings: const [],
      activities: activities,
      cards: const [],
      onboardingProgress: 1,
      marketSentiment: '',
      requiresKyc: false,
      accountReady: true,
      exchangeEnabled: false,
      outflowsEnabled: false,
      referralsEnabled: false,
      vouchersEnabled: false,
      isBusinessAccount: false,
      portfolioEstimate: null,
    );

class _HomeBankingApi extends MobileBankingApi {
  _HomeBankingApi({required this.fails}) : super(Dio());
  final bool fails;
  String? cardId;
  Money? amount;
  int calls = 0;
  @override
  Future<void> topUpCard(
      {required String cardId, required Money amount, String? token}) async {
    this.cardId = cardId;
    this.amount = amount;
    calls++;
    if (fails) {
      throw DioException(requestOptions: RequestOptions(path: '/card/top-up'));
    }
  }
}

class _HomeEstimateApi extends MobilePlatformApi {
  _HomeEstimateApi() : super(Dio());
  @override
  Future<QuantumTopUpEstimate> getQuantumTopUpEstimate(
          {required Money amount}) async =>
      QuantumTopUpEstimate(
          success: true,
          usdAmount: amount.decimalAmount,
          topUpFee: 0,
          topUpFeePercent: 0);
}

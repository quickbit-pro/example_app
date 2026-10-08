import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_panel.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';
import 'package:mobile_flutter/flavors.dart';

/// The four widths the layout laws name.
const _widths = <double>[375, 393, 834, 1440];

const _exampleBranding = AppBranding(
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

/// A tenant with no `ExampleBrand` extension: the control group for every
/// "white-label is untouched" assertion in this file.
const _tenantBranding = AppBranding(
  appName: 'Hoppa',
  brandId: 'generic',
  primarySeedHex: '7C5CFF',
  accentSeedHex: '2DD4BF',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'Hoppa',
);

const _assets = [
  HoppaWalletAsset(
    symbol: 'USDC',
    name: 'USD Coin',
    network: 'Polygon',
    amount: 1420,
    fiatValue: 1310.44,
    address: '0xabc0000000000000000000000000000000000def',
    tint: Color(0xFF2775CA),
    walletId: 'w-usdc',
    canTopUp: true,
  ),
  HoppaWalletAsset(
    symbol: 'USDT',
    name: 'Tether',
    network: 'Tron',
    amount: 620.5,
    fiatValue: 572.18,
    address: 'TXabc0000000000000000000000000000000',
    tint: Color(0xFF26A17B),
    walletId: 'w-usdt',
  ),
];

const _budget = PlatformResource(
  id: 'equals-main',
  title: 'Account balance',
  subtitle: 'USD',
  metadata: {
    'accountId': 'equals-main',
    'displayName': 'Account balance',
    'currency': 'USD',
    'supportedCurrencies': ['USD', 'EUR'],
    'balances': [
      {'currency': 'USD', 'amount': '1240.00'},
      {'currency': 'EUR', 'amount': '86.00'},
    ],
  },
);

const _exchangeOverview = BoomFiExchangeOverview(
  accountId: 991,
  accountName: 'Example Exchange',
  accountEnabled: true,
  accountState: 'active',
  balances: [
    BoomFiExchangeBalance(
      accountId: 991,
      currency: 'USDC',
      amount: 2410.5,
      pendingAmount: 0,
      chainId: 137,
      chainName: 'Polygon',
      tokenAddress: '0x0',
    ),
    BoomFiExchangeBalance(
      accountId: 991,
      currency: 'USD',
      amount: 812.19,
      pendingAmount: 0,
      chainId: 0,
      chainName: '',
      tokenAddress: '',
    ),
  ],
  settlementAccounts: [],
  subAccounts: [],
  fiatFundingCurrencies: ['USD'],
);

/// How the addresses provider is behaving for a given case. The route header
/// has to survive all four, which is the point of hoisting it out of the data
/// branch.
enum _Addresses { data, empty, loading, failing }

List<Override> _overrides({
  _Addresses addresses = _Addresses.data,
  List<PlatformResource> budgets = const [_budget],
}) =>
    [
      mobileTenantConfigProvider.overrideWith(
        (ref) async => MobileTenantConfig.fromJson(const {
          'company': {'name': 'Example'},
          'features': {
            'equalsMoneyEnabled': true,
            'boomFiExchangeEnabled': true,
            'walletOutflowsEnabled': true,
          },
        }),
      ),
      dashboardProvider
          .overrideWith((ref) => Completer<DashboardSnapshot>().future),
      hoppaWalletAssetsProvider.overrideWith((ref) async => _assets),
      hoppaWalletAddressesProvider.overrideWith((ref) {
        switch (addresses) {
          case _Addresses.data:
            return Future<List<HoppaWalletAsset>>.value(_assets);
          case _Addresses.empty:
            return Future<List<HoppaWalletAsset>>.value(const []);
          case _Addresses.loading:
            return Completer<List<HoppaWalletAsset>>().future;
          case _Addresses.failing:
            return Future<List<HoppaWalletAsset>>.error(
              StateError('provider down'),
            );
        }
      }),
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => budgets),
      exchangeTransfersProvider.overrideWith((ref) async => const []),
      exchangeOverviewProvider.overrideWith(
        (ref) => Future<BoomFiExchangeOverview>.value(_exchangeOverview),
      ),
      // The budget details dialog reaches for these two; without the
      // overrides the test drives a real Dio at demo-api and the dialog
      // renders its failure branches instead of its content.
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      activityTransactionsProvider.overrideWith((ref) async => const []),
    ];

Widget _host({
  required Widget child,
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double textScale = 1,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      themeMode: ThemeMode.light,
      builder: (context, navigator) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: ExampleSheenScope(child: navigator ?? const SizedBox.shrink()),
      ),
      home: child,
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget app, {
  required double width,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// The exchange panel on its own, which is how the two cross-account transfer
/// dialogs are reached. The screen around it is covered elsewhere; what is
/// under test here is the dialog those two buttons open.
Widget _exchangePanelHost({
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  MobilePlatformApi? api,
}) =>
    _host(
      width: width,
      brightness: brightness,
      branding: branding,
      overrides: [
        ..._overrides(),
        if (api != null) mobilePlatformApiProvider.overrideWithValue(api),
      ],
      child: Scaffold(
        body: Consumer(
          builder: (context, ref, child) {
            final config = ref.watch(mobileTenantConfigProvider).valueOrNull;
            if (config == null) return const SizedBox.shrink();
            return SingleChildScrollView(
              child: ExchangePanel(
                config: config,
                budgets: const [_budget],
                wallets: _assets,
                transferSection: const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );

void main() {
  group('Deposit addresses route', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'names itself exactly once at $width in $brightness',
          (tester) async {
            await _pumpAt(
              tester,
              _host(
                width: width,
                brightness: brightness,
                overrides: _overrides(),
                child: const WalletsScreen(initialView: WalletView.addresses),
              ),
              width: width,
            );

            // The defect this replaces: the screen painted an ungoverned
            // Material `titleLarge` "Deposit addresses" and `_AddressList`
            // painted a `ExampleSectionTitle` saying the same three words
            // directly underneath it.
            expect(find.text('Deposit addresses'), findsOneWidget);
            expect(find.byType(ExampleSectionTitle), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('keeps its title through loading, empty and failure',
        (tester) async {
      for (final state in const [
        _Addresses.loading,
        _Addresses.empty,
        _Addresses.failing,
      ]) {
        await _pumpAt(
          tester,
          _host(
            width: 375,
            brightness: Brightness.dark,
            overrides: _overrides(addresses: state),
            child: const WalletsScreen(initialView: WalletView.addresses),
          ),
          width: 375,
        );

        // A header that only exists in the data branch is a header that pops
        // in when the request lands. This one belongs to the route.
        expect(
          find.text('Deposit addresses'),
          findsOneWidget,
          reason: 'missing header while addresses were $state',
        );
      }
    });

    testWidgets('holds at text scale 1.3 on the narrow phone', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.light,
          textScale: 1.3,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.addresses),
        ),
        width: 375,
      );

      expect(find.text('Deposit addresses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a white-label tenant keeps its Material heading',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.addresses),
        ),
        width: 375,
      );

      expect(find.text('Deposit addresses'), findsOneWidget);
      expect(find.byType(ExampleSectionTitle), findsNothing);
    });
  });

  group('Balances route', () {
    testWidgets('answers to one name on Example', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.balances),
        ),
        width: 375,
      );

      // "Fiat account" over a section called "Accounts & budgets" was two
      // different names for one screen, in two different type systems.
      expect(find.text('Accounts & budgets'), findsOneWidget);
      expect(find.text('Fiat account'), findsNothing);
    });

    testWidgets('a white-label tenant keeps both of its headings',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.balances),
        ),
        width: 375,
      );

      expect(find.text('Fiat account'), findsOneWidget);
      expect(find.text('Accounts & budgets'), findsOneWidget);
    });
  });

  group('Budget details dialog', () {
    for (final brightness in Brightness.values) {
      testWidgets('clears the 44 pt floor on every control in $brightness',
          (tester) async {
        await _pumpAt(
          tester,
          _host(
            width: 375,
            brightness: brightness,
            overrides: _overrides(),
            child: const WalletsScreen(initialView: WalletView.balances),
          ),
          width: 375,
        );

        final semantics = tester.ensureSemantics();

        await tester.tap(find.text('Details').first);
        await tester.pumpAndSettle();

        // The dialog opens with the latest-transactions frame already
        // expanded, so the pair that closes it is what is on screen first.
        // Both were already on the 44 pt floor; assert it, because they are
        // the siblings the third control has to match.
        for (final label in const <String>['More', 'Hide']) {
          final button = find.widgetWithText(TextButton, label);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button, findsOneWidget, reason: label);
          expect(
            tester.getSize(button).height,
            greaterThanOrEqualTo(44),
            reason: label,
          );
        }

        // Closing the frame is what reveals the control this test is about.
        await tester.tap(find.widgetWithText(TextButton, 'Hide'));
        await tester.pumpAndSettle();

        // "Show" was the one control on this dialog still sitting on
        // Material's 40 pt text-button floor, next to the "More"/"Hide" pair
        // that had already been lifted off it.
        final show = find.widgetWithText(TextButton, 'Show');
        await tester.ensureVisible(show);
        await tester.pumpAndSettle();
        expect(show, findsOneWidget);
        expect(tester.getSize(show).height, greaterThanOrEqualTo(44));

        // And it says which list it opens, rather than the bare word.
        expect(
          tester.getSemantics(show),
          matchesSemantics(
            label: 'Show the latest transactions',
            isButton: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        // And it does what it says.
        await tester.tap(show);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Hide'), findsOneWidget);

        semantics.dispose();
      });
    }
  });

  group('Cross-account transfer dialog', () {
    for (final width in <double>[375, 1440]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'spells its direction out at $width in $brightness',
          (tester) async {
            await _pumpAt(
              tester,
              _exchangePanelHost(width: width, brightness: brightness),
              width: width,
            );

            expect(find.text('Fiat to crypto'), findsOneWidget);
            await tester.tap(find.text('Fiat to crypto'));
            await tester.pumpAndSettle();

            expect(
              find.text('Fiat account to Crypto card'),
              findsOneWidget,
            );
            // U+2192 is outside what the bundled Geist subsets guarantee, and
            // the button that opened this dialog does not use one either.
            expect(find.textContaining('→'), findsNothing);
            expect(find.byType(ExampleGlassButton), findsWidgets);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('a white-label tenant keeps its arrow title', (tester) async {
      await _pumpAt(
        tester,
        _exchangePanelHost(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
        ),
        width: 375,
      );

      expect(find.text('Fiat → Crypto'), findsOneWidget);
      await tester.tap(find.text('Fiat → Crypto'));
      await tester.pumpAndSettle();

      expect(find.text('Fiat account → Crypto card'), findsOneWidget);
      expect(find.byType(ExampleGlassButton), findsNothing);
    });
  });

  group('Quote review', () {
    for (final brightness in Brightness.values) {
      testWidgets('reads as Example facts in $brightness', (tester) async {
        final api = MobilePlatformApi(Dio()..httpClientAdapter = _QuoteStub());
        await _pumpAt(
          tester,
          _exchangePanelHost(
            width: 375,
            brightness: brightness,
            api: api,
          ),
          width: 375,
        );

        await tester.tap(find.text('Crypto to fiat'));
        await tester.pumpAndSettle();
        expect(find.text('Crypto card to Fiat account'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'Amount (USDC)'),
          '25',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Get quote'));
        await tester.pumpAndSettle();

        // The figure that decides the transfer is a labelled amount with
        // tabular figures, not the tail of a sentence.
        expect(find.text('You receive'), findsOneWidget);
        expect(find.byType(ExampleAmount), findsWidgets);
        expect(find.textContaining('You receive:'), findsNothing);
        expect(find.text('Rate'), findsWidgets);
        expect(find.text('Fee'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a white-label tenant keeps the prose card', (tester) async {
      final api = MobilePlatformApi(Dio()..httpClientAdapter = _QuoteStub());
      await _pumpAt(
        tester,
        _exchangePanelHost(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          api: api,
        ),
        width: 375,
      );

      await tester.tap(find.text('Crypto → Fiat'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (USDC)'),
        '25',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get quote'));
      await tester.pumpAndSettle();

      expect(find.textContaining('You receive:'), findsOneWidget);
      expect(find.text('You receive'), findsNothing);

      // Documented, not fixed: the same unconstrained dropdown that used to
      // overflow on Example still overflows here by 16 px at 375. The fix is
      // `isExpanded: true` plus an ellipsising label, and it is deliberately
      // gated on Example so a white-label tenant's pixels do not move behind
      // its back. Draining it keeps this test honest about what it covers.
      expect(
        tester.takeException(),
        isA<FlutterError>(),
        reason: 'the white-label dropdown overflow is expected to persist',
      );
    });
  });
}

/// Answers every POST with one BoomFi-shaped quote, which is all these two
/// dialogs ask for before they render the review.
class _QuoteStub implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        '{"rate":"0.998400","buy_amount":"24.96","buy_currency":"USD",'
        '"fees":{"total_fee":"0.04","fee_ccy":"USD"},'
        '"expiry":"2026-09-04T12:30:00Z","session":"q-1"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
}

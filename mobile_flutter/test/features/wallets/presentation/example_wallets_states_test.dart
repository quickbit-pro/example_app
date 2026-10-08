import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';
import 'package:mobile_flutter/flavors.dart';

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

/// A tenant with no `ExampleBrand` extension: every Example branch must fall
/// through to the tree that shipped before this wave.
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

const _convertibleBudget = PlatformResource(
  id: 'equals-main',
  title: 'Account balance',
  subtitle: 'GBP',
  metadata: {
    'accountId': 'equals-main',
    'parentAccountId': 'equals-parent',
    'displayName': 'Account balance',
    'supportedCurrencies': ['GBP', 'EUR'],
    'balances': [
      {'currency': 'GBP', 'amount': '377.00'},
      {'currency': 'EUR', 'amount': '42.00'},
    ],
  },
);

final _assets = [
  const HoppaWalletAsset(
    symbol: 'USDC',
    name: 'USD Coin',
    network: 'Polygon',
    amount: 1420.0,
    fiatValue: 1310.44,
    address: '0xabc0000000000000000000000000000000000def',
    tint: Color(0xFF2775CA),
    walletId: 'w-usdc',
    canTopUp: true,
  ),
  const HoppaWalletAsset(
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

final _balances = [
  const HoppaWalletBalance(
    label: 'Main account',
    currency: 'EUR',
    available: 4820.75,
    reserved: 0,
  ),
];

/// Every provider `WalletsScreen` watches. `dashboardProvider` is deliberately
/// left pending: the screen reads it through `valueOrNull`, so a never
/// completing future is the honest stand-in for "still loading" and keeps the
/// test off `DashboardSnapshot`'s whole object graph.
List<Override> _overrides() => [
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
      hoppaWalletAddressesProvider.overrideWith((ref) async => _assets),
      hoppaWalletBalancesProvider.overrideWith((ref) async => _balances),
      budgetsProvider.overrideWith((ref) async => const []),
      exchangeTransfersProvider.overrideWith((ref) async => const []),
      exchangeOverviewProvider.overrideWith(
        (ref) => Completer<BoomFiExchangeOverview>().future,
      ),
    ];

Widget _host({
  required Widget child,
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double textScale = 1,
  bool reducedMotion = false,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      themeMode: ThemeMode.light,
      // The MediaQuery goes in through `builder`, above the Navigator, not
      // inside `home`. A dialog route is a sibling of `home` under that
      // Navigator, so an override placed in `home` never reaches it — which
      // is exactly how a reduced-motion assertion on a dialog ends up
      // measuring an un-reduced widget and passing anyway.
      builder: (context, navigator) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
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
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  group('Convert funds', () {
    // Regression: the footer was a `Row` with `CrossAxisAlignment.stretch`
    // inside `bottomNavigationBar`, so the bar measured itself against the
    // whole Scaffold and the form above it laid out at zero height. The
    // dialog opened with a heading and a CTA and no fields at all.
    for (final width in const [375.0, 1440.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('lays out the whole form at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              width: width,
              brightness: brightness,
              child: Consumer(
                builder: (context, ref, child) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showEqualsMoneyConversionDialog(
                        context,
                        ref,
                        const [_convertibleBudget],
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
            width: width,
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);

          // Every field the customer needs before committing money.
          expect(find.text('Account or budget'), findsOneWidget);
          expect(find.text('From'), findsOneWidget);
          expect(find.text('To'), findsOneWidget);
          expect(find.text('Rate'), findsOneWidget);
          expect(find.text('Fee'), findsOneWidget);
          expect(find.text('Estimate'), findsOneWidget);
          expect(find.text('Review conversion'), findsOneWidget);

          // And on the phone branch the scroller they sit in has real height,
          // which is the thing that actually broke: it measured zero. The
          // desktop branch above 900 px is a fixed-height column with no
          // viewport of its own, so the field assertions above are the whole
          // proof there.
          if (width < 900) {
            final list = find.byType(ListView);
            expect(list, findsOneWidget);
            expect(tester.getSize(list).height, greaterThan(100));
          }
        });
      }
    }
  });

  group('WalletsScreen', () {
    for (final width in const [375.0, 1440.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('renders the Example assets ledger at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              width: width,
              brightness: brightness,
              overrides: _overrides(),
              child: const WalletsScreen(initialView: WalletView.assets),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);

          // The ledger composition, not a stack of cards.
          expect(find.byType(ExampleListGroup), findsWidgets);
          // Money is tabular everywhere on the route.
          expect(find.byType(ExampleAmount), findsWidgets);
          // No un-converted Material CTA survives on the Example tree.
          expect(find.byType(FilledButton), findsNothing);
        });

        testWidgets('renders the exchange route at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              width: width,
              brightness: brightness,
              overrides: _overrides(),
              child: const WalletsScreen(initialView: WalletView.exchange),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          // Exchange is still loading, so the route must be showing the shape
          // of the ledger that is coming, never a bare spinner.
          expect(find.byType(ExampleSkeleton), findsWidgets);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(FilledButton), findsNothing);
        });
      }
    }

    testWidgets('a white-label tenant keeps its pre-Example tree',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.assets),
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleListGroup), findsNothing);
      expect(find.byType(ExampleGlassButton), findsNothing);
    });
  });
}

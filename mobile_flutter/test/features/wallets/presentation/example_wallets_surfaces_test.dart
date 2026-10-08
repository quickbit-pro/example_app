import 'dart:async';
import 'dart:math' as math;

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

/// The four widths the layout laws name: phone, the second phone the design
/// canvas uses, tablet, and desktop. Every structural assertion in this file
/// runs at all four, because a screen that only holds together at 375 and
/// 1440 is a screen with two untested breakpoints in the middle — and this
/// composition changes its mind at 560, 820 and 900.
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

/// A tenant with no `ExampleBrand` extension. Everything this file changes has
/// to leave this tree exactly as it found it.
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

final _assets = [
  const HoppaWalletAsset(
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
  // Unpriced and not USD-pegged, so the hero has to take its "some assets
  // unpriced" branch rather than the all-estimated one.
  const HoppaWalletAsset(
    symbol: 'ETH',
    name: 'Ethereum',
    network: 'Ethereum',
    amount: 0.482,
    fiatValue: 0,
    address: '0xdef0000000000000000000000000000000000abc',
    tint: Color(0xFF627EEA),
    walletId: 'w-eth',
  ),
];

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

/// A funded fiat budget, so the exchange route's cross-account transfer pair
/// is enabled rather than hidden. `_ExampleReadyExchangePanel` only offers the
/// two transfer buttons when there is somewhere to transfer to.
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

/// A second budget with a deliberately long name, so the accounts list has to
/// prove that the title gets the row's spare width instead of splitting it
/// 1:1 with a nine character balance.
const _secondBudget = PlatformResource(
  id: 'equals-contractors',
  title: 'Contractor payments',
  subtitle: 'EUR',
  metadata: {
    'accountId': 'equals-contractors',
    'budgetId': 'equals-contractors',
    'accountType': 'budget',
    'displayName': 'Contractor payments, third quarter',
    'currency': 'EUR',
    'supportedCurrencies': ['EUR'],
    'balances': [
      {'currency': 'EUR', 'amount': '8.20'},
    ],
  },
);

/// Every provider the screen watches. [exchangeReady] decides whether the
/// exchange route lands on the skeleton or on the live composer — the second
/// of which had no coverage at all before this file.
List<Override> _overrides({
  bool exchangeReady = false,
  List<PlatformResource>? budgets,
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
      // Read through `valueOrNull`, so a pending future is the honest stand-in
      // for "still loading" and keeps the test off the whole dashboard graph.
      dashboardProvider
          .overrideWith((ref) => Completer<DashboardSnapshot>().future),
      hoppaWalletAssetsProvider.overrideWith((ref) async => _assets),
      hoppaWalletAddressesProvider.overrideWith((ref) async => _assets),
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      activityTransactionsProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith(
        (ref) async => budgets ?? (exchangeReady ? const [_budget] : const []),
      ),
      exchangeTransfersProvider.overrideWith((ref) async => const []),
      exchangeOverviewProvider.overrideWith(
        (ref) => exchangeReady
            ? Future<BoomFiExchangeOverview>.value(_exchangeOverview)
            : Completer<BoomFiExchangeOverview>().future,
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
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Every `OutlinedButton` in the tree, with the border side it actually
/// resolves at rest. `styleFrom` returns `WidgetStateProperty`s, so the side
/// has to be resolved against an empty state set rather than read off the
/// style object.
Iterable<BorderSide> _restingSides(WidgetTester tester) sync* {
  for (final button in tester.widgetList<OutlinedButton>(
    find.byType(OutlinedButton),
  )) {
    final side = button.style?.side?.resolve(const <WidgetState>{});
    if (side != null) yield side;
  }
}

/// Alpha-composites [color] over [ground] and returns the WCAG 2.1 contrast
/// ratio. Both arguments are painted colours, not tokens: the laws ask for
/// the ratio *after* compositing, which is the step an alpha-carrying token
/// makes easy to skip.
double _contrast(Color color, Color ground) {
  final composited = Color.alphaBlend(color, ground);
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final a = luminance(composited);
  final b = luminance(ground);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Assets route', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('composes without overflow at $width in $brightness',
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

          // A RenderFlex overflow is reported as an exception in tests, so
          // this single assertion covers "nothing runs off the edge" at every
          // one of the four widths.
          expect(tester.takeException(), isNull);

          // The house vocabulary, not a stack of Material cards.
          expect(find.byType(ExampleListGroup), findsWidgets);
          expect(find.byType(ExampleAmount), findsWidgets);
          expect(find.byType(ExampleGlassPanel), findsWidgets);

          // Exactly one decisive action in the portfolio panel: the other
          // three are secondary by construction, so the route never becomes a
          // row of competing glass slabs.
          expect(find.byType(ExampleGlassButton), findsOneWidget);
          expect(find.byType(FilledButton), findsNothing);

          // All four hero actions are present and none of them is below the
          // 44 pt target floor.
          for (final label in const [
            'Exchange to crypto',
            'Exchange to USD',
            'Receive',
            'Send',
          ]) {
            expect(find.text(label), findsOneWidget, reason: label);
          }
          final outlined = find.byType(OutlinedButton);
          expect(outlined, findsNWidgets(3));
          for (var i = 0; i < 3; i++) {
            expect(
              tester.getSize(outlined.at(i)).height,
              greaterThanOrEqualTo(44),
            );
          }
          expect(
            tester.getSize(find.byType(ExampleGlassButton)).height,
            greaterThanOrEqualTo(44),
          );
        });

        testWidgets(
            'draws every operated edge at control contrast at $width in '
            '$brightness', (tester) async {
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

          final context = tester.element(find.byType(ExampleListGroup).first);
          final expected = ExampleBorders.controlSideOf(context).color;
          final structural = ExampleBorders.subtleSideOf(context).color;
          final sides = _restingSides(tester).toList();
          expect(sides, isNotEmpty);
          for (final side in sides) {
            // WCAG 1.4.11: the boundary of something the user operates is a
            // control edge, never the divider hairline. On paper the two are
            // 4.66:1 and 1.18:1, which is the whole point of the distinction.
            expect(side.color, expected);
            if (brightness == Brightness.light) {
              expect(side.color, isNot(structural));
            }
          }
        });
      }
    }

    testWidgets('the operated edge clears 3:1 on paper', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.light,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.assets),
        ),
        width: 375,
      );
      final context = tester.element(find.byType(ExampleListGroup).first);
      final palette = ExamplePalette.of(context);
      final edge = ExampleBorders.controlSideOf(context).color;
      // The edge is drawn over the button's own fill, which on paper is the
      // opaque light surface.
      expect(_contrast(edge, palette.surfaceLevel(1)), greaterThan(3));
    });

    testWidgets('holds together at text scale 1.3 on a 375 phone',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.light,
          textScale: 1.3,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.assets),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      // The labels ellipsise inside their buttons instead of widening the
      // row, so every action is still there at the larger scale.
      expect(find.text('Exchange to crypto'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.byType(ExampleGlassButton), findsOneWidget);
    });

    testWidgets('reduced motion lands on the settled figure, not a faster one',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          reducedMotion: true,
          overrides: _overrides(),
          child: const WalletsScreen(initialView: WalletView.assets),
        ),
        width: 375,
      );

      final hero = tester.widget<ExampleAmount>(find.byType(ExampleAmount).first);
      final context = tester.element(find.byType(ExampleListGroup).first);
      // The arrival tints the figure from secondary to primary. Under reduced
      // motion the settled colour has to be on screen on the first frame —
      // the final visual state, not a quicker route to it.
      expect(hero.color, ExampleInk.primary(context));
    });

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
      final context = tester.element(find.byType(WalletsScreen));
      expect(context.isExampleTheme, isFalse);
      expect(find.byType(ExampleListGroup), findsNothing);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.byType(ExampleGlassPanel), findsNothing);
    });
  });

  group('Exchange route, live composer', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'renders the composer and the ledger at $width in '
            '$brightness', (tester) async {
          await _pumpAt(
            tester,
            _host(
              width: width,
              brightness: brightness,
              overrides: _overrides(exchangeReady: true),
              child: const WalletsScreen(initialView: WalletView.exchange),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);

          // The composer's one CTA, and the balances as a single group.
          expect(find.text('Review exchange'), findsOneWidget);
          expect(find.byType(ExampleGlassButton), findsWidgets);
          expect(find.byType(ExampleListGroup), findsWidgets);
          expect(find.byType(FilledButton), findsNothing);

          // The swap control keeps the 44 pt target even though its disc is
          // 32, and it announces which two currencies it trades.
          expect(
            find.bySemanticsLabel('Swap USDC and USD'),
            findsOneWidget,
          );

          // Money is tabular on both legs and down the ledger.
          expect(find.byType(ExampleAmount), findsWidgets);
        });
      }
    }

    testWidgets('the transfer pair reads as words, never as arrow glyphs',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 834,
          brightness: Brightness.dark,
          overrides: _overrides(exchangeReady: true),
          child: const WalletsScreen(initialView: WalletView.exchange),
        ),
        width: 834,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Fiat to crypto'), findsOneWidget);
      expect(find.text('Crypto to fiat'), findsOneWidget);
      // U+2192 is not in the bundled Geist subsets and need not be in a
      // tenant's configured font either; on this route it renders as tofu.
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('holds together at text scale 1.3 on a 375 phone',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.light,
          textScale: 1.3,
          overrides: _overrides(exchangeReady: true),
          child: const WalletsScreen(initialView: WalletView.exchange),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Review exchange'), findsOneWidget);
    });

    testWidgets('a white-label tenant keeps the Material exchange panel',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _overrides(exchangeReady: true),
          child: const WalletsScreen(initialView: WalletView.exchange),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.byType(ExampleListGroup), findsNothing);
      // The arrow labels are pre-existing on this tree and must stay exactly
      // as they were: this file changes no white-label pixel.
      expect(find.text('Fiat → Crypto'), findsOneWidget);
      expect(find.text('Crypto → Fiat'), findsOneWidget);
    });
  });

  group('Balances route and embedded accounts', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'styles the embedded accounts and budgets at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              width: width,
              brightness: brightness,
              overrides: _overrides(budgets: const [_budget, _secondBudget]),
              child: const Scaffold(
                body: WalletsScreen(
                  initialView: WalletView.balances,
                  embedded: true,
                ),
              ),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(ExampleGlassPanel), findsWidgets);
          expect(find.byType(FilledButton), findsNothing);

          // Every fiat figure on the route is a ExampleAmount, so the symbol,
          // the grouping and the Private Mode mask are decided in one place.
          expect(find.byType(ExampleAmount), findsWidgets);
        });
      }
    }

    testWidgets('gives a long budget name the row it needs, not half of it',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(budgets: const [_budget, _secondBudget]),
          child: const Scaffold(
            body: WalletsScreen(
              initialView: WalletView.balances,
              embedded: true,
            ),
          ),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      final title = find.text('Contractor payments, third quarter');
      expect(title, findsOneWidget);

      final panel = find
          .ancestor(of: title, matching: find.byType(ExampleGlassPanel))
          .first;
      final panelWidth = tester.getSize(panel).width;
      final titleWidth = tester.getSize(title).width;
      final figureWidth = tester
          .getSize(
            find.descendant(of: panel, matching: find.byType(ExampleAmount)),
          )
          .width;

      // The budget holds €8.20, so the figure needs a fraction of the row.
      // Under the old `Expanded` title beside a `Flexible` figure the two
      // were handed exactly half the free space each whatever they needed,
      // and the name ellipsised at the midpoint with the balance's unused
      // half sitting empty next to it. The title now takes everything the
      // figure does not: more than half the panel, and more than twice the
      // figure.
      expect(figureWidth, lessThan(panelWidth * .3));
      expect(titleWidth, greaterThan(panelWidth * .5));
      expect(titleWidth, greaterThan(figureWidth * 2));
    });

    testWidgets('standalone budgets retain the existing account actions',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(budgets: const [_budget, _secondBudget]),
          child: const WalletsScreen(initialView: WalletView.balances),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Create budget'), findsOneWidget);
      expect(find.text('Transactions'), findsNWidgets(2));
      expect(find.text('Details'), findsNWidgets(2));
      expect(find.text('Latest'), findsNWidgets(2));
      expect(find.text('Fund'), findsOneWidget);
    });

    testWidgets('a white-label tenant keeps its budget cards', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _overrides(budgets: const [_budget, _secondBudget]),
          child: const WalletsScreen(initialView: WalletView.balances),
        ),
        width: 375,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassPanel), findsNothing);
      expect(find.byType(ExampleAmount), findsNothing);
    });
  });
}

// The Money hub hero, after it stopped being a balance over three grey discs.
//
// The design review of the rendered app said three things about this panel:
// the multi-currency sub-line was doing real work at caption size, two of the
// three action discs read as disabled, and the whole panel had one weight.
// This suite pins the answers, at the phone floor and the desktop shell, in
// both Twilight and Pearl daylight — a hero that resolves a different material
// per brightness is exactly the kind of thing that regresses in one theme
// while the other stays fine.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
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

/// A tenant that is not Example. Everything in this panel is gated on
/// `isExample`, and the guard the cross-screen glass suite provides mounts the
/// *payees* tab, which never builds this branch in either brand — so the
/// white-label proof for the hero has to live here.
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

const _tenantConfig = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: true,
  referralRegistrationMode: 'code',
  vouchersEnabled: false,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: false,
  walletOutflowsEnabled: false,
  equalsMoneyEnabled: true,
);

const _clearKyc = KycDetailedStatus(
  hoppaStatus: 'approved',
  bankStatus: 'approved',
  cardIssuerStatus: 'approved',
  nextAction: '',
  equalsMoneyAccountId: 'eq-1',
  equalsMoneyApproved: true,
  equalsMoneyStatus: 'active',
);

const _equalsAccount = AccountBalance(
  id: 'acc-1',
  name: 'Main account',
  iban: 'GB29NWBK60161331926819',
  balance: Money(currency: 'EUR', minorUnits: 729475),
  available: Money(currency: 'EUR', minorUnits: 729475),
  provider: 'EqualsMoney',
  supportedCurrencies: ['EUR', 'GBP', 'USD'],
);

/// The same fixture the review sheets render: EUR 7,294.75 promoted to the
/// hero, USD 4,562.35 and GBP 1,860.00 underneath it.
const _budgets = [
  PlatformResource(
    id: 'b1',
    title: 'Account balance',
    subtitle: 'Equals Money',
    metadata: {
      'id': 'b1',
      'name': 'Account balance',
      'provider': 'EqualsMoney',
      'balances': [
        {'currency': 'USD', 'amount': 4562.35},
        {'currency': 'EUR', 'amount': 6234.75},
      ],
    },
  ),
  PlatformResource(
    id: 'b2',
    title: 'Operations budget',
    subtitle: 'Equals Money',
    metadata: {
      'id': 'b2',
      'name': 'Operations budget',
      'provider': 'EqualsMoney',
      'balances': [
        {'currency': 'GBP', 'amount': 1860},
        {'currency': 'EUR', 'amount': 120},
      ],
    },
  ),
  PlatformResource(
    id: 'b3',
    title: 'Travel budget',
    subtitle: 'Equals Money',
    metadata: {
      'id': 'b3',
      'name': 'Travel budget',
      'provider': 'EqualsMoney',
      'balances': [
        {'currency': 'EUR', 'amount': 940},
      ],
    },
  ),
];

/// The same account holding five currencies: EUR is promoted to the hero,
/// three of the remaining four are drawn as pockets and the fifth is counted
/// rather than drawn. JPY is deliberate: [ExampleCurrencyAvatar] paints no
/// artwork for it, so its disc falls back to a 6 px glyph (`size: 20` times
/// the .3 scale the fallback gives a three-letter code) and the ISO code
/// beside the figure — 11 px, the floor `ExampleAmount` clamps a code span to —
/// is the larger of the two places the currency is named.
const _fiveCurrencyBudgets = [
  ..._budgets,
  PlatformResource(
    id: 'b4',
    title: 'Travel money',
    subtitle: 'Equals Money',
    metadata: {
      'id': 'b4',
      'name': 'Travel money',
      'provider': 'EqualsMoney',
      'balances': [
        {'currency': 'JPY', 'amount': 99000},
        {'currency': 'CHF', 'amount': 500},
      ],
    },
  ),
];

const _dashboard = DashboardSnapshot(
  profile: UserProfile(
    id: 'u-1',
    name: 'Test Customer',
    email: 'test@example.test',
    accountType: 'personal',
    kycStatus: 'approved',
    businessStatus: 'not_started',
    onboardingStatus: 'approved',
  ),
  accounts: [_equalsAccount],
  cards: [],
  transactions: [],
  onboarding: [],
);

List<Override> _overrides(List<PlatformResource> budgets) => [
      portfolioEstimateProvider
          .overrideWith((ref) async => PortfolioEstimate.fromJson({
                'currency': 'USD',
                'valuationRates': [
                  {'currency': 'EUR', 'rate': 1.16},
                  {'currency': 'AED', 'rate': 0.2723},
                  {'currency': 'RON', 'rate': 0.2214},
                  {'currency': 'USD', 'rate': 1},
                  {'currency': 'GBP', 'rate': 1.3},
                  {'currency': 'CHF', 'rate': 1.25},
                  {'currency': 'JPY', 'rate': 0.0068},
                ],
              })),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenantConfig),
      kycDetailedStatusProvider.overrideWith((ref) async => _clearKyc),
      dashboardProvider.overrideWith((ref) async => _dashboard),
      accountsProvider.overrideWith((ref) async => const [_equalsAccount]),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => budgets),
      payeesProvider.overrideWith((ref) async => const <Payee>[]),
      hoppaWalletAssetsProvider.overrideWith((ref) async => const []),
      hoppaWalletAddressesProvider.overrideWith((ref) async => const []),
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
    ];

const _widths = [375.0, 1440.0];

Widget _host({
  required double width,
  required Brightness brightness,
  double textScale = 1,
  bool reducedMotion = false,
  AppBranding branding = _exampleBranding,
  List<PlatformResource> budgets = _budgets,
  bool disabledSheenScope = false,
  ValueNotifier<MoneyTab>? screenTab,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  final router = GoRouter(
    initialLocation: '/money',
    routes: [
      GoRoute(
        path: '/money',
        // `disabledSheenScope` stands in for the shell, or for any ancestor
        // that has switched the alive layer off: the screen adds one of its
        // own only when nothing above it has.
        builder: (_, __) => screenTab != null
            ? ValueListenableBuilder<MoneyTab>(
                valueListenable: screenTab,
                builder: (_, tab, __) => MoneyScreen(initialTab: tab),
              )
            : disabledSheenScope
                ? const ExampleSheenScope(enabled: false, child: MoneyScreen())
                : const MoneyScreen(),
      ),
      GoRoute(path: '/money/pay', builder: (_, __) => const Text('Pay form')),
      GoRoute(path: '/money/payees', builder: (_, __) => const Text('Payees')),
      GoRoute(path: '/profile', builder: (_, __) => const Text('Profile')),
      GoRoute(
          path: '/wallets/assets', builder: (_, __) => const Text('Crypto')),
      GoRoute(
        path: '/wallets/addresses',
        builder: (_, __) => const Text('Deposit'),
      ),
      GoRoute(
        path: '/wallets/exchange',
        builder: (_, __) => const Text('Exchange'),
      ),
    ],
  );
  return ProviderScope(
    overrides: _overrides(budgets),
    child: MaterialApp.router(
      theme: theme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
  double textScale = 1,
  bool reducedMotion = false,
  AppBranding branding = _exampleBranding,
  List<PlatformResource> budgets = _budgets,
  bool disabledSheenScope = false,
  ValueNotifier<MoneyTab>? screenTab,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      width: width,
      brightness: brightness,
      textScale: textScale,
      reducedMotion: reducedMotion,
      branding: branding,
      budgets: budgets,
      disabledSheenScope: disabledSheenScope,
      screenTab: screenTab,
    ),
  );
  await tester.pumpAndSettle();
}

/// The opacity the hero's own chips are wrapped in, read through the chip's
/// label so the private widget type never has to be named.
double _chipOpacity(WidgetTester tester, String label) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text(label), matching: find.byType(Opacity)).first,
    )
    .opacity;

/// Width of the matte chip carrying [label] — the `DecoratedBox` the chip
/// paints its surface on, which is the closest one above the label and the
/// same box the surface-step assertion below reads. Found through the label so
/// the private widget type is never named.
double _chipWidth(WidgetTester tester, String label) => tester
    .getSize(
      find
          .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
          .first,
    )
    .width;

/// The string [amount] actually renders, runs joined. `ExampleAmount` sets the
/// numerals, the cents and the ISO code as spans of one `Text.rich`, so
/// `find.text` matches none of it and the widget's own `currency` and `code`
/// fields only say what was asked for, not what came out.
String _renderedAmount(WidgetTester tester, ExampleAmount amount) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byWidget(amount),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
    .join();

void main() {
  testWidgets('EUR leads the hero and account list after currency valuation',
      (tester) async {
    await _pumpAt(tester,
        width: 375,
        brightness: Brightness.light,
        budgets: const [
          PlatformResource(
              id: 'main',
              title: 'Account balance',
              subtitle: '',
              metadata: {
                'id': 'main',
                'name': 'Account balance',
                'provider': 'EqualsMoney',
                'balances': [
                  {'currency': 'AED', 'amount': 42.15},
                  {'currency': 'EUR', 'amount': 37.92},
                  {'currency': 'RON', 'amount': 10.29},
                ],
              }),
        ]);
    final amounts =
        tester.widgetList<ExampleAmount>(find.byType(ExampleAmount)).toList();
    expect(amounts.first.currency, 'EUR');
    expect(amounts.first.amount, 37.92);
    final euro = find.textContaining('Euro Account');
    final aed = find.textContaining('AED Account');
    await tester.scrollUntilVisible(aed.first, 150,
        scrollable: find.byType(Scrollable).first);
    expect(tester.getTopLeft(euro.first).dy,
        lessThan(tester.getTopLeft(aed.first).dy));
    expect(tester.takeException(), isNull);
  });

  group('Money accounts hero', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('lays out at $width in $brightness', (tester) async {
          await _pumpAt(tester, width: width, brightness: brightness);
          expect(tester.takeException(), isNull);

          // The masthead states the currency in artwork before the number
          // states it in a symbol, and the hero itself is unchanged: the
          // largest volume that fits, still carrying the promoted balance.
          // Asserted on the widget rather than on its text, because
          // `ExampleAmount` sets the whole units, the cents and the ISO code as
          // three spans of one `Text.rich` and `find.text` matches none of it.
          expect(find.text('MONEY BALANCE'), findsOneWidget);
          final hero = tester
              .widgetList<ExampleAmount>(find.byType(ExampleAmount))
              .where(
                (amount) =>
                    amount.size == ExampleAmountSize.hero ||
                    amount.size == ExampleAmountSize.large,
              )
              .toList();
          expect(hero, hasLength(1));
          expect(hero.single.currency, 'EUR');
          expect(hero.single.amount, closeTo(7294.75, .001));
        });
      }
    }

    testWidgets('the other currencies are pockets, not a caption',
        (tester) async {
      await _pumpAt(tester, width: 375, brightness: Brightness.dark);

      // Was: a single 12 px Text reading "$4,562.35   £1,860.00". Each
      // currency is now its own object with its own flag, and its figure is
      // set at the row volume rather than at caption size.
      expect(find.text(r'$4,562.35   £1,860.00'), findsNothing);

      final pockets = tester
          .widgetList<ExampleAmount>(find.byType(ExampleAmount))
          .where((amount) => amount.size == ExampleAmountSize.small)
          .toList();
      expect(
        pockets.map((amount) => amount.currency),
        containsAll(<String>['USD', 'GBP']),
      );
      expect(pockets.every((amount) => amount.animate), isFalse);

      // One disc for the hero currency and one per pocket. The avatar paints
      // real flag artwork, so EUR and USD are told apart without reading.
      final avatars = tester
          .widgetList<ExampleCurrencyAvatar>(find.byType(ExampleCurrencyAvatar))
          .map((avatar) => avatar.code)
          .toList();
      expect(avatars, containsAll(<String>['EUR', 'USD', 'GBP']));
    });

    testWidgets('the primary action is the house glass and it is enabled',
        (tester) async {
      await _pumpAt(tester, width: 375, brightness: Brightness.dark);

      final glass = tester.widget<ExampleGlassButton>(
        find.widgetWithText(ExampleGlassButton, 'Add money'),
      );
      expect(glass.tone, ExampleGlassButtonTone.primary);
      // It sits inside the panel's own ExampleAtmosphere, so it samples that
      // light rather than inventing a haze.
      expect(glass.ground, ExampleGlassGround.atmosphere);
      // The panel already carries the screen's lit hairline; one moving
      // object per surface.
      expect(glass.sheen, isFalse);
      expect(glass.onPressed, isNotNull);
      expect(
        tester.getSize(find.byType(ExampleGlassButton)).height,
        greaterThanOrEqualTo(ExampleGlassButton.minTouchTarget),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets(
          'an unavailable action reads unavailable beside it '
          'in $brightness', (tester) async {
        await _pumpAt(tester, width: 375, brightness: brightness);

        // This fixture has no convertible budget — the balances carry no
        // parent account — so Convert is genuinely unavailable while New
        // budget is not. That is the exact pair the review called out: three
        // identical discs could not tell them apart, and a chip at
        // ExampleOpacity.disabled beside a full-strength chip and a filled CTA
        // can.
        expect(_chipOpacity(tester, 'Convert'), ExampleOpacity.disabled);
        expect(_chipOpacity(tester, 'New budget'), 1);

        // And the chips are a surface step above the panel they rest on. At
        // level 1 — the panel's own ground — a chip would be the exact same
        // colour in Twilight, and only its hairline would prove it was a
        // control at all. Depth spent by role is the whole point of the row.
        final chip = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text('Convert'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final context = tester.element(find.text('Convert'));
        expect(
          (chip.decoration as BoxDecoration).color,
          ExampleSurface.of(context, 2),
        );
        expect(
          ExampleSurface.of(context, 2),
          isNot(ExampleSurface.of(context, 1)),
        );
      });
    }

    for (final width in _widths) {
      testWidgets('Add money opens receiving details at $width',
          (tester) async {
        await _pumpAt(tester, width: width, brightness: Brightness.light);
        await tester.tap(find.widgetWithText(ExampleGlassButton, 'Add money'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(
            find.text(
                'Send a bank transfer using the receiving details below.'),
            findsOneWidget);
        expect(find.text('Receiving account details'), findsOneWidget);
        expect(find.text('Receiving details unavailable'), findsOneWidget);
        await tester
            .tap(width < 600 ? find.byTooltip('Close') : find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Add money shows the selected account bank details',
        (tester) async {
      await _pumpAt(tester,
          width: 375,
          brightness: Brightness.light,
          budgets: const [
            PlatformResource(
              id: 'bank-main',
              title: 'Account balance',
              subtitle: 'EUR',
              metadata: {
                'budgetId': 'bank-main',
                'provider': 'EqualsMoney',
                'iban': 'BE68539007547034',
                'swift': 'BBRUBEBB',
                'accountHolderName': 'Test Customer',
                'balances': [
                  {'currency': 'EUR', 'amount': 0}
                ],
              },
            )
          ]);
      await tester.tap(find.widgetWithText(ExampleGlassButton, 'Add money'));
      await tester.pumpAndSettle();
      expect(find.text('Receiving account details'), findsOneWidget);
      expect(find.text('BE68539007547034'), findsOneWidget);
      expect(find.text('BBRUBEBB'), findsOneWidget);
      expect(find.text('Receiving details unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reaches its final state on frame one under reduced motion',
        (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(width: 375, brightness: Brightness.dark, reducedMotion: true),
      );
      // One frame for the providers, and no `pumpAndSettle`: the point is that
      // the arrival moment is already over, not that it finishes quickly.
      await tester.pump();
      await tester.pump();

      final hero = tester
          .widgetList<ExampleAmount>(find.byType(ExampleAmount))
          .firstWhere((amount) => amount.size != ExampleAmountSize.small);
      final context = tester.element(find.text('MONEY BALANCE'));
      expect(hero.color, ExampleInk.primary(context));
      expect(tester.takeException(), isNull);
    });

    testWidgets('holds at a 1.3 text scale on a 375 phone', (tester) async {
      await _pumpAt(
        tester,
        width: 375,
        brightness: Brightness.light,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('MONEY BALANCE'), findsOneWidget);
      expect(
          find.widgetWithText(ExampleGlassButton, 'Add money'), findsOneWidget);
    });

    testWidgets('the desktop action column grows with the type it holds',
        (tester) async {
      // The two-row layout exists because at 375 the three labels cannot
      // share a line without clipping "New budget". The wide layout then
      // handed the action column a flat 220 px, which splits into two chips
      // and leaves each label 80 — enough for "New budget" at a 1.0 text
      // scale and not at 1.3, so the clipping the restructure removed came
      // back on desktop at every accessibility scale.
      //
      // Measured on the room the label is given rather than on whether it
      // clipped: `flutter_test` substitutes a fixed-width fallback font that
      // sets "New budget" about 45 percent wider than the shipped one, so
      // `didExceedMaxLines` here would report the test font, not the design.
      await _pumpAt(tester, width: 1440, brightness: Brightness.dark);
      final atOne = tester.getSize(find.text('New budget')).width;

      await _pumpAt(
        tester,
        width: 1440,
        brightness: Brightness.dark,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      final atThirteen = tester.getSize(find.text('New budget')).width;

      // The chips' fixed furniture — an 18 px icon and its gutter — does not
      // scale, so a column that tracks the text scale hands the label back
      // slightly more than the type grew by, never less. Held at 220 the two
      // are equal and the longer label is the one that pays.
      expect(atThirteen, greaterThanOrEqualTo(atOne * 1.3));
    });

    testWidgets(
        'a panel that cannot afford the action column stacks instead of '
        'clamping it', (tester) async {
      // 800 less the screen's two 20 px gutters is a 760 px panel — the
      // narrowest that takes the two-column layout off the web, and the same
      // arithmetic the web runs from 500 px up. The column asks for
      // 220 * scale and may hold at most .45 of the panel, so at 1.0 it takes
      // 220 of the 342 it is allowed and at 1.6 it wants 352, which is more
      // than the panel has to give.
      //
      // The shape this replaces clamped the column to those 342 and kept the
      // two columns, which hands each chip (342 - 8) / 2 = 167 px — narrower than
      // the 106 px chip of the 1.0 layout scaled by the same 1.6. That is the
      // squeeze that ellipsises "New budget": on web the band opens at a
      // 500 px panel, where the clamp leaves 82 px of label room against the
      // 94 the label wants. Here it stacks instead and `_actions()` gets the
      // whole 724 px of panel interior, so each chip is 358.
      //
      // Measured on the chip rather than on the label: `flutter_test`
      // substitutes a fixed-width fallback font that sets "New budget" about
      // 45 percent wider than the shipped one, so `didExceedMaxLines` here
      // would report the test font's clip and not the design's.
      await _pumpAt(tester, width: 800, brightness: Brightness.dark);
      final atOne = _chipWidth(tester, 'New budget');

      await _pumpAt(
        tester,
        width: 800,
        brightness: Brightness.dark,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);

      // Whatever layout it lands in, a chip is never given less room than the
      // 1.0 chip grown by the same scale as the type inside it.
      expect(
          _chipWidth(tester, 'New budget'), greaterThanOrEqualTo(atOne * 1.6));

      // And the actions are stacked under the summary, not beside it: each
      // chip takes half the panel interior rather than half a 342 px column.
      // (The CTA no longer proves this — it hugs its label on the masthead.)
      expect(_chipWidth(tester, 'New budget'), greaterThan((342 - 8) / 2));
    });

    testWidgets('a disabled scope above it stays the kill switch',
        (tester) async {
      await _pumpAt(
        tester,
        width: 375,
        brightness: Brightness.dark,
        disabledSheenScope: true,
      );

      // The screen adds an alive layer on the routes that mount it without
      // the shell, and the question it has to ask is `existsAbove`.
      // `maybeOf` reports null for a scope that is switched *off*, so a
      // screen asking it would answer "nobody has one" while standing
      // directly under a deliberately disabled scope, nest an enabled one,
      // and set the hero's hairline and the section headline looping at the
      // 7 s cadence anyway.
      expect(find.byType(ExampleSheenScope), findsOneWidget);
      expect(
        ExampleSheenScope.maybeOf(tester.element(find.text('MONEY BALANCE'))),
        isNull,
      );
    });

    // Both brightnesses, because the colour assertion below is the only one
    // in this file whose expected value moves with the theme. Checked by
    // mutation, not assumed: writing the counter's colour as the Twilight
    // literal `ExampleColors.textTertiary` leaves this run green in dark and
    // fails it in light with `Expected alpha 0.6039 red 0.0510 ... Actual
    // alpha 0.5294 red 0.9490 ...`. The neighbouring geometry and enum tests
    // stay on one brightness because nothing they read resolves per theme.
    for (final brightness in Brightness.values) {
      testWidgets(
          'the currencies past the third are counted, in the eyebrow '
          'voice, in $brightness', (tester) async {
        await _pumpAt(
          tester,
          width: 375,
          brightness: brightness,
          budgets: _fiveCurrencyBudgets,
        );
        expect(tester.takeException(), isNull);

        // Five currencies: one promoted, three drawn, one counted. The
        // counter was a raw 12.5 px TextStyle — the exact off-ladder volume
        // this panel was rebuilt to remove, and with no fontFamily, so a
        // tenant's APP_FONT_FAMILY skipped it in silence. It is the
        // masthead's 11 px eyebrow now, in tertiary ink.
        final context = tester.element(find.text('+1 MORE'));
        final eyebrow = ExampleTextStyles.label(context);
        final counter = tester.widget<Text>(find.text('+1 MORE'));
        expect(counter.style?.fontSize, eyebrow.fontSize);
        expect(counter.style?.fontFamily, eyebrow.fontFamily);
        expect(counter.style?.fontWeight, eyebrow.fontWeight);
        // Token identity, not a ratio: expected and actual both resolve from
        // this context, so the line catches a hard-coded literal and cannot
        // catch a bad number. The numbers behind the token were measured
        // instead, by rastering this panel's own backdrop at 375 and text
        // scale 1 and compositing the ink over the extreme ground pixel
        // inside the counter's own box — pearl .53 over rgb(28,32,54), the
        // brightest pixel under it in Twilight, is 4.83:1; night .604 over
        // rgb(245,243,253), the darkest under it on paper, is 5.02:1. Both
        // clear the 4.5:1 body floor. Bare ExampleSurface level 1 would read
        // 5.10:1 and 5.09:1; the panel's violet dawn is what costs the rest,
        // and it is brightest at the top-left corner, so both figures move if
        // this row moves.
        expect(counter.style?.color, ExampleInk.tertiary(context));
        // The caps are typography, so the count is spelled out and counted.
        expect(counter.semanticsLabel, '1 more currency');
      });
    }

    testWidgets('every pocket ends in its ISO code, painted disc or not',
        (tester) async {
      await _pumpAt(
        tester,
        width: 375,
        brightness: Brightness.dark,
        budgets: _fiveCurrencyBudgets,
      );

      // JPY is the artwork-free case, so its disc is a 6 px glyph and the
      // code beside the figure is what names it at a body size. `auto` would
      // print that code too — `Money.formatAmount` has a symbol only for USD,
      // EUR and GBP — so what this pins is not "JPY is named" but the strip's
      // one shape: every pocket, symbol currency or not, ends in its ISO
      // code, the same as the hero one register up. Read off the rendered
      // runs rather than the `code` enum, so it also fails if `_AmountParts`
      // stops honouring [ExampleAmountCode.always].
      final pockets = tester
          .widgetList<ExampleAmount>(find.byType(ExampleAmount))
          .where((amount) => amount.size == ExampleAmountSize.small)
          .toList();
      expect(pockets.map((amount) => amount.currency), contains('JPY'));
      expect(pockets, hasLength(3));
      for (final pocket in pockets) {
        expect(
          _renderedAmount(tester, pocket),
          endsWith(' ${pocket.currency}'),
        );
      }
    });

    for (final width in _widths) {
      testWidgets('a white-label tenant gets none of it at $width',
          (tester) async {
        await _pumpAt(
          tester,
          width: width,
          brightness: Brightness.dark,
          branding: _tenantBranding,
        );

        // The whole panel is behind `isExample && initialTab == accounts`. The
        // cross-screen glass suite mounts the payees tab, which never builds
        // this branch in either brand, so this is the only place a tenant on
        // the accounts tab is rendered at all: the Material header and tab
        // bar, and not one Example object.
        expect(find.text('MONEY BALANCE'), findsNothing);
        expect(find.byType(ExampleGlassButton), findsNothing);
        expect(find.byType(ExampleCurrencyAvatar), findsNothing);
        expect(find.byType(ExampleAmount), findsNothing);
        expect(find.text('Fiat account'), findsOneWidget);

        // The legacy `_EqualsMoneyHeader` this branch still renders overflows
        // its own Row by 27 px at 375. It predates the hero, it is in the
        // tenant branch, and moving it would move a tenant's pixels — so it
        // is drained here exactly as the glass suite drains it, rather than
        // asserted away or quietly fixed.
        final legacy = tester.takeException();
        if (width == 375) {
          expect('$legacy', contains('overflowed'));
        } else {
          expect(legacy, isNull);
        }
      });
    }
  });
}

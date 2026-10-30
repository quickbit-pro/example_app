import 'package:mobile_flutter/core/widgets/keyboard_focus_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';

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

const _tenantConfig = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: true,
  referralRegistrationMode: 'code',
  vouchersEnabled: false,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: true,
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
        {'currency': 'EUR', 'amount': 6234.75},
      ],
    },
  ),
];

const _payee = Payee(
  id: 'p-1',
  name: 'Ana Novak',
  accountReference: 'SI56 0201 0001 2345 678',
  firstName: 'Ana',
  lastName: 'Novak',
  paymentType: 'INDIVIDUAL',
  paymentMethod: 'SEPA.CREDITTRANSFER',
  currency: 'EUR',
  status: 'active',
);

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

Widget _host({
  required MoneyTab tab,
  required AppBranding branding,
  required Brightness brightness,
}) {
  final themes = buildAppThemes(branding);
  final router = GoRouter(
    initialLocation: '/money',
    routes: [
      GoRoute(
          path: '/money',
          builder: (_, __) => Scaffold(
                bottomNavigationBar: const SizedBox(height: 80),
                body: MoneyScreen(initialTab: tab),
              )),
      GoRoute(path: '/profile', builder: (_, __) => const Text('Profile')),
    ],
  );
  return ProviderScope(
    overrides: [
      exchangeOverviewProvider
          .overrideWith((ref) async => BoomFiExchangeOverview.fromJson({
                'account': {'id': 1, 'enabled': true, 'state': 'active'},
              })),
      exchangeCardDepositAddressesProvider
          .overrideWith((ref) async => const []),
      portfolioEstimateProvider
          .overrideWith((ref) async => PortfolioEstimate.fromJson({
                'currency': 'USD',
                'valuationRates': [
                  {'currency': 'EUR', 'rate': 1.16},
                  {'currency': 'USD', 'rate': 1},
                ],
              })),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenantConfig),
      kycDetailedStatusProvider.overrideWith((ref) async => _clearKyc),
      dashboardProvider.overrideWith((ref) async => _dashboard),
      accountsProvider.overrideWith((ref) async => const [_equalsAccount]),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => _budgets),
      payeesProvider.overrideWith((ref) async => const [_payee]),
      hoppaWalletAssetsProvider.overrideWith((ref) async => const []),
      hoppaWalletAddressesProvider.overrideWith((ref) async => const []),
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? themes.dark : themes.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => KeyboardFocusVisibility(child: child!),
    ),
  );
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final viewport in [const Size(393, 852), const Size(375, 667)]) {
      for (final resizeViewport in [false, true]) {
        for (final tab in [MoneyTab.payees, MoneyTab.pay]) {
          testWidgets(
              '$platform $tab $viewport resize=$resizeViewport keeps input visible',
              (tester) async {
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(_host(
              tab: tab,
              branding: _exampleBranding,
              brightness: Brightness.dark,
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final field = find.widgetWithText(TextFormField,
                tab == MoneyTab.payees ? 'Bank name' : 'Reference');
            final scroll = find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first;
            if (tab == MoneyTab.payees) {
              await tester.scrollUntilVisible(find.text('Add payee'), 150,
                  scrollable: scroll);
              await tester.tap(find.text('Add payee'));
              await tester.pumpAndSettle();
            }
            await tester.scrollUntilVisible(field, 150, scrollable: scroll);
            await tester.enterText(field, 'Keyboard regression');
            await tester.pumpAndSettle();
            final editable = tester.widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            );
            if (resizeViewport) {
              // Mobile browsers can shrink the view instead of reporting insets.
              tester.view.physicalSize =
                  Size(viewport.width, viewport.height - 360);
            } else {
              tester.view.viewInsets = const FakeViewPadding(bottom: 360);
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(milliseconds: 300));
            await tester.pumpAndSettle();
            final rect = tester.getRect(field);
            expect(rect.top, greaterThanOrEqualTo(56));
            expect(rect.bottom, lessThanOrEqualTo(viewport.height - 360));
            final formRect = tester.getRect(find.byType(ListView).last);
            expect(rect.top, greaterThanOrEqualTo(formRect.top));
            expect(rect.bottom, lessThanOrEqualTo(formRect.bottom));
            expect(editable.focusNode.hasFocus, isTrue);
            expect(editable.controller.text, 'Keyboard regression');
            // The user must still be able to scroll farther through the form.
            await tester.drag(field, const Offset(0, -100));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            tester.view.viewInsets = const FakeViewPadding();
            tester.view.physicalSize = viewport;
            await tester.pumpAndSettle();
            expect(editable.controller.text, 'Keyboard regression');
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }, variant: TargetPlatformVariant.only(platform));
        }
      }
    }
  }
}

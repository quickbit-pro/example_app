import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/presentation/example_otp_field.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_panel.dart';
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
  ],
  settlementAccounts: [],
  subAccounts: [],
  fiatFundingCurrencies: ['USD'],
);

/// Quotes, issues a verification token and remembers every code the dialog
/// tries to confirm with.
class _FakeExchangeApi extends MobilePlatformApi {
  _FakeExchangeApi() : super(Dio());

  final confirmedCodes = <String>[];

  @override
  Future<Map<String, dynamic>> getInterlaceToEqualsQuote(
          Map<String, Object?> request) async =>
      {
        'rate': '0.998400',
        'buy_amount': '24.96',
        'buy_currency': 'USD',
        'fees': {'total_fee': '0.04', 'fee_ccy': 'USD'},
        'expiry': '2026-09-04T12:30:00Z',
        'session': 'q-1',
      };

  @override
  Future<Map<String, dynamic>> initiateInterlaceToEquals(
          Map<String, Object?> request) async =>
      {'verificationToken': 'tok-exchange'};

  @override
  Future<ActionResult> confirmInterlaceToEquals({
    required String verificationToken,
    required String otpCode,
  }) async {
    confirmedCodes.add(otpCode);
    return const ActionResult(message: 'Transfer confirmed');
  }
}

List<Override> _overrides(_FakeExchangeApi api) => [
      mobilePlatformApiProvider.overrideWithValue(api),
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
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => const [_budget]),
      exchangeTransfersProvider.overrideWith((ref) async => const []),
      exchangeOverviewProvider.overrideWith(
        (ref) => Future<BoomFiExchangeOverview>.value(_exchangeOverview),
      ),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      activityTransactionsProvider.overrideWith((ref) async => const []),
    ];

Widget _exchangePanelHost({
  required _FakeExchangeApi api,
  required AppBranding branding,
  required Brightness brightness,
}) {
  final themes = buildAppThemes(branding);
  return ProviderScope(
    overrides: _overrides(api),
    child: MaterialApp(
      theme: brightness == Brightness.dark ? themes.dark : themes.light,
      themeMode: ThemeMode.light,
      builder: (context, navigator) => MediaQuery(
        data: const MediaQueryData(size: Size(375, 900)),
        child: ExampleSheenScope(child: navigator ?? const SizedBox.shrink()),
      ),
      home: Scaffold(
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
    ),
  );
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _otpInput() => find.descendant(
      of: find.byType(ExampleOtpField),
      matching: find.byType(EditableText),
    );

/// The dialog's commit, whichever material the brand renders it in.
VoidCallback? _confirmAction(WidgetTester tester, bool example) => example
    ? tester
        .widget<ExampleGlassButton>(
            find.widgetWithText(ExampleGlassButton, 'Confirm transfer'))
        .onPressed
    : tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm transfer'))
        .onPressed;

void main() {
  const variants = <(String, AppBranding, Brightness, String)>[
    ('Example twilight', _exampleBranding, Brightness.dark, 'Crypto to fiat'),
    ('Example daylight', _exampleBranding, Brightness.light, 'Crypto to fiat'),
    ('white-label', _tenantBranding, Brightness.dark, 'Crypto → Fiat'),
  ];

  for (final (name, branding, brightness, opener) in variants) {
    final example = branding == _exampleBranding;
    testWidgets(
        'the crypto-to-fiat code is eight cells and the commit waits for all '
        'of them ($name)', (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeExchangeApi();
      await tester.pumpWidget(
        _exchangePanelHost(
            api: api, branding: branding, brightness: brightness),
      );
      await tester.pumpAndSettle();

      await _tap(tester, opener);
      // The white-label dialog header already overflows by 16 px at 375
      // before any code is asked for; that predates these cells and is
      // drained here so the assertions below are about the cells alone.
      if (!example) tester.takeException();
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (USDC)'),
        '25',
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Get quote');
      await _tap(tester, 'Send verification code');

      expect(find.byType(ExampleOtpField), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Email verification code'),
        findsNothing,
      );
      final editable = tester.state<EditableTextState>(_otpInput());
      expect(
          editable.widget.autofillHints, contains(AutofillHints.oneTimeCode));

      // Seven digits leave the commit inert; the eighth arms it.
      await tester.enterText(_otpInput(), '1234567');
      await tester.pumpAndSettle();
      expect(_confirmAction(tester, example), isNull);

      await tester.enterText(_otpInput(), '12345678');
      await tester.pumpAndSettle();
      expect(_confirmAction(tester, example), isNotNull);

      await _tap(tester, 'Confirm transfer');
      expect(api.confirmedCodes, ['12345678']);
      expect(find.byType(ExampleOtpField), findsNothing);
      expect(find.text('Transfer confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

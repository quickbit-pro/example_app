import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/presentation/example_otp_field.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';
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

/// Quotes, checks and issues codes without complaint, and remembers every
/// code the screen tries to verify and every commit that followed.
class _FakeBankingApi extends MobileBankingApi {
  _FakeBankingApi() : super(Dio());

  final verifiedCodes = <String>[];
  var payoutsConfirmed = 0;
  var payeesConfirmed = 0;

  @override
  Future<PayoutQuote> createPayoutQuote({
    required String payeeId,
    required double amount,
    required String sourceCurrency,
    required String targetCurrency,
    String? lastQuoteId,
  }) async =>
      PayoutQuote(
        id: 'q-1',
        quoteRequestId: 'qr-1',
        sourceAmount: amount,
        sourceCurrency: sourceCurrency,
        targetAmount: amount,
        targetCurrency: targetCurrency,
        exchangeRate: 1,
        fee: 0.5,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

  @override
  Future<PayoutCheck> checkPayout({
    required String payeeId,
    required String quotationId,
    required double amount,
    required String currency,
    String? balanceId,
    String? memo,
    String? reason,
  }) async =>
      const PayoutCheck(id: 'chk-1', pass: true);

  @override
  Future<PayoutOtpInitiation> initiatePayoutOtp({
    required String checkId,
    required String payeeId,
    required double amount,
    required String currency,
    String? balanceId,
    String? quoteRequestId,
  }) async =>
      const PayoutOtpInitiation(
        success: true,
        verificationToken: 'tok-payout',
        message: 'Code sent.',
      );

  @override
  Future<OtpVerification> verifyPayoutOtp({
    required String verificationToken,
    required String otpCode,
  }) async {
    verifiedCodes.add(otpCode);
    return const OtpVerification(
      success: true,
      verificationToken: 'tok-verified',
    );
  }

  @override
  Future<void> confirmPayout({
    required String checkId,
    required String payeeId,
    required double amount,
    required String currency,
    String? balanceId,
    required String verificationToken,
    String? quoteRequestId,
  }) async {
    payoutsConfirmed++;
  }

  @override
  Future<PayoutOtpInitiation> initiatePayeeCreation({
    required String paymentType,
    required String currency,
    required String paymentMethod,
    required String countryCode,
    required String firstName,
    required String lastName,
    required String accountNumber,
    String? userName,
    String? displayName,
    String? bankName,
    String? routingCodeType,
    String? routingCodeValue,
    String? bankCountry,
    String? bankAddressLine1,
    String? bankAddressLine2,
    String? bankCity,
    String? bankState,
    String? bankPostalCode,
    String? payeeCountry,
    String? payeeAddressLine1,
    String? payeeAddressLine2,
    String? payeeCity,
    String? payeeState,
    String? payeePostalCode,
    String? comments,
    String? verificationMethod,
  }) async =>
      const PayoutOtpInitiation(
        success: true,
        verificationToken: 'tok-payee',
        message: 'Code sent to your email.',
      );

  @override
  Future<void> confirmPayeeCreation({
    required String verificationToken,
  }) async {
    payeesConfirmed++;
  }
}

/// Phone width, but tall enough that the pay and payee forms fit without
/// scrolling: both live in lazy lists, and a commit pushed below the fold by
/// a quote card or a long form is not built at all, so it cannot be reached
/// by `ensureVisible`. The cells' own fit at phone width is proven in
/// example_otp_field_test.dart.
const _tall = 2600.0;

Widget _host({
  required _FakeBankingApi api,
  required MoneyTab tab,
  required AppBranding branding,
  required Brightness brightness,
}) {
  final themes = buildAppThemes(branding);
  final router = GoRouter(
    initialLocation: '/money',
    routes: [
      GoRoute(path: '/money', builder: (_, __) => MoneyScreen(initialTab: tab)),
      GoRoute(path: '/profile', builder: (_, __) => const Text('Profile')),
    ],
  );
  return ProviderScope(
    overrides: [
      mobileBankingApiProvider.overrideWithValue(api),
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
      builder: (context, child) => MediaQuery(
        data: const MediaQueryData(size: Size(375, _tall)),
        child: child!,
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeBankingApi api,
  required MoneyTab tab,
  required AppBranding branding,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(375, _tall);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(api: api, tab: tab, branding: branding, brightness: brightness),
  );
  await tester.pumpAndSettle();
  // The white-label money screen already overflows by 27 px at 375 on open,
  // before any code is asked for (money_accounts_hero_test.dart drains the
  // same legacy exception). It predates these cells and is drained here so
  // the assertions in each flow are about the cells alone.
  if (branding == _tenantBranding) tester.takeException();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Finder _otpInput() => find.descendant(
      of: find.byType(ExampleOtpField),
      matching: find.byType(EditableText),
    );

/// Types [code] into the cells and presses [commit]; the screen's own guard
/// decides whether that reaches the API.
Future<void> _commitWith(
    WidgetTester tester, String code, String commit) async {
  await tester.enterText(_otpInput(), code);
  await tester.pump();
  await _tap(tester, commit);
}

void main() {
  const variants = <(String, AppBranding, Brightness)>[
    ('Example twilight', _exampleBranding, Brightness.dark),
    ('Example daylight', _exampleBranding, Brightness.light),
    ('white-label', _tenantBranding, Brightness.dark),
  ];

  group('Payout confirmation', () {
    for (final (name, branding, brightness) in variants) {
      testWidgets('takes eight cells and confirms on the eighth ($name)',
          (tester) async {
        final api = _FakeBankingApi();
        await _pump(tester,
            api: api,
            tab: MoneyTab.pay,
            branding: branding,
            brightness: brightness);

        await _enter(tester, 'Amount', '10');
        await _enter(tester, 'Reference', 'Rent');
        await _tap(tester, 'Show fee');
        await _tap(tester, 'Send OTP code');

        expect(find.byType(ExampleOtpField), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'OTP code'), findsNothing);
        expect(
            find.text('Enter the 8-digit code sent to you.'), findsOneWidget);
        expect(find.text('Resend code'), findsOneWidget);
        final editable = tester.state<EditableTextState>(_otpInput());
        expect(
            editable.widget.autofillHints, contains(AutofillHints.oneTimeCode));

        await _commitWith(tester, '1234567', 'Confirm payment');
        expect(find.text('Enter the full 8-digit OTP code.'), findsOneWidget);
        expect(api.verifiedCodes, isEmpty);

        await _commitWith(tester, '12345678', 'Confirm payment');
        expect(api.verifiedCodes, ['12345678']);
        expect(api.payoutsConfirmed, 1);
        expect(find.text('Payment submitted'), findsOneWidget);
        expect(find.byType(ExampleOtpField), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Payee confirmation', () {
    for (final (name, branding, brightness) in variants) {
      testWidgets('takes eight cells and saves on the eighth ($name)',
          (tester) async {
        final api = _FakeBankingApi();
        await _pump(tester,
            api: api,
            tab: MoneyTab.payees,
            branding: branding,
            brightness: brightness);

        await _tap(tester, 'Add payee');
        await _enter(tester, 'First name', 'Ana');
        await _enter(tester, 'Last name', 'Novak');
        await _enter(tester, 'Account holder name', 'Ana Novak');
        await _enter(tester, 'IBAN or account number', 'SI56020100012345678');
        await _tap(tester, 'Send OTP code');

        expect(find.byType(ExampleOtpField), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'OTP code'), findsNothing);
        expect(find.text('Code sent to your email.'), findsOneWidget);
        final editable = tester.state<EditableTextState>(_otpInput());
        expect(
            editable.widget.autofillHints, contains(AutofillHints.oneTimeCode));

        await _commitWith(tester, '1234567', 'Confirm payee');
        expect(find.text('Enter the full 8-digit OTP code.'), findsOneWidget);
        expect(api.verifiedCodes, isEmpty);

        await _commitWith(tester, '12345678', 'Confirm payee');
        expect(api.verifiedCodes, ['12345678']);
        expect(api.payeesConfirmed, 1);
        expect(find.text('Payee saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/presentation/example_otp_field.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/domain/withdrawal_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/crypto_withdrawal_dialog.dart';
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

/// A real, all-lowercase EVM address: 42 characters, so it passes the
/// validator's format check without tripping its EIP-55 mixed-case rule.
const _evmAddress = '0x71c7656ec7ab88b098defb751b7401b5f6d8976f';

const _usdt = HoppaWalletAsset(
  symbol: 'USDT',
  name: 'Tether',
  network: 'ETH / OP / ARB',
  amount: 320.394999,
  fiatValue: 320.39,
  address: _evmAddress,
  tint: Color(0xFF26A17B),
  walletId: 'w-usdt',
);

/// Answers the withdrawal's questions in order and remembers every code the
/// sheet tries to confirm with.
class _FakeApi extends MobilePlatformApi {
  _FakeApi() : super(Dio());

  final confirmedCodes = <String>[];

  @override
  Future<CryptoWithdrawalBalance> getCryptoWithdrawalAvailableBalance() async =>
      const CryptoWithdrawalBalance(
        totalAvailableUsdt: 320.394999,
        totalAvailableUsdc: 320.394999,
      );

  @override
  Future<CryptoWithdrawalQuote> getCryptoWithdrawalFeeAndQuota({
    required String chain,
    required String address,
    required String currency,
    required String amount,
  }) async =>
      const CryptoWithdrawalQuote(
        code: '000000',
        crossChainQuota: '',
        crossChainFeeRate: '',
        crossChainAmount: '',
        fees: [CryptoWithdrawalFee(amount: 0.5, currency: 'USDT', type: 'GAS')],
        message: '',
      );

  @override
  Future<CryptoWithdrawalResult> createCryptoWithdrawal({
    required String currency,
    required String chain,
    required String amount,
    required String destinationAddress,
  }) async =>
      const CryptoWithdrawalResult(
        success: true,
        otpRequired: true,
        verificationToken: 'token-1',
        status: 'PENDING',
        message: '',
        transactionId: 'tx-1',
        otpExpiresAt: null,
        fees: [],
      );

  @override
  Future<CryptoWithdrawalResult> confirmCryptoWithdrawal({
    required String verificationToken,
    required String otpCode,
  }) async {
    confirmedCodes.add(otpCode);
    return const CryptoWithdrawalResult(
      success: true,
      otpRequired: false,
      verificationToken: '',
      status: 'COMPLETED',
      message: '',
      transactionId: 'tx-1',
      otpExpiresAt: null,
      fees: [],
    );
  }
}

Widget _opener({
  required _FakeApi api,
  required AppBranding branding,
  required Brightness brightness,
  HoppaWalletAsset asset = _usdt,
  List<HoppaWalletAsset>? assets,
}) {
  final themes = buildAppThemes(branding);
  return ProviderScope(
    overrides: [
      mobilePlatformApiProvider.overrideWithValue(api),
      hoppaWalletAssetsProvider.overrideWith((ref) async => assets ?? [asset]),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? themes.dark : themes.light,
      themeMode: ThemeMode.light,
      builder: (context, navigator) => MediaQuery(
        data: const MediaQueryData(size: Size(375, 900)),
        child: ExampleSheenScope(child: navigator ?? const SizedBox.shrink()),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showCryptoWithdrawalDialog(context, asset: asset),
              child: const Text('open'),
            ),
          ),
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

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Finder _otpInput() => find.descendant(
      of: find.byType(ExampleOtpField),
      matching: find.byType(EditableText),
    );

void main() {
  testWidgets('invalid Tron input never looks valid or enables review',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_opener(
        api: _FakeApi(),
        branding: _exampleBranding,
        brightness: Brightness.dark));
    await _tap(tester, 'open');
    await _tap(tester, 'Ethereum');
    await _tap(tester, 'Tron');
    await _enter(tester, 'Amount (USDT)', '10');
    await _enter(tester, 'Destination wallet address',
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
    final field = find.widgetWithText(TextField, 'Destination wallet address');
    expect(tester.widget<TextField>(field).decoration!.suffixIcon, isNotNull);
    await _enter(tester, 'Destination wallet address', 'T123');
    expect(tester.widget<TextField>(field).decoration!.suffixIcon, isNull);
    expect(tester.widget<TextField>(field).decoration!.errorText,
        contains('34 characters'));
    expect(
        tester
            .widget<ExampleGlassButton>(
                find.widgetWithText(ExampleGlassButton, 'Review withdrawal'))
            .onPressed,
        isNull);
  });

  testWidgets('USDC resets Tron and exposes only supported network choices',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const usdc = HoppaWalletAsset(
        symbol: 'USDC',
        name: 'USD Coin',
        network: 'ETH',
        amount: 20,
        fiatValue: 20,
        address: _evmAddress,
        tint: Colors.blue,
        walletId: 'usdc');
    await tester.pumpWidget(_opener(
        api: _FakeApi(),
        branding: _exampleBranding,
        brightness: Brightness.dark,
        assets: [_usdt, usdc]));
    await _tap(tester, 'open');
    await _tap(tester, 'Ethereum');
    await _tap(tester, 'Tron');
    await _enter(tester, 'Destination wallet address',
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
    await _tap(tester, 'USDC Wallet');
    expect(find.text('Ethereum'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Destination wallet address'))
            .decoration!
            .suffixIcon,
        isNull);
    await _tap(tester, 'Ethereum');
    expect(find.text('Tron'), findsNothing);
    expect(find.text('OKX Chain'), findsNothing);
  });

  testWidgets(
      'subminimum balance explains and disables both withdrawal actions',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const dust = HoppaWalletAsset(
        symbol: 'USDT',
        name: 'Tether',
        network: 'ETH',
        amount: 0.006913,
        fiatValue: 0.006913,
        address: _evmAddress,
        tint: Colors.green,
        walletId: 'dust');
    await tester.pumpWidget(_opener(
        api: _FakeApi(),
        branding: _exampleBranding,
        brightness: Brightness.dark,
        asset: dust));
    await _tap(tester, 'open');
    expect(find.textContaining('below the minimum withdrawal'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Max'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<ExampleGlassButton>(
                find.widgetWithText(ExampleGlassButton, 'Review withdrawal'))
            .onPressed,
        isNull);
  });

  const variants = <(String, AppBranding, Brightness)>[
    ('Example twilight', _exampleBranding, Brightness.dark),
    ('Example daylight', _exampleBranding, Brightness.light),
    ('white-label', _tenantBranding, Brightness.dark),
  ];

  for (final (name, branding, brightness) in variants) {
    testWidgets(
        'the verification step takes eight cells and confirms on the eighth '
        '($name)', (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      await tester.pumpWidget(
        _opener(api: api, branding: branding, brightness: brightness),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'open');

      await _enter(tester, 'Destination wallet address', _evmAddress);
      await _enter(tester, 'Amount (USDT)', '10');
      await _tap(tester, 'Review withdrawal');
      final confirmation = find.byType(CheckboxListTile);
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await tester.pumpAndSettle();
      await _tap(tester, 'Send verification code');

      // The bare text field is gone; the code is entered cell by cell into
      // one input that still carries the one-time-code hint.
      expect(find.byType(ExampleOtpField), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Verification code'), findsNothing);
      final editable = tester.state<EditableTextState>(_otpInput());
      expect(
          editable.widget.autofillHints, contains(AutofillHints.oneTimeCode));

      await tester.enterText(_otpInput(), '1234567');
      await tester.pump();
      await _tap(tester, 'Confirm withdrawal');
      expect(find.text('Enter the full 8-digit verification code.'),
          findsOneWidget);
      expect(api.confirmedCodes, isEmpty);

      await tester.enterText(_otpInput(), '12345678');
      await tester.pump();
      await _tap(tester, 'Confirm withdrawal');
      expect(api.confirmedCodes, ['12345678']);
      expect(find.byType(ExampleOtpField), findsNothing);
      expect(find.text('Withdrawal submitted successfully.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

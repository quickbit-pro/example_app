import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/domain/referral_quote.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _tenant = MobileTenantConfig(
  companyName: 'Test',
  brandName: 'Test',
  referralsEnabled: true,
  referralRegistrationMode: 'optional',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, String brand, bool light,
    {String? referralCode}) async {
  final size = brand == 'example' ? const Size(390, 844) : const Size(800, 1800);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final branding = AppBranding(
    appName: brand,
    brandId: brand,
    primarySeedHex: '7B6CF6',
    accentSeedHex: 'A78BFA',
    loginBackgroundHex: '',
    themeMode: light ? 'light' : 'dark',
    fontFamily: '',
    logoAsset: '',
    radiusScale: '1',
    supportEmail: 'support@example.test',
    supportPhone: '',
    legalEntity: brand,
  );
  final themes = buildAppThemes(branding);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://127.0.0.1:1',
        branding: branding,
      )),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
      mobilePlatformApiProvider.overrideWithValue(_ReferralApi()),
    ],
    child: MaterialApp(
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      home: SignupScreen(initialStep: 2, initialReferralCode: referralCode),
    ),
  ));
  await _settle(tester);
}

Finder get _password => find.byWidgetPredicate((widget) =>
    widget is EditableText &&
    widget.autofillHints?.contains(AutofillHints.newPassword) == true);

void main() {
  for (final light in [false, true]) {
    testWidgets('Example light=$light can continue with a referral code',
        (tester) async {
      await _pump(tester, 'example', light, referralCode: 'FRIEND1');
      await tester.enterText(_password, 'ValidExample1234');
      await _settle(tester);
      expect(find.text('Long referral programme conditions'), findsNothing);
      expect(find.textContaining('Referral terms · version'), findsNothing);
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(find.byKey(const Key('signup_referral_accept')), findsNothing);
      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final brand in ['example', 'hoppa']) {
    for (final light in [false, true]) {
      testWidgets('$brand light=$light password errors follow corrections',
          (tester) async {
        await _pump(tester, brand, light);
        await tester.enterText(_password, 'lowercase1234');
        await _settle(tester);
        expect(find.textContaining('Still needed:'), findsNothing);

        if (brand == 'example') {
          await tester.tap(find.text('Continue'));
        } else {
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Continue').last)
              .onPressed!();
        }
        await _settle(tester);
        expect(find.textContaining('Still needed:'), findsOneWidget);
        expect(find.text('Still needed: An uppercase letter (A–Z)'),
            findsOneWidget);

        await tester.enterText(_password, 'ValidExample1234');
        await _settle(tester);
        expect(find.textContaining('Still needed:'), findsNothing);
        expect(find.text('Strong password'), findsOneWidget);
        if (brand == 'example') {
          expect(
            find.text(
                'Your password is too weak. Check the requirements below the field.'),
            findsNothing,
          );
        }

        // Once submitted, removing a requirement updates the error again.
        await tester.enterText(_password, 'ValidExample');
        await _settle(tester);
        expect(find.textContaining('Still needed:'), findsOneWidget);
        expect(find.text('Strong password'), findsNothing);

        // A password manager/controller write must update both displays too.
        tester.widget<EditableText>(_password).controller.text =
            'FilledExample1234';
        await _settle(tester);
        expect(find.textContaining('Still needed:'), findsNothing);
        expect(find.text('Strong password'), findsOneWidget);

        if (brand == 'example') {
          await tester.tap(find.text('Continue'));
        } else {
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Continue').last)
              .onPressed!();
        }
        await _settle(tester);
        expect(find.text('Create account'), findsWidgets);
        if (brand == 'example') {
          expect(find.text('Step 4 of 4'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

class _ReferralApi extends MobilePlatformApi {
  _ReferralApi() : super(Dio());

  @override
  Future<ReferralWelcome?> checkReferralCode(String referralCode) async =>
      const ReferralWelcome(inviterDisplayName: 'Friend');

  @override
  Future<ReferralQuote> getReferralQuote({
    required String registrationAttemptId,
    required String referralCode,
    required String source,
    String? invitationToken,
    required String locale,
  }) async =>
      ReferralQuote(
        quoteId: 'quote',
        registrationAttemptId: registrationAttemptId,
        termsVersion: 3,
        termsText: 'Long referral programme conditions',
        termsHash: 'terms',
        policyHash: 'policy',
        expiresAt: DateTime.utc(2099),
      );
}

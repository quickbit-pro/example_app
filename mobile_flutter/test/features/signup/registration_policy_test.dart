import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/presentation/example_auth_field.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/features/signup/domain/registration_policy_failure.dart';
import 'package:mobile_flutter/flavors.dart';

Map<String, dynamic> _config({Map<String, dynamic>? registration}) => {
      'company': {'name': 'ExampleCo'},
      'features': {
        'equalsMoneyEnabled': false,
        'businessOnboardingEnabled': false
      },
      if (registration != null) 'registration': registration,
    };

class _SignupAdapter implements HttpClientAdapter {
  Map<String, dynamic>? submitted;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    expect(options.path, '/api/v1/mobile/auth/signup');
    submitted = Map<String, dynamic>.from(options.data as Map);
    return ResponseBody.fromString(
        jsonEncode({'message': 'Account created'}), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, MobileTenantConfig config,
    {required String brand, int initialStep = 0}) async {
  final branding = AppBranding(
    appName: brand,
    brandId: brand,
    primarySeedHex: '7B6CF6',
    accentSeedHex: 'A78BFA',
    loginBackgroundHex: '',
    themeMode: 'dark',
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
      mobileTenantConfigProvider.overrideWith((ref) async => config),
    ],
    child: MaterialApp(
        theme: themes.dark, home: SignupScreen(initialStep: initialStep)),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('only definitive policy refusals release a frozen signup draft', () {
    expect(
        canRestartRegistrationSignup('auth.signup.country_blocked', 403), true);
    expect(canRestartRegistrationSignup('auth.signup.country_required', 400),
        true);
    expect(
        canRestartRegistrationSignup(
            'auth.signup.external_wallet_required', 400),
        true);
    expect(
        canRestartRegistrationSignup('auth.signup.external_wallet_invalid', 400),
        true);
    expect(canRestartRegistrationSignup('auth.signup.country_blocked', 502),
        false);
    expect(canRestartRegistrationSignup('auth.signup.creation_uncertain', 503),
        false);
    expect(
        canRestartRegistrationSignup('auth.signup.provider_unavailable', 502),
        false);
    expect(canRestartRegistrationSignup(null, null), false);
    expect(
        shouldRefreshRegistrationPolicy('auth.signup.policy_unavailable', 503),
        true);
    expect(canRestartRegistrationSignup('auth.signup.policy_unavailable', 503),
        true);
    expect(canRestartRegistrationSignup('auth.signup.policy_unavailable', 502),
        false);
  });
  test('authoritative registration policy overrides legacy referral options',
      () {
    final config = MobileTenantConfig.fromJson(_config(registration: {
      'available': true,
      'allowsSelfRegistration': true,
      'requireExternalWallet': true,
      'referralRequired': true,
      'referralCodesEnabled': true,
      'blockedCountries': ['si', ' SI ', 'DE'],
    }));
    expect(config.signupAvailable, true);
    expect(config.referralRequired, true);
    expect(config.referralsEnabled, false);
    expect(config.signupReferralCodesEnabled, true);
    expect(config.requireExternalWallet, true);
    expect(config.blockedRegistrationCountries, ['SI', 'DE']);
    expect(config.isRegistrationCountryAllowed('si'), false);
    expect(config.isRegistrationCountryAllowed('FR'), true);
    expect(config.isRegistrationCountryAllowed(null), false);
    expect(config.isRegistrationCountryAllowed('France'), false);
  });

  test(
      'unavailable or disabled policy closes signup; missing legacy object stays compatible',
      () {
    expect(MobileTenantConfig.fromJson(_config()).signupAvailable, true);
    expect(
        MobileTenantConfig.fromJson(_config(registration: {
          'available': false,
          'allowsSelfRegistration': true,
        })).signupAvailable,
        false);
    expect(
        MobileTenantConfig.fromJson(_config(registration: {
          'available': true,
          'allowsSelfRegistration': false,
        })).signupAvailable,
        false);
  });

  test(
      'signup sends residence independently of phone and preserves wallet address',
      () async {
    final adapter = _SignupAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    await MobilePlatformApi(dio).signUp(
      email: 'person@example.test',
      password: 'Test password 1!',
      firstName: 'Test',
      lastName: 'Person',
      accountType: 'personal',
      emailVerificationCode: '123456',
      phone: '+38640123456',
      countryCode: ' de ',
      externalWalletAddress: ' 0xABC123 ',
    );
    expect(adapter.submitted!['countryCode'], 'DE');
    expect(adapter.submitted!['phone'], '+38640123456');
    expect(adapter.submitted!['externalWalletAddress'], '0xABC123');
  });

  for (final brand in ['example', 'hoppa']) {
    testWidgets(
        '$brand shows required signup codes without enabling referral rewards',
        (tester) async {
      await _pump(
          tester,
          MobileTenantConfig.fromJson(_config(registration: {
            'available': true,
            'allowsSelfRegistration': true,
            'referralCodesEnabled': true,
            'referralRequired': true,
          })),
          brand: brand,
          initialStep: 2);
      expect(find.byKey(const Key('signup_referral_code')), findsOneWidget);
      expect(find.text('Referral code'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('$brand closes signup and keeps sign in available',
        (tester) async {
      await _pump(
          tester,
          MobileTenantConfig.fromJson(_config(registration: {
            'available': true,
            'allowsSelfRegistration': false,
          })),
          brand: brand);
      expect(find.text('Registration is closed'), findsOneWidget);
      expect(find.text('Go to sign in'), findsOneWidget);
      expect(find.byKey(const Key('signup_email')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        '$brand requires wallet and excludes blocked residence countries',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
          tester,
          MobileTenantConfig.fromJson(_config(registration: {
            'available': true,
            'allowsSelfRegistration': true,
            'requireExternalWallet': true,
            'blockedCountries': ['SI'],
          })),
          brand: brand,
          initialStep: 1);
      final dropdown = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      expect(dropdown.value, isNull);
      final residence = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('signup_country_code')));
      expect(residence.validator!(null), isNotNull);
      expect(residence.validator!('SI'), isNotNull);
      expect(residence.validator!('DE'), isNull);
      expect(dropdown.items!.any((item) => item.value == 'SI'), false);
      expect(dropdown.items!.any((item) => item.value == 'DE'), true);
      final wallet = tester.widget<ExampleAuthField>(
          find.byKey(const Key('signup_external_wallet')));
      expect(wallet.validator!(''), isNotNull);
      expect(wallet.validator!('0xABC123'), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('unavailable policy offers retry instead of a form',
      (tester) async {
    await _pump(
        tester,
        MobileTenantConfig.fromJson(_config(registration: {
          'available': false,
          'allowsSelfRegistration': false,
        })),
        brand: 'example');
    expect(
        find.text('Registration is temporarily unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const Key('signup_email')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

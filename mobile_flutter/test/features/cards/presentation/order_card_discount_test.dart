import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/card_discount.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/cards/presentation/order_card_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

const tier =
    PlatformResource(id: '1', title: 'Standard', subtitle: '', metadata: {
  'monthlyFee': 8,
  'yearlyFee': 60,
  'cardTypes': [
    {
      'cardTypeId': 1,
      'name': 'Virtual',
      'currency': 'EUR',
      'issuanceFee': 20,
      'monthlySubscriptionFee': 99,
      'yearlySubscriptionFee': 999,
      'tierOverridesCardMonthly': true,
      'tierOverridesCardYearly': true
    },
    {
      'cardTypeId': 2,
      'name': 'Extra',
      'currency': 'EUR',
      'issuanceFee': 40,
      'monthlySubscriptionFee': 12,
      'yearlySubscriptionFee': 120
    },
  ],
});

class DiscountApi extends MobileBankingApi {
  DiscountApi() : super(Dio());
  Future<CardDiscount> Function(String) validate =
      (_) async => CardDiscount.fromJson({
            'isValid': true,
            'buyDiscountPercent': 25,
            'monthlyDiscountPercent': 50,
            'yearlyDiscountPercent': 100,
          });
  @override
  Future<CardDiscount> validateCardDiscount(String code) => validate(code);
}

Future<void> pumpScreen(WidgetTester tester, DiscountApi api,
    {bool example = false, bool dark = false}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final branding = AppBranding(
      appName: example ? 'EXAMPLE' : 'Hoppa',
      brandId: example ? 'example' : 'hoppa',
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: dark ? 'dark' : 'light',
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: '',
      supportPhone: '',
      legalEntity: '');
  final themes = buildAppThemes(branding);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://localhost',
            branding: branding)),
        mobileBankingApiProvider.overrideWithValue(api),
        mobileTenantConfigProvider
            .overrideWith((_) async => MobileTenantConfig.fromJson(const {})),
        kycDetailedStatusProvider
            .overrideWith((_) async => KycDetailedStatus.fromJson(const {
                  'interlace': {'approved': true, 'status': 'approved'},
                })),
        currentTierProvider.overrideWith((_) async => tier),
        tiersProvider.overrideWith((_) async => [tier]),
        cardTierProvider('1').overrideWith((_) async => tier),
        budgetsProvider.overrideWith((_) async => []),
      ],
      child: MaterialApp(
          theme: themes.light,
          darkTheme: themes.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const OrderCardScreen())));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.ensureVisible(find.byKey(const ValueKey('card-discount-code')));
  await tester.pump();
}

Future<void> apply(WidgetTester tester, String code) async {
  await tester.enterText(
      find.byKey(const ValueKey('card-discount-code')), code);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.ensureVisible(find.text('Apply'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Apply'));
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final example in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
          'discount pricing and review retain Flutter design example=$example dark=$dark',
          (tester) async {
        final api = DiscountApi();
        await pumpScreen(tester, api, example: example, dark: dark);
        await apply(tester, 'save25');
        expect(find.text('Discount applied!'), findsOneWidget);
        expect(find.text('15.00 EUR'), findsOneWidget);
        expect(find.text('4.00 EUR'), findsOneWidget);
        expect(find.text('Free'), findsOneWidget);
        expect(find.text('25% off'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final confirm = find.text('Confirm & order Virtual');
        await tester.ensureVisible(confirm);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(confirm);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('SAVE25'), findsOneWidget);
        expect(find.text('15.00 EUR'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('editing invalidates applied prices and ignores stale responses',
      (tester) async {
    final api = DiscountApi();
    await pumpScreen(tester, api);
    await apply(tester, 'SAVE');
    await tester.enterText(
        find.byKey(const ValueKey('card-discount-code')), 'NEW');
    await tester.pump();
    expect(find.text('Discount applied!'), findsNothing);
    expect(find.text('15.00 EUR'), findsNothing);
    final pending = Completer<CardDiscount>();
    api.validate = (_) => pending.future;
    await apply(tester, 'OLD');
    await tester.enterText(
        find.byKey(const ValueKey('card-discount-code')), 'NEW');
    pending.complete(
        CardDiscount.fromJson({'isValid': true, 'buyDiscountPercent': 100}));
    await tester.pump();
    expect(find.text('Discount applied!'), findsNothing);
    expect(find.text('Free'), findsNothing);
  });
  testWidgets('fixed prices and server rejection are visible', (tester) async {
    final api = DiscountApi();
    api.validate = (_) async => CardDiscount.fromJson({
          'isValid': true,
          'discountType': 'fixed',
          'buyDiscountFixed': 3,
          'monthlyDiscountFixed': 0,
          'yearlyDiscountFixed': 10
        });
    await pumpScreen(tester, api);
    await apply(tester, 'FIXED');
    expect(find.text('3.00 EUR'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('10.00 EUR'), findsOneWidget);
    api.validate = (_) async => CardDiscount.fromJson(
        {'isValid': false, 'errorMessage': 'This code has expired'});
    await apply(tester, 'EXPIRED');
    expect(find.text('This code has expired'), findsOneWidget);
    expect(find.text('3.00 EUR'), findsNothing);
  });
}

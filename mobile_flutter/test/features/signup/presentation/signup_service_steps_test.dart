import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/legal_agreements.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/flavors.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final brand in ['example', 'hoppa']) {
    testWidgets('$brand services precede agreements and survive Back', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final branding = AppBranding(
        appName: brand, brandId: brand, primarySeedHex: '7B6CF6',
        accentSeedHex: 'A78BFA', loginBackgroundHex: '', themeMode: 'dark',
        fontFamily: '', logoAsset: '', radiusScale: '1',
        supportEmail: 'support@example.test', supportPhone: '', legalEntity: brand,
      );
      final themes = buildAppThemes(branding);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig(
            flavor: AppFlavor.dev, apiBaseUrl: 'http://127.0.0.1:1', branding: branding,
          )),
          mobileTenantConfigProvider.overrideWith((ref) async => const MobileTenantConfig(
            companyName: 'Test', brandName: 'Test', referralsEnabled: false,
            referralRegistrationMode: 'optional', vouchersEnabled: true,
            existingAccountClaimEnabled: true, boomFiExchangeEnabled: true,
            walletOutflowsEnabled: true, equalsMoneyEnabled: true,
            unifiedCddOnboardingEnabled: true,
          )),
        ],
        child: MaterialApp(theme: themes.dark, home: const SignupScreen(initialStep: 3)),
      ));
      await settle(tester);
      expect(find.byKey(const Key('signup-service-selection')), findsOneWidget);
      if (brand == 'example') {
        expect(find.byType(LegalAgreementsSection), findsNothing);
      } else {
        expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 3);
      }
      final banking = find.widgetWithText(CheckboxListTile, 'Banking');
      final exchange = find.widgetWithText(CheckboxListTile, 'Exchange');
      tester.widget<CheckboxListTile>(banking).onChanged!(true);
      tester.widget<CheckboxListTile>(exchange).onChanged!(true);
      await settle(tester);
      expect(find.widgetWithText(CheckboxListTile, 'Crypto card'), findsNothing);
      if (brand == 'example') {
        await tester.tap(find.text('Continue'));
      } else {
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue').last).onPressed!();
      }
      await settle(tester);
      expect(find.byType(LegalAgreementsSection), findsOneWidget);
      if (brand == 'example') {
        expect(find.byKey(const Key('signup-service-selection')), findsNothing);
      }
      expect(find.text('Create account'), findsWidgets);
      if (brand == 'example') {
        expect(find.text('Step 5 of 5'), findsOneWidget);
      } else {
        expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 4);
      }
      if (brand == 'example') {
        await tester.tap(find.text('Back'));
      } else {
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Back').last).onPressed!();
      }
      await settle(tester);
      expect(tester.widget<CheckboxListTile>(banking).value, isTrue);
      expect(tester.widget<CheckboxListTile>(exchange).value, isTrue);
      if (brand == 'example') {
        expect(find.byType(LegalAgreementsSection), findsNothing);
      } else {
        expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 3);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

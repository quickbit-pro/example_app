import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/flavors.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(384, 600),
    const Size(390, 700),
    const Size(1600, 800)
  ]) {
    testWidgets('signup steps start at the top at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = size.width >= 900;
      const branding = AppBranding(
        appName: 'Example',
        brandId: 'example',
        design: AppDesign({'layout': 'example'}),
        primarySeedHex: '7B6CF6',
        accentSeedHex: 'A78BFA',
        loginBackgroundHex: '',
        themeMode: 'dark',
        fontFamily: '',
        logoAsset: '',
        radiusScale: '1',
        supportEmail: 'support@example.test',
        supportPhone: '',
        legalEntity: 'Test',
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://127.0.0.1:1',
            branding: branding,
          )),
          mobileTenantConfigProvider.overrideWith(
            (ref) async => MobileTenantConfig(
              companyName: 'Test',
              brandName: 'Test',
              referralsEnabled: false,
              referralRegistrationMode: 'optional',
              vouchersEnabled: true,
              existingAccountClaimEnabled: true,
              boomFiExchangeEnabled: true,
              walletOutflowsEnabled: true,
              equalsMoneyEnabled: true,
              unifiedCddOnboardingEnabled: !desktop,
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAppThemes(branding).dark,
          home: SignupScreen(initialStep: desktop ? 2 : 0),
        ),
      ));
      await _settle(tester);

      final scrollView = find.byType(SingleChildScrollView);
      ScrollPosition position() => tester
          .state<ScrollableState>(find
              .descendant(
                of: scrollView,
                matching: find.byType(Scrollable),
              )
              .first)
          .position;

      if (desktop) {
        await tester.enterText(
            find.byType(EditableText).first, 'ValidExample1234');
        await _settle(tester);
      }
      await tester.drag(scrollView, const Offset(0, -1200));
      await _settle(tester);
      if (!desktop) expect(position().pixels, greaterThan(0));
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(position().pixels, 0);
      expect(find.text(desktop ? 'Step 4 of 4' : 'Step 2 of 5').hitTestable(),
          findsOneWidget);
      if (desktop) {
        await tester.drag(scrollView, const Offset(0, -3000));
        await _settle(tester);
        expect(position().pixels, greaterThan(0));
        await tester.ensureVisible(find.text('Back'));
        await tester.tap(find.text('Back'));
        await _settle(tester);
        expect(position().pixels, 0);
        expect(find.text('Step 3 of 4').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }

      // Returning to a step also restores its heading, not its old offset.
      final firstName = find.byType(EditableText).first;
      expect(firstName.hitTestable(), findsOneWidget);
      await tester.enterText(firstName, 'Alex');
      await tester.drag(scrollView, const Offset(0, -1200));
      await _settle(tester);
      expect(position().pixels, greaterThan(0));
      await tester.tap(find.text('Back'));
      await _settle(tester);
      expect(position().pixels, 0);
      expect(find.text('Step 1 of 5').hitTestable(), findsOneWidget);

      // Scroll reset must preserve the details already entered.
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(position().pixels, 0);
      expect(tester.widget<EditableText>(firstName).controller.text, 'Alex');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/routes.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/presentation/payments_screen.dart';
import 'package:mobile_flutter/flavors.dart';

void main() {
  for (final brand in ['generic', 'example']) {
    testWidgets('$brand payments sends customers through Money',
        (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: AppRoutes.payments,
        routes: [
          GoRoute(
            path: AppRoutes.payments,
            builder: (_, __) => const PaymentsScreen(),
          ),
          GoRoute(
            path: AppRoutes.pay,
            builder: (_, __) => const Scaffold(
              body: Text('Money payment flow'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      final branding = AppBranding(
        appName: 'Payments test',
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
        legalEntity: 'Payments test',
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          paymentsProvider.overrideWith((ref) async => const []),
          mandatesProvider.overrideWith((ref) async => const []),
          paymentRequestsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp.router(
          theme: buildAppThemes(branding).dark,
          routerConfig: router,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Create payout'), findsNothing);
      final sendPayment = find.text('Send payment');
      await tester.ensureVisible(sendPayment);
      await tester.tap(sendPayment);
      await tester.pumpAndSettle();

      expect(router.routerDelegate.state.uri.path, AppRoutes.pay);
      expect(find.text('Money payment flow'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Destination address'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

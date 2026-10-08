import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart'
    as banking;
import 'package:mobile_flutter/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mobile_flutter/features/notifications/notifications.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/flavors.dart';

void main() {
  for (final brand in ['generic', 'example']) {
    testWidgets(
        'Try again refetches failed sources and handles failure: $brand',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(ProviderScope(overrides: [
        appConfigProvider.overrideWithValue(AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'https://example.test',
            branding: AppBranding(
                appName: brand,
                primarySeedHex: '7C5CFF',
                accentSeedHex: '7C5CFF',
                loginBackgroundHex: '101020',
                themeMode: 'dark',
                fontFamily: '',
                logoAsset: '',
                radiusScale: '1',
                supportEmail: '',
                supportPhone: '',
                legalEntity: '',
                brandId: brand))),
        banking.dashboardProvider.overrideWith((ref) async {
          calls++;
          throw DioException(
              requestOptions: RequestOptions(path: '/profile'),
              type: DioExceptionType.connectionError);
        }),
        banking.accountsProvider.overrideWith((ref) async => []),
        budgetsProvider.overrideWith((ref) async => []),
        portfolioEstimateProvider.overrideWith((ref) async =>
            throw DioException(requestOptions: RequestOptions())),
        mobileTenantConfigProvider.overrideWith(
            (ref) async => MobileTenantConfig.fromJson(const {'features': {}})),
        unreadNotificationCountProvider.overrideWith((ref) async => 0),
      ], child: const MaterialApp(home: DashboardScreen())));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2,
          reason:
              'Retry must invalidate the failed banking source, not just its composed Home provider.');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(tester.takeException(), isNull);
    });
  }
}

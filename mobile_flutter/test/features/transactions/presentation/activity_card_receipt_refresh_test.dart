import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/transactions/presentation/transactions_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _branding = AppBranding(
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

const _tenant = MobileTenantConfig(
  companyName: 'EXAMPLE',
  brandName: 'EXAMPLE',
  referralsEnabled: true,
  referralRegistrationMode: 'open',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
  supportEmail: 'support@example.com',
);

void main() {
  for (final initiallyCached in [false, true]) {
    testWidgets(
        'opening selected-card receipt refreshes only absent global activity '
        '(cached: $initiallyCached)', (tester) async {
      const size = Size(1440, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      });

      final transaction = LedgerTransaction.fromJson({
        'id': 'new-card-payment',
        'cardId': '1',
        'title': 'New card payment',
        'amount': -12.50,
        'currency': 'USD',
        'type': 'card_payment',
        'status': 'completed',
        'bookedAt': DateTime.now().toIso8601String(),
      });
      final olderTransaction = LedgerTransaction.fromJson({
        'id': 'older-card-payment',
        'cardId': '1',
        'title': 'Older card payment',
        'amount': -1,
        'currency': 'USD',
        'type': 'card_payment',
        'status': 'completed',
        'bookedAt':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      });
      var globalLoads = 0;
      var includeNew = initiallyCached;
      final cardLoads = <String>[];
      final router = GoRouter(
        initialLocation: '/activity',
        routes: [
          GoRoute(
            path: '/activity',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/transactions/:id',
            builder: (context, state) => Consumer(
              builder: (context, ref, child) {
                // Receipts resolve their transaction from the global feed.
                // Watching it here reproduces that contract without unrelated
                // receipt detail providers obscuring cache invalidation.
                final activity = ref.watch(activityTransactionsProvider);
                return Scaffold(
                  body: activity.when(
                    data: (items) => Text(
                      items.any((item) => item.id == state.pathParameters['id'])
                          ? 'Receipt loaded: ${state.pathParameters['id']}'
                          : 'Receipt unavailable',
                    ),
                    loading: () => const Text('Loading receipt'),
                    error: (error, stack) => const Text('Receipt failed'),
                  ),
                );
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final themes = buildAppThemes(_branding);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityTransactionsProvider.overrideWith((ref) async {
              globalLoads++;
              return includeNew ? [transaction] : [olderTransaction];
            }),
            activityCardTransactionsProvider.overrideWith((ref, cardId) async {
              cardLoads.add(cardId);
              return [transaction];
            }),
            cardsProvider.overrideWith((ref) async => [
                  PaymentCard.fromJson(
                      {'id': '1', 'label': 'Metal', 'last4': '1234'}),
                ]),
            mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
          ],
          child: MaterialApp.router(
            theme: themes.light,
            darkTheme: themes.dark,
            themeMode: ThemeMode.dark,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entryLoads = globalLoads;
      expect(entryLoads, greaterThan(0));
      expect(find.byKey(const ValueKey('activity-direction-filter')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('activity-asset-filter')), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<Object>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Card').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activity-scope-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metal · •••• 1234').last);
      await tester.pumpAndSettle();
      expect(cardLoads, isNotEmpty);
      expect(cardLoads, everyElement('1'));
      final loadsBeforeReceipt = globalLoads;
      expect(loadsBeforeReceipt, greaterThanOrEqualTo(entryLoads));

      includeNew = true;
      await tester.tap(find.text('New card payment'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path,
          '/transactions/new-card-payment');
      expect(find.text('Receipt loaded: new-card-payment'), findsOneWidget);
      expect(find.text('Receipt unavailable'), findsNothing);
      expect(globalLoads, loadsBeforeReceipt + (initiallyCached ? 0 : 1));
      expect(tester.takeException(), isNull);
    });
  }
}

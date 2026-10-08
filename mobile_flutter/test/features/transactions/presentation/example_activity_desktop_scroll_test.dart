import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  for (final width in [1440.0, 2144.0]) {
    testWidgets(
        'desktop dates scroll away across multiple days at ${width.toInt()}',
        (tester) async {
      final size = Size(width, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      });

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      // Separate day groups reproduce the accumulated headers in the report.
      // These are isolated widget fixtures, never part of the app's API data.
      final ledger = [
        for (var day = 0; day < 14; day++)
          for (var row = 0; row < 2; row++)
            LedgerTransaction(
              id: 'day-$day-row-$row',
              title: 'Payment $day / $row',
              subtitle: 'completed',
              status: 'completed',
              amount: const Money(currency: 'USD', minorUnits: -125),
              bookedAt: today.subtract(Duration(days: day, minutes: row)),
              type: TransactionType.card,
              rawType: 'card_payment',
            ),
      ];
      final themes = buildAppThemes(_branding);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityTransactionsProvider.overrideWith((ref) async => ledger),
            mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
          ],
          child: MaterialApp(
            theme: themes.light,
            darkTheme: themes.dark,
            themeMode: ThemeMode.dark,
            home: const TransactionsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollView = find.byType(CustomScrollView);
      expect(scrollView, findsOneWidget);
      final viewport = tester.getRect(scrollView);
      expect(viewport.width, closeTo(width, 1));
      final todayHeading = find.text('Today');
      expect(todayHeading.hitTestable(), findsOneWidget);
      final todayTop = tester.getTopLeft(todayHeading).dy;

      final dateHeadings = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Today' ||
                widget.data == 'Yesterday' ||
                RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d+ ')
                    .hasMatch(widget.data ?? '')),
      );

      for (var step = 0; step < 5; step++) {
        // A wheel over the ledger scrolls past successive date groups.
        await tester.sendEventToBinding(PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: viewport.center,
          scrollDelta: const Offset(0, 300),
        ));
        await tester.pumpAndSettle();

        expect(todayHeading.hitTestable(), findsNothing,
            reason: 'The first date must leave the viewport, not stay pinned.');
        if (todayHeading.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(todayHeading).dy, lessThan(todayTop - 250));
        }

        final visibleHeaders = dateHeadings.hitTestable();
        expect(visibleHeaders.evaluate(), isNotEmpty);
        for (final heading in visibleHeaders.evaluate()) {
          final headingRect = tester.getRect(find.byWidget(heading.widget));
          for (final transaction in ledger) {
            final row = find.byKey(ValueKey(transaction.id)).hitTestable();
            if (row.evaluate().isEmpty) continue;
            expect(headingRect.overlaps(tester.getRect(row)), isFalse,
                reason: 'A date heading must not cover a visible transaction.');
          }
        }
        expect(tester.takeException(), isNull);
      }

      await tester.sendEventToBinding(PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: viewport.center,
        scrollDelta: const Offset(0, -1500),
      ));
      await tester.pumpAndSettle();
      expect(todayHeading.hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(todayHeading).dy, closeTo(todayTop, .1));
      expect(tester.getBottomLeft(todayHeading).dy,
          lessThan(tester.getTopLeft(find.text('Payment 0 / 0')).dy));
      expect(tester.takeException(), isNull);
    });
  }
}

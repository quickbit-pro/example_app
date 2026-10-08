import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/transactions/presentation/transactions_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _accountId = '91bccb7d-d7c5-4e8b-8d8b-f6dde2392ea8';

// Measure narrow layouts with the shipped glyph widths, rather than Ahem's
// square test glyphs, which make a small crypto amount wider than a phone row.
Future<void> _loadFonts() async {
  const fonts = <String, List<String>>{
    'Geist': [
      'Geist-Regular.ttf',
      'Geist-Medium.ttf',
      'Geist-SemiBold.ttf',
      'Geist-Bold.ttf',
    ],
    'GeistMono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      final font = File('assets/fonts/$file');
      loader.addFont(
        Future.value(ByteData.view(font.readAsBytesSync().buffer)),
      );
    }
    await loader.load();
  }
}

final _ledger = [
  LedgerTransaction.fromJson({
    'id': 'fiat-debit',
    'title': 'Account payment',
    'type': 'transfer_out',
    'currency': 'USD',
    'amount': -2,
    'metadata': {'accountId': _accountId},
    'status': 'completed',
    'bookedAt': DateTime.now().toIso8601String(),
  }),
  LedgerTransaction.fromJson({
    'id': 'crypto-debit',
    'title': 'Crypto withdrawal',
    'type': 'crypto_withdrawal',
    'currency': 'USDC',
    'amount': 1,
    'metadata': {'accountId': _accountId},
    'status': 'completed',
    'bookedAt': DateTime.now().toIso8601String(),
  }),
];

Widget _app() {
  final themes = buildAppThemes(const AppBranding(
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
  ));
  return ProviderScope(
    overrides: [
      activityTransactionsProvider.overrideWith((ref) async => _ledger),
      accountsProvider.overrideWith((ref) async => const [
            AccountBalance(
              id: _accountId,
              name: 'Current',
              iban: '',
              balance: Money(currency: 'USD', minorUnits: 0),
              available: Money(currency: 'USD', minorUnits: 0),
            ),
          ]),
      budgetsProvider.overrideWith((ref) async => const []),
      mobileTenantConfigProvider
          .overrideWith((ref) async => const MobileTenantConfig(
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
              )),
    ],
    child: MaterialApp(
      theme: themes.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const TransactionsScreen(),
    ),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  for (final scenario in [
    (
      name: 'small phone with keyboard',
      size: const Size(320, 568),
      inset: 300.0
    ),
    (name: 'short landscape viewport', size: const Size(740, 280), inset: 0.0),
  ]) {
    testWidgets('Activity filters remain usable in ${scenario.name}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final scope = find.byKey(const ValueKey('activity-account-dropdown'));
      await _tapVisible(tester, scope);
      await _tapVisible(tester, find.text('Current · USD').last);

      // The user can open the keyboard while a specific account is selected.
      // Neither the filter controls nor the ledger may overflow the body.
      if (scenario.inset > 0) {
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
      }
      tester.view.physicalSize = scenario.size;
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.inset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('activity-compact-filters')),
          findsOneWidget);
      if (scenario.inset > 0) {
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isTrue,
          reason: 'Entering compact layout preserves the active search field.',
        );
      }

      await tester.ensureVisible(scope);
      await tester.pumpAndSettle();
      expect(scope.hitTestable(), findsOneWidget);
      expect(tester.widget<DropdownButton<String>>(scope).value,
          'account:$_accountId:USD');

      final direction = find.byKey(const ValueKey('activity-direction-filter'));
      await _tapVisible(
        tester,
        find.descendant(of: direction, matching: find.text('Out')),
      );
      final asset = find.byKey(const ValueKey('activity-asset-filter'));
      await _tapVisible(
        tester,
        find.descendant(of: asset, matching: find.text('Crypto')),
      );
      expect(find.byKey(const ValueKey<String>('crypto-debit')), findsNothing,
          reason: 'The selected USD account denomination remains active.');
      expect(find.text('Nothing matches those filters'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('fiat-debit')), findsNothing);

      // Choosing independent filters preserves the account and its dropdown
      // remains reachable even if the header had to scroll to expose it.
      await tester.ensureVisible(scope);
      await tester.pumpAndSettle();
      expect(scope.hitTestable(), findsOneWidget);
      expect(tester.widget<DropdownButton<String>>(scope).value,
          'account:$_accountId:USD');
      expect(tester.takeException(), isNull);
    });
  }
}

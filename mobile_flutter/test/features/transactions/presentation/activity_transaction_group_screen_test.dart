import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/shared/widgets/finance_transaction_row.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/transactions/application/activity_valuation_provider.dart';
import 'package:mobile_flutter/features/transactions/presentation/transactions_screen.dart';
import 'package:mobile_flutter/flavors.dart';

final _today = DateTime.now();

Future<void> _pumpAt(WidgetTester tester, Widget home, Size size,
    {required bool light,
    required bool hoppa,
    required List<LedgerTransaction> ledger}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  });
  final config =
      jsonDecode(File('config/hoppa.json').readAsStringSync()) as Map;
  final themes = buildAppThemes(AppBranding(
    appName: 'Hoppa',
    brandId: 'hoppa',
    design: AppDesign.fromJsonString(jsonEncode(config['design'])),
    primarySeedHex: '7B6CF6',
    accentSeedHex: 'A78BFA',
    loginBackgroundHex: '',
    themeMode: 'light',
    fontFamily: 'Inter',
    logoAsset: '',
    radiusScale: '1',
    supportEmail: '',
    supportPhone: '',
    legalEntity: 'Hoppa',
  ));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activityTransactionsProvider.overrideWith((ref) async => ledger),
        activityValuationProvider.overrideWith((ref) => {'USD': 1}),
        accountsProvider.overrideWith((ref) async => []),
        budgetsProvider.overrideWith((ref) async => []),
        cardsProvider.overrideWith((ref) async => []),
        mobileTenantConfigProvider
            .overrideWith((ref) async => const MobileTenantConfig(
                  companyName: 'Hoppa',
                  brandName: 'Hoppa',
                  referralsEnabled: false,
                  referralRegistrationMode: 'open',
                  vouchersEnabled: false,
                  existingAccountClaimEnabled: true,
                  boomFiExchangeEnabled: true,
                  walletOutflowsEnabled: true,
                  equalsMoneyEnabled: true,
                  supportEmail: '',
                )),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themes.light,
        home: home,
        builder: (context, child) => RepaintBoundary(
            key: const ValueKey('activity-test-capture'), child: child!),
      )));
  await tester.pumpAndSettle();
}

Future<void> _writeActivityScreenshot(
    WidgetTester tester, String filename) async {
  final output = Platform.environment['EXAMPLE_ACTIVITY_TEST_OUTPUT'];
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('activity-test-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$filename').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in [400, 500, 600, 700]) {
      final bytes =
          File('config/assets/hoppa-inter-$weight.ttf').readAsBytesSync();
      inter.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await inter.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final size in [const Size(375, 1000), const Size(1200, 1000)]) {
    testWidgets('Hoppa operation groups expand at ${size.width}',
        (tester) async {
      final ledger = [
        LedgerTransaction.fromJson({
          'id': 'fx',
          'type': 'fx_trade',
          'title': 'FX Trade: 555 HUF → 11.79 CNY',
          'amount': 11.79,
          'currency': 'CNY',
          'status': 'completed',
          'transactionDate': _today.toIso8601String(),
        }),
        LedgerTransaction.fromJson({
          'id': 'credit',
          'type': 'deposit',
          'title': 'Budget credit',
          'amount': 11.79,
          'currency': 'CNY',
          'status': 'completed',
          'parentTransactionId': 'fx',
          'isPrimary': false,
          'transactionDate': _today.toIso8601String(),
        }),
        LedgerTransaction.fromJson({
          'id': 'unload',
          'type': 'card_unload',
          'title': 'Card unload',
          'amount': 12,
          'currency': 'USD',
          'status': 'closed',
          'metadata': {'type': 3},
          'transactionDate':
              _today.subtract(const Duration(minutes: 1)).toIso8601String(),
        }),
        LedgerTransaction.fromJson({
          'id': 'wallet',
          'type': 'wallet_debit',
          'title': 'Infinity account wallet debit',
          'amount': 12,
          'currency': 'USD',
          'status': 'closed',
          'metadata': {'type': 3},
          'transactionDate': _today
              .subtract(const Duration(minutes: 1, milliseconds: 1))
              .toIso8601String(),
        }),
      ];
      await _pumpAt(tester, const TransactionsScreen(), size,
          light: true, hoppa: true, ledger: ledger);
      expect(find.byType(ExampleTransactionRow), findsNWidgets(2));
      expect(find.text('2 events'), findsOneWidget);
      expect(find.text('Budget credit'), findsNothing);
      expect(find.text('Infinity account wallet debit'), findsNothing);
      expect(find.text('Show 2 entries'), findsNWidgets(2));
      await _writeActivityScreenshot(
          tester, 'hoppa-groups-${size.width.toInt()}-collapsed.png');
      final toggle = find.byKey(const ValueKey('activity-group-toggle-fx'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Budget credit'), findsOneWidget);
      expect(find.byType(ExampleTransactionRow), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await _writeActivityScreenshot(
          tester, 'hoppa-groups-${size.width.toInt()}-expanded.png');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Budget credit'), findsNothing);
    });
  }
}

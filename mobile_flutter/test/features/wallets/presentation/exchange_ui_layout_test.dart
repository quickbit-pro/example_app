import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_panel.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';

import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_account_details.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_support.dart';

class UiApi extends MobilePlatformApi {
  UiApi() : super(Dio());
  bool fail = false;
  @override
  Future<Map<String, dynamic>> getExchangeVerification() async => {
        'hasProviderAccount': true,
        'provider': {'kycStatus': 'accepted'}
      };
  @override
  Future<BoomFiExchangeOverview> getExchangeOverview() async =>
      sample(fiat: false, amount: 0);
  @override
  Future<List<Map<String, dynamic>>> getExchangeDestinations() async {
    if (fail) {
      throw DioException(
          requestOptions: RequestOptions(path: 'https://private/api'),
          message: 'Internal error');
    }
    return [];
  }

  @override
  Future<List<PlatformResource>> getEqualsBankingInfos() async => [];
  @override
  Future<Map<String, dynamic>> getExchangeSettlementAccounts() async => {
        'kycStatus': 'accepted',
        'accounts': [
          {
            'name': 'ZBX USDC (SOL)',
            'reference': 'deposit-1-227-usdc-1399811149',
            'currencies': ['USDC'],
            'chainId': 1399811149,
            'ready': true,
            'address': 'A8CskNfm4vLve4RLwifdcFdNJHgYjwpocd57ZkzCcjiH'
          },
          {
            'name': 'ZBX EUR',
            'currencies': ['EUR'],
            'chainId': 0,
            'ready': false
          },
          {
            'currencies': ['USDC'],
            'chainId': 1,
            'reference': 'deposit-1-227-usdc-1',
            'ready': true,
            'address': '0xAc8237D9212A68ddeaA5ea4A3D5Eb4Ca93A952b1'
          },
        ]
      };
}

BoomFiExchangeOverview sample({bool fiat = true, double amount = 25}) =>
    BoomFiExchangeOverview(
        accountId: 1,
        accountName: 'Demo',
        accountEnabled: true,
        accountState: 'ready',
        balances: [
          BoomFiExchangeBalance(
              accountId: 1,
              currency: 'USDC',
              amount: amount,
              pendingAmount: 0,
              chainId: 1399811149,
              chainName: 'Solana',
              tokenAddress: ''),
          if (fiat)
            const BoomFiExchangeBalance(
                accountId: 2,
                currency: 'EUR',
                amount: 0,
                pendingAmount: 0,
                chainId: 0,
                chainName: '',
                tokenAddress: '')
        ],
        settlementAccounts: [],
        subAccounts: [],
        fiatFundingCurrencies: [
          'EUR'
        ]);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(Future.value(ByteData.sublistView(
          File('config/assets/hoppa-inter-400.ttf').readAsBytesSync())));
    await font.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(File(
                '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytesSync())));
      await icons.load();
    }
  });

  for (final size in [
    const Size(375, 812),
    const Size(1000, 900),
    const Size(568, 400)
  ]) {
    for (final scale in [1.0, 1.3]) {
      for (final scene in [
        'deposit',
        'withdraw',
        'convert',
        'unavailable',
        'error'
      ]) {
        testWidgets('$scene fits $size at $scale', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final config =
              jsonDecode(File('config/hoppa.json').readAsStringSync())
                  as Map<String, dynamic>;
          final theme = buildAppThemes(AppBranding(
                  appName: 'Hoppa',
                  brandId: 'hoppa',
                  primarySeedHex: '621A96',
                  accentSeedHex: 'C6F24E',
                  loginBackgroundHex: '',
                  themeMode: 'dark',
                  fontFamily: 'Inter',
                  logoAsset: '',
                  radiusScale: '1',
                  supportEmail: '',
                  supportPhone: '',
                  legalEntity: '',
                  design:
                      AppDesign.fromJsonString(jsonEncode(config['design']))))
              .dark;

          final api = UiApi()..fail = scene == 'error';
          final capture = GlobalKey();
          final dialog = scene == 'deposit'
              ? const ExchangeAccountDetails()
              : scene == 'error'
                  ? const ExchangeAccountDetails(destinations: true)
                  : ExchangeFlowDialog(
                      flow: scene == 'withdraw'
                          ? ExchangeFlow.withdraw
                          : ExchangeFlow.convert,
                      overview: sample(
                          fiat: scene != 'unavailable',
                          amount: scene == 'unavailable' ? 0 : 25),
                      outflowsEnabled: true);
          await tester.pumpWidget(ProviderScope(
              overrides: [payeesProvider.overrideWith((ref) async => []),
                      mobilePlatformApiProvider.overrideWithValue(api)],
              child: RepaintBoundary(
                  key: capture,
                  child: MaterialApp(
                      theme: theme,
                      debugShowCheckedModeBanner: false,
                      builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: TextScaler.linear(scale)),
                          child: child!),
                      home: Scaffold(
                          body: Builder(
                              builder: (context) => TextButton(
                                  onPressed: () => showDialog<void>(
                                      context: context, builder: (_) => dialog),
                                  child: const Text('Open'))))))));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final close = find
              .text(scene == 'deposit' || scene == 'error' ? 'Done' : 'Cancel');
          var footer = tester.getRect(close);
          expect(footer.bottom, lessThan(size.height));
          expect(find.textContaining('DioException'), findsNothing);
          if (scene == 'error') {
            expect(find.textContaining('couldn’t load'), findsOneWidget);
            expect(find.textContaining('being prepared'), findsNothing);
            api.fail = false;
            await tester.tap(find.text('Refresh'));
            await tester.pumpAndSettle();
            expect(
                find.textContaining('No saved destinations'), findsOneWidget);
            footer = tester.getRect(close);
          }
          if (scene == 'unavailable') {
            expect(find.byType(ExchangeBankFields), findsNothing);
            final action = tester.widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Get quote'));
            expect(action.onPressed, isNull);
          }
          if (scene == 'withdraw') {
            expect(find.text('Saved destination'), findsNothing);
          }
          if (scene == 'deposit') {
            expect(find.text('Solana'), findsOneWidget);
            expect(find.textContaining('Chain 139'), findsNothing);
          }
          await tester.drag(
              find.byType(SingleChildScrollView).first, const Offset(0, -1500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getRect(close), footer);
          if (const bool.fromEnvironment('CAPTURE_EXCHANGE_UI') &&
              scale == 1 &&
              size.height > 500) {
            await tester.drag(find.byType(SingleChildScrollView).first,
                const Offset(0, 4000));
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final image = await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
              final png =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              File('/private/tmp/hoppa-$scene-${size.width.toInt()}.png')
                  .writeAsBytesSync(png!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(close);
          await tester.pumpAndSettle();
        });
      }
    }
  }

  for (final size in [const Size(375, 812), const Size(1000, 900)]) {
    testWidgets('overview prioritizes deposit with zero balances at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final config = jsonDecode(File('config/hoppa.json').readAsStringSync())
          as Map<String, dynamic>;
      final theme = buildAppThemes(AppBranding(
              appName: 'Hoppa',
              brandId: 'hoppa',
              primarySeedHex: '621A96',
              accentSeedHex: 'C6F24E',
              loginBackgroundHex: '',
              themeMode: 'dark',
              fontFamily: 'Inter',
              logoAsset: '',
              radiusScale: '1',
              supportEmail: '',
              supportPhone: '',
              legalEntity: '',
              design: AppDesign.fromJsonString(jsonEncode(config['design']))))
          .dark;

      final api = UiApi();
      final capture = GlobalKey();
      await tester.pumpWidget(ProviderScope(
          overrides: [payeesProvider.overrideWith((ref) async => []),
                      mobilePlatformApiProvider.overrideWithValue(api)],
          child: RepaintBoundary(
              key: capture,
              child: MaterialApp(
                  theme: theme,
                  debugShowCheckedModeBanner: false,
                  home: Scaffold(
                      body: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: ExchangePanel(
                              config: MobileTenantConfig.fromJson(const {'features': {'walletOutflowsEnabled': true}}),
                              budgets: const [],
                              wallets: const [],
                              transferSection: const SizedBox.shrink())))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(
          tester
              .widget<ExampleGlassButton>(
                  find.widgetWithText(ExampleGlassButton, 'Convert'))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<ExampleGlassButton>(
                  find.widgetWithText(ExampleGlassButton, 'Withdraw'))
              .onPressed,
          isNull);
      if (const bool.fromEnvironment('CAPTURE_EXCHANGE_UI')) {
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('/private/tmp/hoppa-overview-${size.width.toInt()}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Saved destinations'), findsOneWidget);
    });
  }
}

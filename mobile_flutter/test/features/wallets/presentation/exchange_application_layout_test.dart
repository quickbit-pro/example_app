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
import 'package:mobile_flutter/features/wallets/presentation/exchange_verification_panel.dart';

class _TimeoutApi extends MobilePlatformApi {
  _TimeoutApi() : super(Dio());
  int calls = 0;
  @override
  Future<Map<String, dynamic>> submitExchangeApplication(
      Map<String, String> answers) async {
    calls++;
    final request = RequestOptions(path: '/exchange/verification/application');
    throw DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: 504),
        message: 'Provider request timed out');
  }
}

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
  testWidgets(
      'uncertain submission shows a useful message and prevents duplicate retries',
      (tester) async {
    final api = _TimeoutApi();
    await tester.pumpWidget(ProviderScope(
        overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
        child: MaterialApp(
            home: Scaffold(
                body: const ExchangeApplicationDialog(initial: {
          'sdd_country_select': 'SI',
          'investment_citizenship': '82',
          'employment_type_or_status': '15',
          'industry': '51',
          'employment_jurisdiction': 'SI',
          'acting_capacity': '156',
          'annual_income': '74',
          'expected_deposit_one_year': '83',
          'hnwi_str': '78',
          'source_of_funds': '54',
          'source_of_funds_of_country': 'SI',
          'source_of_wealth_of_country': 'SI',
        })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit application'));
    await tester.pumpAndSettle();
    expect(find.textContaining('We could not confirm your application'),
        findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit application'))
            .onPressed,
        isNull);
    expect(api.calls, 1);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(375, 812),
    const Size(1000, 900),
    const Size(568, 400)
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('application fits $size at text scale $scale',
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
        final capture = GlobalKey();
        await tester.pumpWidget(ProviderScope(
            child: RepaintBoundary(
                key: capture,
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!),
                    home: Scaffold(
                        body: Builder(
                            builder: (context) => TextButton(
                                onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) =>
                                        const ExchangeApplicationDialog(
                                            initial: {
                                              'sdd_country_select': 'SI',
                                              'investment_citizenship': '82',
                                              'employment_type_or_status': '15',
                                              'industry': '51',
                                              'employment_jurisdiction': 'SI',
                                              'acting_capacity': '156'
                                            })),
                                child: const Text('Open'))))))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final submit = find.widgetWithText(FilledButton, 'Submit application');
        final footerBefore = tester.getRect(submit);
        expect(footerBefore.bottom, lessThan(size.height));
        expect(
            tester.getRect(find.text('Country of residence')).bottom,
            lessThan(tester
                .getRect(find.byType(DropdownButtonFormField<String>).first)
                .top));
        final scroller = find.byType(SingleChildScrollView).first;
        await tester.drag(scroller, const Offset(0, -2000));
        await tester.pumpAndSettle();
        await tester.drag(scroller, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(submit), footerBefore);
        expect(find.text('Countries where wealth originates').hitTestable(),
            findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_EXCHANGE_UI') &&
            scale == 1 &&
            size.height > 500) {
          await tester.drag(scroller, const Offset(0, 4000));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('/private/tmp/hoppa-exchange-ui-${size.width.toInt()}.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}

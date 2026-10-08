import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/cards/presentation/widgets/card_face.dart';
import 'package:mobile_flutter/features/dashboard/presentation/example_activation_panel.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'example_activation_panel_test.dart' show snapshot;

const _branding = AppBranding(appName: 'EXAMPLE', brandId: 'example', primarySeedHex: '7B6CF6', accentSeedHex: 'A78BFA',
  loginBackgroundHex: '', themeMode: 'dark', fontFamily: 'Geist', logoAsset: '', radiusScale: '1', supportEmail: '', supportPhone: '', legalEntity: 'EXAMPLE');
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Geist')..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final light in [false, true]) {
    testWidgets('Example activation and preview visual light=$light', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Money.maskAmounts = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(requestOptions: request, data: request.method == 'GET'
          ? {'data': [], 'pagination': {'hasNext': false}}
          : {'showIntroduction': request.data['claimIntroduction'] == true, 'hasCompletedDeposit': false}));
      }));
      final themes = buildAppThemes(_branding);
      await tester.pumpWidget(ProviderScope(overrides: [dioProvider.overrideWithValue(dio)], child: MaterialApp(
        debugShowCheckedModeBanner: false, theme: light ? themes.light : themes.dark,
        home: Scaffold(body: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 32),
          ExampleActivationPanel(snapshot: snapshot()),
          const ExampleReferralTeaser(enabled: true),
          const SizedBox(height: 16),
          CardFace(showBalance: true, interactive: false, sweepOnArrival: false, card: PaymentCard.fromJson({
            'id': '1', 'last4': '1234', 'status': 'active', 'currency': 'USD', 'balance': {'currency': 'USD', 'amount': 45.50},
          })),
          const SizedBox(height: 16),
          CardFace(showBalance: true, interactive: false, sweepOnArrival: false, card: PaymentCard.fromJson({
            'id': '2', 'last4': '9876', 'status': 'active', 'currency': 'USD',
          })),
        ])),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/activation_intro_${light ? 'light' : 'dark'}.png'));
      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/activation_remaining_${light ? 'light' : 'dark'}.png'));
    });
  }
}

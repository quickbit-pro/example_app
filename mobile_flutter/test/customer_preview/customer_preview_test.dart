import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/app/shell/banking_shell.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/customer_preview/customer_preview_app.dart';
import 'package:mobile_flutter/customer_preview/preview_configuration.dart';
import 'package:mobile_flutter/customer_preview/preview_fixtures.dart';
import 'package:mobile_flutter/features/auth/presentation/login_screen.dart';
import 'package:mobile_flutter/features/cards/presentation/cards_screen.dart';
import 'package:mobile_flutter/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mobile_flutter/features/profile/presentation/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _message(
        {String screen = 'home', String theme = 'light'}) =>
    {
      'type': 'customer-brand-update',
      'screen': screen,
      'theme': theme,
      'config': {
        'schemaVersion': 1,
        'app': {
          'name': 'Harbor Money',
          'id': 'harbor',
          'supportEmail': 'support@example.invalid',
        },
        'design': {
          'layout': 'example',
          'light': {'paper': '#F1FAF8', 'fill': '#006C65', 'accent': '#006C65'},
          'dark': {'paper': '#062824', 'fill': '#2AAB95', 'accent': '#65E7D2'},
          'assets': {'logo': ''},
          'typography': {'fontFamily': 'Geist', 'monoFontFamily': 'GeistMono'},
          'motion': {'enabled': false},
        },
        'flutterDefines': {
          'API_BASE_URL': 'https://production.example.invalid'
        },
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    for (final family in ['Geist', 'GeistMono']) {
      final loader = FontLoader(family);
      loader.addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      await loader.load();
    }
  });

  for (final theme in ['light', 'dark']) {
    for (final entry in <String, Type>{
      'home': DashboardScreen,
      'login': LoginScreen,
      'cards': CardsScreen,
      'profile': ProfileScreen,
    }.entries) {
      testWidgets('renders production ${entry.key} screen in $theme theme',
          (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final config = await CustomerPreviewConfiguration.fromMessage(
          _message(screen: entry.key, theme: theme),
        );
        await tester.pumpWidget(CustomerPreviewApp(configuration: config));
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(find.byType(entry.value), findsOneWidget);
        if (entry.key != 'login') {
          expect(find.byType(BankingShell), findsOneWidget);
        }
        final context = tester.element(find.byType(entry.value));
        expect(AppDesignTheme.nameOf(context), 'Harbor Money');
        expect(Theme.of(context).brightness,
            theme == 'light' ? Brightness.light : Brightness.dark);
        expect(AppDesignTheme.of(context).asset('logo'), '');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('live branding edits preserve login state and navigator',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = await CustomerPreviewConfiguration.fromMessage(
      _message(screen: 'login'),
    );
    await tester.pumpWidget(CustomerPreviewApp(configuration: first));
    await tester.pump(const Duration(seconds: 1));
    final loginState = tester.state(find.byType(LoginScreen));
    final email = find.byType(EditableText).first;
    await tester.enterText(email, 'alex@example.test');
    final emailFocus = tester.widget<EditableText>(email).focusNode;

    final message = _message(screen: 'login', theme: 'dark');
    ((message['config'] as Map<String, dynamic>)['app']
        as Map<String, dynamic>)['name'] = 'Updated Harbor';
    final updated = await CustomerPreviewConfiguration.fromMessage(message);
    await tester.pumpWidget(CustomerPreviewApp(configuration: updated));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.state(find.byType(LoginScreen)), same(loginState));
    expect(tester.widget<EditableText>(email).controller.text,
        'alex@example.test');
    expect(tester.widget<EditableText>(email).focusNode, same(emailFocus));
    expect(emailFocus.hasFocus, isTrue);
    final context = tester.element(find.byType(LoginScreen));
    expect(AppDesignTheme.nameOf(context), 'Updated Harbor');
    expect(Theme.of(context).brightness, Brightness.dark);

    final cards = await CustomerPreviewConfiguration.fromMessage(
      _message(screen: 'cards'),
    );
    await tester.pumpWidget(CustomerPreviewApp(configuration: cards));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CardsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('imported customer API never reaches preview transport', () async {
    final config = await CustomerPreviewConfiguration.fromMessage(_message());
    final container =
        ProviderContainer(overrides: customerPreviewOverrides(config.branding));
    addTearDown(container.dispose);
    expect(container.read(appConfigProvider).apiBaseUrl,
        'https://preview.invalid');
    final dio = container.read(dioProvider);
    for (final method in ['GET', 'POST', 'DELETE']) {
      await expectLater(
        dio.request<dynamic>('https://production.example.invalid/payments',
            options: Options(method: method)),
        throwsA(isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)),
      );
    }
  });

  test('source image bytes reach production AssetImage bundle keys', () async {
    final message = _message();
    final config = message['config'] as Map<String, dynamic>;
    (config['design'] as Map<String, dynamic>)['assets'] = {
      'logo': 'assets/customer-logo.png'
    };
    message['assets'] = [
      {
        'path': 'assets/customer-logo.png',
        'data': base64Encode([1, 2, 3]),
        'mime': 'image/png',
      }
    ];
    final preview =
        await CustomerPreviewConfiguration.fromMessage(message, revision: 42);
    final asset = preview.branding.design.asset('logo');
    expect(asset, 'customer-preview/42/assets/customer-logo.png');
    final bytes = await preview.bundle.load(asset);
    expect(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        [1, 2, 3]);
  });

  test('rejects external/traversing assets and invalid palette colors',
      () async {
    for (final path in [
      'https://example.invalid/logo.png',
      '../logo.png',
      '/logo.png'
    ]) {
      final message = _message();
      ((message['config'] as Map<String, dynamic>)['design']
          as Map<String, dynamic>)['assets'] = {'logo': path};
      await expectLater(CustomerPreviewConfiguration.fromMessage(message),
          throwsFormatException);
    }
    final message = _message();
    ((message['config'] as Map<String, dynamic>)['design']
        as Map<String, dynamic>)['light'] = {'paper': 'javascript:invalid'};
    await expectLater(CustomerPreviewConfiguration.fromMessage(message),
        throwsFormatException);
  });
}

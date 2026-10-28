import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_verification_panel.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_support.dart';

class BusinessApi extends MobilePlatformApi {
  BusinessApi(
      {this.authorise = false, this.ready = true, this.confirmCode = true})
      : super(Dio());
  final bool authorise, confirmCode;
  bool ready;
  int starts = 0, sends = 0, confirmations = 0, legacyCalls = 0;
  bool connected = false;
  Map<String, dynamic>? edd;
  @override
  Future<Map<String, dynamic>> getExchangeVerification() async => {
        'eligible': true,
        'verificationType': 'business',
        'status': 'approved',
        'businessOnboardingSupported': true,
        'hasProviderAccount': connected,
        if (connected) 'provider': {'kycStatus': 'pending'},
      };
  @override
  Future<Map<String, dynamic>> getExchangeBusinessApplication() async => {
        'legalName': 'Saved Equals Company Ltd',
        'contactName': 'Test Owner',
        'contactEmail': 'owner@example.test',
        'contactPhone': '+38640123456',
        'readyToSubmit': ready,
        'issues': ready ? [] : ['Add a valid mobile number.'],
      };
  @override
  Future<Map<String, dynamic>> startExchangeBusiness() async {
    starts++;
    if (authorise && confirmations == 0)
      return {'status': 'authorisation_required'};
    connected = true;
    return {'status': 'pending'};
  }

  @override
  Future<Map<String, dynamic>> sendExchangeBusinessCode() async {
    sends++;
    return {'sent': true};
  }

  @override
  Future<Map<String, dynamic>> authoriseExchangeBusiness(String code) async {
    expect(code, '123456');
    confirmations++;
    return {'authorised': confirmCode};
  }

  @override
  Future<Map<String, dynamic>> startExchangeVerification(String tier) async {
    legacyCalls++;
    return {};
  }

  @override
  Future<Map<String, dynamic>> getExchangeApplication() async {
    legacyCalls++;
    return {};
  }

  @override
  Future<Map<String, dynamic>> submitExchangeEdd(
      Map<String, dynamic> request) async {
    edd = request;
    return {};
  }
}

Future<void> host(WidgetTester tester, BusinessApi api,
    {Size size = const Size(1000, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
    child: const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: ExchangeVerificationPanel()))),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Review business details'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('blocked details can be refreshed after correction', (tester) async {
    final api = BusinessApi(ready: false);
    await host(tester, api);
    expect(find.text('A detail needs your attention'), findsOneWidget);
    api.ready = true;
    await tester.ensureVisible(find.text('Refresh details'));
    await tester.tap(find.text('Refresh details'));
    await tester.pumpAndSettle();
    expect(find.text('A detail needs your attention'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,
        'Continue to verification')).onPressed, isNotNull);
    expect(api.starts, 0);
  });

  testWidgets('correction action opens support without starting onboarding', (tester) async {
    final api = BusinessApi();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: ExchangeVerificationPanel())),
      GoRoute(path: '/support', builder: (_, __) => const Scaffold(body: Text('Support tickets'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      mobilePlatformApiProvider.overrideWithValue(api),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review business details'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Need to update these details?'));
    await tester.tap(find.text('Need to update these details?'));
    await tester.pumpAndSettle();
    expect(find.text('Support tickets'), findsOneWidget);
    expect(api.starts, 0);
    expect(api.sends, 0);
  });

  for (final entry in {
    'pending': 'Complete the provider verification to continue.',
    'rejected': 'Your Exchange application was not approved. Contact support.',
    'accepted': 'Your account is approved. Settlement accounts are being prepared.',
  }.entries) {
    testWidgets('corporate provider status ${entry.key} controls resume', (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        exchangeVerificationProvider.overrideWith((ref) async => {
          'verificationType': 'business',
          'hasProviderAccount': true,
          'provider': {
            'kycStatus': entry.key,
            'nextAction': 'kyb_required',
            'verificationUrl': 'https://in.sumsub.com/verify',
          },
        }),
      ], child: const MaterialApp(home: Scaffold(body: ExchangeVerificationPanel()))));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Continue verification'), entry.key == 'pending' ? findsOneWidget : findsNothing);
      expect(find.text('Activate Exchange'), findsNothing);
      expect(find.text('Review business details'), findsNothing);
    });
  }

  testWidgets(
      'business reuses saved details and skips personal activation even with old approved KYB',
      (tester) async {
    final api = BusinessApi();
    await host(tester, api);
    expect(find.text('Saved Equals Company Ltd'), findsOneWidget);
    expect(find.text('Activate Exchange'), findsNothing);
    expect(api.starts, 0);
    await tester.tap(find.text('Continue to verification'));
    await tester.pumpAndSettle();
    expect(api.starts, 1);
    expect(api.legacyCalls, 0);
    expect(find.textContaining('under review'), findsOneWidget);
    expect(find.text('Review business details'), findsNothing);
  });

  testWidgets(
      'email authorisation is explicit and retries CORP only after confirmation',
      (tester) async {
    final api = BusinessApi(authorise: true);
    await host(tester, api);
    await tester.tap(find.text('Continue to verification'));
    await tester.pumpAndSettle();
    expect(api.sends, 0);
    await tester.tap(find.text('Send email code'));
    await tester.pumpAndSettle();
    expect(api.sends, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Verify and continue'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();
    expect(api.confirmations, 1);
    expect(api.starts, 2);
    expect(api.legacyCalls, 0);
  });

  testWidgets('failed authorisation does not retry create', (tester) async {
    final api = BusinessApi(authorise: true, confirmCode: false);
    await host(tester, api);
    await tester.tap(find.text('Continue to verification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send email code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();
    expect(api.starts, 1);
    expect(find.textContaining('was not confirmed'), findsOneWidget);
  });

  for (final size in [const Size(375, 812), const Size(568, 400)]) {
    testWidgets('missing details block start and review fits $size',
        (tester) async {
      final api = BusinessApi(ready: false);
      await host(tester, api, size: size);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(
                  FilledButton, 'Continue to verification'))
              .onPressed,
          isNull);
      expect(api.starts, 0);
      expect(tester.takeException(), isNull);
    });
  }

  test('corporate action URLs are parsed and unsafe links are rejected', () {
    expect(
        exchangeActionUrl(
            {'nextAction': 'kyb_required:https://in.sumsub.com/verify'}),
        'https://in.sumsub.com/verify');
    expect(exchangeActionUrl({'nextAction': 'kyb_required:http://unsafe.test'}),
        isNull);
  });

  testWidgets('EDD is text only and does not offer document URL input',
      (tester) async {
    final api = BusinessApi();
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
            home: Scaffold(body: ExchangeProviderActionDialog(tax: false)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Document uploads are not available'),
        findsOneWidget);
    expect(find.textContaining('Supporting document HTTPS'), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Company capital'),
        'Company retained earnings');
    await tester.tap(find.text('Submit information'));
    await tester.pumpAndSettle();
    expect(api.edd, {'capitalOfCompany': 'Company retained earnings'});
  });

  test(
      'business mobile API uses dedicated routes without client identity or documents',
      () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(
          requestOptions: request, data: <String, dynamic>{}, statusCode: 200));
    }));
    final api = MobilePlatformApi(dio);
    await api.getExchangeBusinessApplication();
    await api.startExchangeBusiness();
    await api.sendExchangeBusinessCode();
    await api.authoriseExchangeBusiness('123456');
    expect(requests.map((r) => r.method), ['GET', 'POST', 'POST', 'POST']);
    expect(requests.map((r) => r.path), [
      '/api/v1/mobile/exchange/verification/business',
      '/api/v1/mobile/exchange/verification/business',
      '/api/v1/mobile/exchange/verification/business/authorisation/send-code',
      '/api/v1/mobile/exchange/verification/business/authorisation',
    ]);
    expect(requests.last.data, {'code': '123456'});
    expect(requests[1].data, isEmpty);
  });
}

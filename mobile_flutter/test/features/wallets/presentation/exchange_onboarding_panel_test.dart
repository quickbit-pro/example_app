import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_onboarding_panel.dart';

void main() {
  Future<void> mount(WidgetTester tester,
      {required Map<String, dynamic> progress,
      bool selected = true,
      bool fail = false,
      required List<RequestOptions> requests}) async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      if (fail) {
        h.reject(DioException(requestOptions: r));
      } else {
        h.resolve(Response(
            requestOptions: r,
            data: r.path.endsWith('/preferences')
                ? {'enabled': true, 'exchange': selected, 'banking': true}
                : progress));
      }
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          mobileTenantConfigProvider
              .overrideWith((ref) async => MobileTenantConfig.fromJson({
                    'features': {'unifiedCddOnboardingEnabled': true},
                  })),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: ExchangeOnboardingPanel(
          legacy: Text('Activate Exchange'),
        )))));
    await tester.pumpAndSettle();
  }

  testWidgets('staging selected Exchange cannot activate or start another KYC',
      (tester) async {
    final requests = <RequestOptions>[];
    await mount(tester,
        progress: {
          'boomFi': 'disabled_in_staging',
          'submissionRequested': true
        },
        requests: requests);
    expect(find.text('Exchange is unavailable in staging.'), findsOneWidget);
    expect(find.text('Activate Exchange'), findsNothing);
    expect(find.text('Continue onboarding'), findsNothing);
    expect(requests.map((r) => r.method), everyElement('GET'));
  });
  for (final state in [
    'submitted',
    'dispatching',
    'not_started',
    'reconciliation_required'
  ]) {
    testWidgets('submitted production $state never offers duplicate activation',
        (tester) async {
      final requests = <RequestOptions>[];
      await mount(tester,
          progress: {'BoomFi': state, 'SubmissionRequested': true},
          requests: requests);
      expect(find.textContaining('application is in progress'), findsOneWidget);
      expect(find.text('Activate Exchange'), findsNothing);
      expect(find.text('Continue onboarding'), findsNothing);
      expect(requests.map((r) => r.method), everyElement('GET'));
    });
  }
  testWidgets('unfinished unified application returns to shared questionnaire',
      (tester) async {
    await mount(tester,
        progress: {'boomFi': 'not_started', 'submissionRequested': false},
        requests: []);
    expect(find.text('Continue onboarding'), findsOneWidget);
    expect(find.text('Activate Exchange'), findsNothing);
  });
  testWidgets('Exchange not selected preserves later legacy opt-in',
      (tester) async {
    final requests = <RequestOptions>[];
    await mount(tester, progress: {}, selected: false, requests: requests);
    expect(find.text('Activate Exchange'), findsOneWidget);
    expect(requests.length, 1);
  });
  testWidgets(
      'failed unified status does not fall back to duplicate activation',
      (tester) async {
    await mount(tester, progress: {}, fail: true, requests: []);
    expect(find.text('Could not check your Exchange application.'),
        findsOneWidget);
    expect(find.text('Activate Exchange'), findsNothing);
  });
}

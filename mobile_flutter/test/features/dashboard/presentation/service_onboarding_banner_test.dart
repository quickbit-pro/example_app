import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/dashboard/data/service_onboarding_provider.dart';
import 'package:mobile_flutter/features/dashboard/domain/service_onboarding.dart';
import 'package:mobile_flutter/features/dashboard/presentation/widgets/service_onboarding_banner.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  final selected = {'enabled': true, 'banking': true, 'exchange': true};
  List<ServiceOnboardingItem> remaining(Map<String, dynamic> progress,
          {bool banking = true,
          bool exchange = true,
          Map<String, dynamic>? preferences}) =>
      remainingServiceOnboarding(
          bankingEnabled: banking,
          exchangeEnabled: exchange,
          preferences: preferences ?? selected,
          progress: progress);

  test('company availability and registration selection both gate each service',
      () {
    for (final bankingEnabled in [false, true]) {
      for (final exchangeEnabled in [false, true]) {
        for (final bankingSelected in [false, true]) {
          for (final exchangeSelected in [false, true]) {
            final items = remaining({},
                banking: bankingEnabled,
                exchange: exchangeEnabled,
                preferences: {
                  'enabled': true,
                  'banking': bankingSelected,
                  'exchange': exchangeSelected,
                });
            expect(items.any((item) => item.name == 'Equals Money banking'),
                bankingEnabled && bankingSelected);
            expect(items.any((item) => item.name == 'ZBX exchange'),
                exchangeEnabled && exchangeSelected);
          }
        }
      }
    }
    expect(remaining({}, preferences: {'enabled': false}), isEmpty);
  });

  test('identity approval does not complete provider applications', () {
    final items = remaining({
      'status': 'approved',
      'equalsMoney': 'not_started',
      'boomFi': 'not_started',
      'submissionRequested': false
    });
    expect(items, hasLength(2));
    expect(items.every((item) => item.needsAction), isTrue);
  });

  test('completed providers disappear independently', () {
    expect(
        remaining({'equalsMoney': 'approved', 'boomFi': 'not_started'})
            .single
            .name,
        'ZBX exchange');
    expect(
        remaining({'equalsMoney': 'not_started', 'boomFi': 'accepted'})
            .single
            .name,
        'Equals Money banking');
    expect(
        remaining({'equalsMoney': 'approved', 'boomFi': 'approved'}), isEmpty);
  });

  test('submitted applications show review while invitations still need action',
      () {
    final items = remaining({
      'submissionRequested': true,
      'equalsMoney': 'invite_required',
      'boomFi': 'submitted'
    });
    expect(items.first.status, 'Accept your banking invite');
    expect(items.first.needsAction, isTrue);
    expect(items.last.status, 'Application under review');
    expect(items.last.needsAction, isFalse);
    expect(
        remaining({'submissionRequested': true}).every((i) => !i.needsAction),
        isTrue);
  });

  Future<(ProviderContainer, List<RequestOptions>)> container({
    bool enabled = true,
    bool banking = true,
    bool exchange = true,
    Map<String, dynamic>? preferences,
    Object? progress = const {},
    bool fail = false,
    bool bankingApproved = false,
    bool exchangeApproved = false,
    bool bankingReview = false,
    bool bankingAction = false,
    String? exchangeStatus,
  }) async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
        requests.add(r);
        if (fail && !r.path.endsWith('/preferences')) {
          h.reject(DioException(requestOptions: r));
        } else {
          h.resolve(Response(
              requestOptions: r,
              data: r.path.endsWith('/preferences')
                  ? preferences ?? selected
                  : progress));
        }
      }));
    final result = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(dio),
      kycDetailedStatusProvider.overrideWith((ref) async => KycDetailedStatus(
            hoppaStatus: 'approved',
            bankStatus: 'not_started',
            cardIssuerStatus: 'approved',
            nextAction: '',
            equalsMoneyApproved: bankingApproved,
            equalsMoneyApplicationId: bankingReview ? "pending" : null,
            equalsMoneyRequiredAction:
                bankingAction ? "ADDITIONAL_DOCUMENTS" : null,
          )),
      exchangeVerificationProvider.overrideWith((ref) async => {
            'hasProviderAccount': exchangeApproved,
            'provider': {
              'kycStatus': exchangeStatus ??
                  (exchangeApproved ? 'accepted' : 'not_started')
            },
          }),
      mobileTenantConfigProvider
          .overrideWith((ref) async => MobileTenantConfig.fromJson({
                'features': {
                  'unifiedCddOnboardingEnabled': enabled,
                  'equalsMoneyEnabled': banking,
                  'boomFiExchangeEnabled': exchange
                },
              })),
    ]);
    addTearDown(result.dispose);
    return (result, requests);
  }

  test('disabled services and unselected products avoid status requests',
      () async {
    for (final options in [
      (enabled: false, banking: true, exchange: true),
      (enabled: true, banking: false, exchange: false),
    ]) {
      final (ref, requests) = await container(
          enabled: options.enabled,
          banking: options.banking,
          exchange: options.exchange);
      expect(await ref.read(homeServiceOnboardingProvider.future), isEmpty);
      expect(requests, isEmpty);
    }
    final (ref, requests) = await container(
        preferences: {'enabled': true, 'banking': false, 'exchange': false});
    expect(await ref.read(homeServiceOnboardingProvider.future), isEmpty);
    expect(requests.single.path, endsWith('/preferences'));
  });

  test('Home reads status only and handles an application not yet started',
      () async {
    final (ref, requests) = await container(progress: null);
    expect(await ref.read(homeServiceOnboardingProvider.future), hasLength(2));
    expect(requests.map((r) => r.method), everyElement('GET'));
    expect(requests.map((r) => r.path).any((p) => p.endsWith('/session')),
        isFalse);
  });

  test('PascalCase provider status and selections are supported', () async {
    final (ref, _) = await container(preferences: {
      'Enabled': true,
      'Banking': true,
      'Exchange': true
    }, progress: {
      'SubmissionRequested': true,
      'EqualsMoney': 'approved',
      'BoomFi': 'submitted'
    });
    final items = await ref.read(homeServiceOnboardingProvider.future);
    expect(items.single.name, 'ZBX exchange');
    expect(items.single.needsAction, isFalse);
  });

  test('actual provider approval hides stale submitted onboarding records',
      () async {
    for (final bankingReady in [false, true]) {
      for (final exchangeReady in [false, true]) {
        final (ref, _) = await container(
            bankingApproved: bankingReady,
            exchangeApproved: exchangeReady,
            progress: {
              'submissionRequested': true,
              'equalsMoney': 'submitted',
              'boomFi': 'submitted'
            });
        final items = await ref.read(homeServiceOnboardingProvider.future);
        expect(
            items.any((i) => i.name == 'Equals Money banking'), !bankingReady);
        expect(items.any((i) => i.name == 'ZBX exchange'), !exchangeReady);
      }
    }
  });

  test(
      'current provider review and follow-up states override stale dispatch status',
      () async {
    final (ref, _) = await container(
        bankingReview: true,
        exchangeStatus: 'rejected',
        progress: {'equalsMoney': 'not_started', 'boomFi': 'submitted'});
    final items = await ref.read(homeServiceOnboardingProvider.future);
    expect(items.first.status, 'Application under review');
    expect(items.first.needsAction, isFalse);
    expect(items.last.status, 'Application needs attention');
    expect(items.last.needsAction, isTrue);
    final (actionRef, _) = await container(
        bankingAction: true,
        progress: {'equalsMoney': 'approved', 'boomFi': 'approved'});
    final action = await actionRef.read(homeServiceOnboardingProvider.future);
    expect(action.single.name, 'Equals Money banking');
    expect(action.single.needsAction, isTrue);
  });

  test('a new login invalidates status from the previous account', () async {
    final (ref, requests) = await container();
    final subscription = ref.listen(homeServiceOnboardingProvider, (_, __) {});
    addTearDown(subscription.close);
    await ref.read(homeServiceOnboardingProvider.future);
    ref.read(authSessionGenerationProvider.notifier).state++;
    await ref.read(homeServiceOnboardingProvider.future);
    expect(requests, hasLength(4));
  });

  for (final width in [320.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('reminder fits $width ${brightness.name} at larger text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ProviderScope(
            overrides: [
              homeServiceOnboardingProvider
                  .overrideWith((ref) async => remaining({})),
            ],
            child: MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: MediaQuery(
                    data: MediaQueryData(
                        size: Size(width, 700),
                        textScaler: const TextScaler.linear(1.3)),
                    child: const Scaffold(
                        body: SingleChildScrollView(
                            child: ServiceOnboardingBanner(
                                isBusinessAccount: false)))))));
        await tester.pumpAndSettle();
        expect(find.text('Equals Money banking'), findsOneWidget);
        expect(find.text('ZBX exchange'), findsOneWidget);
        expect(find.text('Continue setup'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('business accounts do not request personal signup preferences',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          homeServiceOnboardingProvider.overrideWith((ref) async {
            calls++;
            return remaining({});
          }),
        ],
        child: const MaterialApp(
            home: ServiceOnboardingBanner(isBusinessAccount: true))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Your service setup'), findsNothing);
  });

  testWidgets('an unreadable status does not label setup as incomplete',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          homeServiceOnboardingProvider
              .overrideWith((ref) async => throw StateError('Unavailable')),
        ],
        child: const MaterialApp(
            home: ServiceOnboardingBanner(isBusinessAccount: false))));
    await tester.pumpAndSettle();
    expect(find.text('Your service setup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'review offers status, and completing setup removes the reminder on return',
      (tester) async {
    var approved = false;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
              body: ServiceOnboardingBanner(isBusinessAccount: false))),
      GoRoute(
          path: '/kyc',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () {
                    approved = true;
                    context.pop();
                  },
                  child: const Text('Finish')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      homeServiceOnboardingProvider.overrideWith((ref) async => approved
          ? []
          : remaining({
              'submissionRequested': true,
              'boomFi': 'submitted',
              'equalsMoney': 'approved'
            })),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Check status'), findsOneWidget);
    expect(find.text('Continue setup'), findsNothing);
    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    expect(find.text('Finish'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Your service setup'), findsNothing);
  });
}

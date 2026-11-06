import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/cache/display_snapshot.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/dashboard/data/onboarding_notice_store.dart';
import 'package:mobile_flutter/features/dashboard/data/service_onboarding_provider.dart';
import 'package:mobile_flutter/features/dashboard/domain/service_onboarding.dart';
import 'package:mobile_flutter/features/dashboard/presentation/widgets/service_onboarding_banner.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

const selected = {
  'enabled': true,
  'cryptoCard': true,
  'banking': true,
  'exchange': true
};
List<ServiceOnboardingItem> statuses(Map<String, dynamic> progress,
        {Map<String, dynamic> preferences = selected,
        bool cards = true,
        bool banking = true,
        bool exchange = true}) =>
    remainingServiceOnboarding(
        cardsEnabled: cards,
        bankingEnabled: banking,
        exchangeEnabled: exchange,
        preferences: preferences,
        progress: progress);
const ready = KycDetailedStatus(
    hoppaStatus: 'approved',
    bankStatus: 'approved',
    cardIssuerStatus: 'approved',
    nextAction: '',
    interlaceApproved: true,
    interlaceStatus: 'approved',
    interlaceKycApproved: true,
    equalsMoneyApproved: true);
const pending = KycDetailedStatus(
    hoppaStatus: 'not_started',
    bankStatus: 'not_started',
    cardIssuerStatus: 'not_started',
    nextAction: '',
    interlaceStatus: 'not_started');
const exchangeReady = {
  'status': 'approved',
  'hasProviderAccount': true,
  'provider': {'kycStatus': 'accepted'}
};
final now = DateTime.utc(2026, 11, 6, 15);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Geist')
          ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf')))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only selected and enabled services appear, in onboarding order', () {
    for (final cards in [false, true]) {
      for (final banking in [false, true]) {
        for (final exchange in [false, true]) {
          final items =
              statuses({}, cards: cards, banking: banking, exchange: exchange);
          expect(items.map((i) => i.kind), [
            if (cards) OnboardingService.cryptoCards,
            if (banking) OnboardingService.banking,
            if (exchange) OnboardingService.exchange
          ]);
        }
      }
    }
    final unselected = statuses({}, preferences: {
      'enabled': true,
      'cryptoCard': false,
      'banking': false,
      'exchange': false
    });
    expect(unselected, isEmpty);
    expect(
        statuses({}, preferences: {'enabled': false, 'cryptoCard': true})
            .single
            .kind,
        OnboardingService
            .cryptoCards); // Crypto Cards are included at registration.
  });

  test(
      'later selected services stay Start and point to the first incomplete step',
      () {
    final items = statuses({
      'interlace': 'approved',
      'equalsMoney': 'invite_required',
      'boomFi': 'not_started',
      'submissionRequested': true
    });
    expect(items.map((i) => i.status), ['Complete', 'Need update', 'Start']);
    expect(items.last.blockedBy, OnboardingService.banking);
    expect(statuses({}).last.blockedBy, OnboardingService.cryptoCards);
    expect(
        statuses({}, preferences: {'enabled': true, 'exchange': true})
            .single
            .blockedBy,
        isNull);
    expect(
        statuses({
          'interlace': 'approved',
          'equalsMoney': 'approved',
          'boomFi': 'not_started'
        }).last.blockedBy,
        isNull);
  });

  for (final entry in {
    'not_started': OnboardingStage.start,
    'pending': OnboardingStage.inProgress,
    'submitted': OnboardingStage.inProgress,
    'dispatching': OnboardingStage.inProgress,
    'rejected': OnboardingStage.rejected,
    'failed': OnboardingStage.rejected,
    'resubmission_required': OnboardingStage.needUpdate,
    'action_required': OnboardingStage.needUpdate,
    'invite_required': OnboardingStage.needUpdate,
    'payment_required': OnboardingStage.needUpdate,
    'accepted': OnboardingStage.complete,
    'approved': OnboardingStage.complete,
    'unavailable': OnboardingStage.unavailable
  }.entries) {
    test('provider state ${entry.key} maps to ${entry.value.label}',
        () => expect(onboardingStage(entry.key), entry.value));
  }

  Future<(ProviderContainer, List<RequestOptions>)> fixture({
    String? owner = 'customer-a',
    bool banking = true,
    bool exchange = true,
    Map<String, dynamic> preferences = selected,
    Object? progress = const {},
    KycDetailedStatus detailed = pending,
    Map<String, dynamic>? verification,
    bool failDetailed = false,
    bool failExchange = false,
  }) async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
        requests.add(r);
        h.resolve(Response(
            requestOptions: r,
            data: r.path.endsWith('/preferences') ? preferences : progress));
      }));
    final container = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(dio),
      displayCacheOwnerProvider.overrideWithValue(owner),
      serviceOnboardingClockProvider.overrideWithValue(() => now),
      kycDetailedStatusProvider.overrideWith((ref) async {
        if (failDetailed) throw StateError('Unavailable');
        return detailed;
      }),
      exchangeVerificationProvider.overrideWith((ref) async {
        if (failExchange) throw StateError('Unavailable');
        return verification ?? {'status': 'not_started'};
      }),
      mobileTenantConfigProvider
          .overrideWith((ref) async => MobileTenantConfig.fromJson({
                'features': {
                  'unifiedCddOnboardingEnabled': true,
                  'equalsMoneyEnabled': banking,
                  'boomFiExchangeEnabled': exchange
                }
              })),
    ]);
    addTearDown(container.dispose);
    return (container, requests);
  }

  test('Home only reads statuses and never starts an application', () async {
    final (container, requests) = await fixture(progress: null);
    final items = await container.read(homeServiceOnboardingProvider.future);
    expect(items.map((i) => i.status), ['Start', 'Start', 'Start']);
    expect(requests.map((r) => r.method), everyElement('GET'));
    expect(requests.any((r) => r.path.contains('/session')), isFalse);
  });

  test('signed-out and unselected services do not request provider status',
      () async {
    final (signedOut, requests) = await fixture(owner: null);
    expect(await signedOut.read(homeServiceOnboardingProvider.future), isEmpty);
    expect(requests, isEmpty);
    final (disabled, disabledRequests) = await fixture(
        banking: false,
        exchange: false,
        preferences: {
          'enabled': true,
          'cryptoCard': false,
          'banking': true,
          'exchange': true
        });
    expect(await disabled.read(homeServiceOnboardingProvider.future), isEmpty);
    expect(disabledRequests.single.path, endsWith('/preferences'));
  });

  test('legacy customer retains enrolled Banking and Exchange reminders',
      () async {
    final (container, requests) = await fixture(preferences: {
      'enabled': false,
      'cryptoCard': true,
      'banking': false,
      'exchange': false
    }, detailed: ready, verification: exchangeReady);
    final items = await container.read(homeServiceOnboardingProvider.future);
    expect(items.map((i) => i.name), ['Crypto Cards', 'Banking', 'Exchange']);
    expect(items.map((i) => i.status), ['Complete', 'Complete', 'Complete']);
    expect(requests.map((r) => r.method), everyElement('GET'));
    expect(
        requests.any((r) => r.path == '/api/v1/mobile/onboarding/cdd'), false);
  });
  test('legacy customer with no enrollments only sees selected cards',
      () async {
    final (container, _) =
        await fixture(preferences: {'enabled': false, 'cryptoCard': true});
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.name),
        ['Crypto Cards']);
  });
  test('legacy enrollments respect company-disabled services', () async {
    final (container, _) = await fixture(
        banking: false,
        exchange: false,
        preferences: {'enabled': false, 'cryptoCard': true},
        detailed: ready,
        verification: exchangeReady);
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.name),
        ['Crypto Cards']);
  });
  test('explicit choices do not infer an unselected provider', () async {
    final (container, _) = await fixture(preferences: {
      'enabled': true,
      'cryptoCard': true,
      'banking': false,
      'exchange': false
    }, detailed: ready, verification: exchangeReady);
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.name),
        ['Crypto Cards']);
  });

  test('provider approval wins over stale submitted dispatch records',
      () async {
    final (container, _) = await fixture(
        detailed: ready,
        verification: exchangeReady,
        progress: {
          'interlace': 'submitted',
          'equalsMoney': 'submitted',
          'boomFi': 'submitted'
        });
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.status),
        ['Complete', 'Complete', 'Complete']);
  });

  test('Interlace and Equals follow-up requests override earlier approval',
      () async {
    final (container, _) = await fixture(
        detailed: const KycDetailedStatus(
            hoppaStatus: 'approved',
            bankStatus: 'approved',
            cardIssuerStatus: 'approved',
            nextAction: '',
            interlaceRequiredAction: 'RESUBMIT_DOCUMENTS',
            equalsMoneyApproved: true,
            equalsMoneyRequiredAction: 'ADDITIONAL_DOCUMENTS'),
        verification: exchangeReady,
        progress: {
          'interlace': 'approved',
          'equalsMoney': 'approved',
          'boomFi': 'approved'
        });
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.status),
        ['Need update', 'Need update', 'Complete']);
  });

  test('an explicit negative Interlace approval cannot display Complete',
      () async {
    final (container, _) = await fixture(
        detailed: const KycDetailedStatus(
            hoppaStatus: 'approved',
            bankStatus: 'not_started',
            cardIssuerStatus: 'approved',
            nextAction: '',
            interlaceApproved: false));
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .first
            .status,
        'In progress');
  });

  for (final action in [
    'tin_required',
    'edd_required',
    'cdd_required',
    'kyc_required'
  ]) {
    test('Exchange $action is Need update, not Complete', () async {
      final (container, _) = await fixture(detailed: ready, verification: {
        ...exchangeReady,
        'provider': {'kycStatus': 'accepted', 'nextAction': action}
      });
      expect(
          (await container.read(homeServiceOnboardingProvider.future))
              .last
              .status,
          'Need update');
    });
  }

  test('submitted Exchange follow-up is In progress', () async {
    final (container, _) = await fixture(detailed: ready, verification: {
      ...exchangeReady,
      'provider': {
        'kycStatus': 'accepted',
        'nextAction': 'edd_required',
        'actionSubmitted': true
      }
    });
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .last
            .status,
        'In progress');
  });

  for (final current in ['rejected', 'pending']) {
    test('current Interlace $current overrides a stale issuer approval flag',
        () async {
      final (container, _) = await fixture(
          detailed: KycDetailedStatus.fromJson({
        'CardIssuerKycApproved': true,
        'Interlace': {'Status': current, 'Approved': current == 'pending'},
      }));
      expect(
          (await container.read(homeServiceOnboardingProvider.future))
              .first
              .status,
          current == 'rejected' ? 'Rejected' : 'In progress');
    });
  }
  test(
      'negative Equals approval does not become Complete from stale status text',
      () async {
    final (container, _) = await fixture(
        detailed: const KycDetailedStatus(
            hoppaStatus: 'approved',
            bankStatus: 'approved',
            cardIssuerStatus: 'approved',
            nextAction: '',
            equalsMoneyApproved: false,
            equalsMoneyStatus: 'approved'));
    expect(
        (await container.read(homeServiceOnboardingProvider.future))[1].status,
        'In progress');
  });
  test('current Equals approval wins over an earlier rejected application',
      () async {
    final (container, _) = await fixture(
        detailed: const KycDetailedStatus(
            hoppaStatus: 'approved',
            bankStatus: 'approved',
            cardIssuerStatus: 'approved',
            nextAction: '',
            equalsMoneyApproved: true,
            equalsMoneyStatus: 'approved',
            equalsMoneyApplicationStatus: 'rejected'));
    expect(
        (await container.read(homeServiceOnboardingProvider.future))[1].status,
        'Complete');
  });
  test(
      'terminal Exchange rejection remains Rejected with an old action reference',
      () async {
    final (container, _) = await fixture(verification: {
      'provider': {'kycStatus': 'rejected', 'nextAction': 'edd_required'}
    });
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .last
            .status,
        'Rejected');
  });
  test('provider rejection remains separate from a request for updates',
      () async {
    final (container, _) = await fixture(
        detailed: const KycDetailedStatus(
            hoppaStatus: 'approved',
            bankStatus: 'rejected',
            cardIssuerStatus: 'rejected',
            nextAction: '',
            equalsMoneyStatus: 'rejected'),
        verification: {
          'provider': {'kycStatus': 'rejected'}
        });
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.status),
        ['Rejected', 'Rejected', 'Rejected']);
  });

  test('a shared staging organization is not a completed customer application',
      () async {
    final (container, _) = await fixture(detailed: ready, verification: {
      ...exchangeReady,
      'usesSharedStagingOrganization': true
    });
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .last
            .status,
        'Check status');
  });
  test('one failed provider read does not hide the other provider reminders',
      () async {
    final (container, _) = await fixture(detailed: ready, failExchange: true);
    expect(
        (await container.read(homeServiceOnboardingProvider.future))
            .map((i) => i.status),
        ['Complete', 'Complete', 'Check status']);
  });

  test('a new session refreshes the account-bound reads', () async {
    final (container, requests) = await fixture();
    final subscription =
        container.listen(homeServiceOnboardingProvider, (_, __) {});
    addTearDown(subscription.close);
    await container.read(homeServiceOnboardingProvider.future);
    container.read(authSessionGenerationProvider.notifier).state++;
    await container.read(homeServiceOnboardingProvider.future);
    expect(
        requests.where((r) => r.path.endsWith('/preferences')), hasLength(2));
  });

  Future<OnboardingNoticeStore> store([String owner = 'customer-a']) async =>
      OnboardingNoticeStore(await SharedPreferences.getInstance(), owner);
  final allComplete = statuses({
    'interlace': 'approved',
    'equalsMoney': 'approved',
    'boomFi': 'approved'
  });

  test(
      'Complete is visible until clicked, and acknowledgement survives a reload',
      () async {
    final s = await store();
    expect(await s.visible(allComplete, now), hasLength(3));
    await s.acknowledge(OnboardingService.banking);
    final reloaded = await store();
    expect((await reloaded.visible(allComplete, now)).map((i) => i.kind),
        [OnboardingService.cryptoCards, OnboardingService.exchange]);
  });

  test('Complete hides after 24 hours, including if Home was closed', () async {
    final s = await store();
    expect(await s.visible(allComplete, now), hasLength(3));
    expect(
        await s.visible(
            allComplete, now.add(const Duration(hours: 23, minutes: 59))),
        hasLength(3));
    expect(
        await (await store())
            .visible(allComplete, now.add(const Duration(hours: 24))),
        isEmpty);
  });

  test('provider completion timestamp is used when available', () async {
    final items = statuses({
      'interlace': 'complete',
      'interlaceCompletedAt':
          now.subtract(const Duration(days: 2)).toIso8601String()
    }, banking: false, exchange: false);
    expect(await (await store()).visible(items, now), isEmpty);
  });

  test(
      'new provider action reopens a dismissed Complete and starts a new completion window',
      () async {
    final s = await store();
    await s.visible(allComplete, now);
    await s.acknowledge(OnboardingService.cryptoCards);
    final updates = statuses({
      'interlace': 'action_required',
      'equalsMoney': 'approved',
      'boomFi': 'approved'
    });
    expect(
        (await s.visible(updates, now.add(const Duration(days: 2))))
            .single
            .status,
        'Need update');
    expect(
        (await s.visible(allComplete, now.add(const Duration(days: 3))))
            .single
            .kind,
        OnboardingService.cryptoCards);
  });

  test(
      'an unavailable status neither resets nor discards completion acknowledgement',
      () async {
    final s = await store();
    await s.visible(allComplete, now);
    await s.acknowledge(OnboardingService.exchange);
    final unavailable = await s.visible(
        statuses({
          'interlace': 'approved',
          'equalsMoney': 'approved',
          'boomFi': 'unavailable'
        }),
        now);
    expect(
        unavailable.any((i) => i.kind == OnboardingService.exchange), isFalse);
    expect(
        (await s.visible(allComplete, now))
            .any((i) => i.kind == OnboardingService.exchange),
        isFalse);
  });

  test('a click while incomplete cannot dismiss a future completion', () async {
    final s = await store();
    await s.visible(statuses({}), now);
    await s.acknowledge(OnboardingService.cryptoCards);
    expect(await s.visible(allComplete, now), hasLength(3));
  });

  test('acknowledgements are isolated between users and installations',
      () async {
    final a = await store('installation-a:user-a');
    await a.visible(allComplete, now);
    await a.acknowledge(OnboardingService.cryptoCards);
    expect(
        await (await store('installation-a:user-b')).visible(allComplete, now),
        hasLength(3));
    expect(
        await (await store('installation-b:user-a')).visible(allComplete, now),
        hasLength(3));
  });

  final sample = statuses({
    'interlace': 'approved',
    'equalsMoney': 'action_required',
    'boomFi': 'not_started'
  });
  Future<void> mount(WidgetTester tester,
      {double width = 320,
      double scale = 1.5,
      Brightness brightness = Brightness.dark,
      bool business = false,
      List<ServiceOnboardingItem>? items,
      bool fail = false}) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          homeServiceOnboardingProvider.overrideWith((ref) async {
            if (fail) throw StateError('Unavailable');
            return items ?? sample;
          }),
        ],
        child: MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'Geist'),
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 800),
                    textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                    body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ServiceOnboardingBanner(
                            isBusinessAccount: business)))))));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 760.0, 1470.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('status buttons fit $width ${brightness.name}',
          (tester) async {
        await mount(tester, width: width, brightness: brightness);
        for (final label in [
          'Crypto Cards',
          'Banking',
          'Exchange',
          'Complete',
          'Need update',
          'Start'
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('all labels remain readable on a phone at 200 percent text',
      (tester) async {
    await mount(tester, scale: 2);
    expect(find.text('Crypto Cards'), findsOneWidget);
    expect(find.text('Need update'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('business and unselected services are hidden', (tester) async {
    await mount(tester, business: true);
    expect(find.text('Crypto Cards'), findsNothing);
    await mount(tester, items: []);
    expect(find.text('Banking'), findsNothing);
  });
  testWidgets('old owner statuses are not exposed while switching accounts',
      (tester) async {
    await mount(tester,
        items: sample.map((i) => i.forOwner('previous-user')).toList());
    expect(find.text('Crypto Cards'), findsNothing);
  });
  testWidgets('unreadable selections do not invent Start reminders',
      (tester) async {
    await mount(tester, fail: true);
    expect(find.text('Start'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'later Start opens the earlier required step and refreshes after return',
      (tester) async {
    var reads = 0;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
              body: ServiceOnboardingBanner(isBusinessAccount: false))),
      GoRoute(
          path: '/onboarding/banking',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Banking step')))),
      GoRoute(
          path: '/onboarding/exchange',
          builder: (_, __) => const Scaffold(body: Text('Exchange step'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      homeServiceOnboardingProvider.overrideWith((ref) async {
        reads++;
        return sample;
      }),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-exchange')));
    await tester.pumpAndSettle();
    expect(find.text('Banking step'), findsOneWidget);
    expect(find.text('Exchange step'), findsNothing);
    await tester.tap(find.text('Banking step'));
    await tester.pumpAndSettle();
    expect(reads, greaterThan(1));
  });
  testWidgets(
      'clicking Complete acknowledges that service and opens its status page',
      (tester) async {
    const owner = 'customer-a';
    final s = await store(owner);
    final items = allComplete.map((i) => i.forOwner(owner)).toList();
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
              body: ServiceOnboardingBanner(isBusinessAccount: false))),
      GoRoute(
          path: '/kyc/status',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Close status')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      displayCacheOwnerProvider.overrideWithValue(owner),
      onboardingNoticeStoreProvider.overrideWith((ref) async => s),
      homeServiceOnboardingProvider
          .overrideWith((ref) async => s.visible(items, now)),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-cryptoCards')));
    await tester.pumpAndSettle();
    expect(find.text('Close status'), findsOneWidget);
    await tester.tap(find.text('Close status'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-cryptoCards')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-banking')), findsOneWidget);
  });
}

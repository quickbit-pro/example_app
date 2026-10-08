import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/cache/display_snapshot.dart';
import 'package:mobile_flutter/core/cache/display_snapshot_codecs.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/dashboard/data/dashboard_display_provider.dart';
import 'package:mobile_flutter/features/dashboard/data/dashboard_providers.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/transactions/application/activity_display_provider.dart';

String token(String user, {String tenant = 'tenant', int expiry = 1}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
          'sub': user,
          'company_installation_id': tenant,
          'exp': expiry,
        })))}.signature';

LedgerTransaction transaction(String id) => LedgerTransaction(
      id: id,
      title: 'Coffee',
      subtitle: 'Completed',
      amount: const Money(
          currency: 'BTC', minorUnits: 0, decimalAmount: -0.000012345),
      bookedAt: DateTime.utc(2026, 9, 17),
      type: TransactionType.card,
      accountId: 'account',
      cardId: 'card',
      budgetId: 'budget',
      status: 'completed',
      hasBookedAt: false,
      isPrimary: false,
      metadata: const {'network': 'BTC'},
    );

HoppaDashboardSnapshot home(String name) => HoppaDashboardSnapshot(
      customerName: name,
      accounts: const [],
      holdings: const [],
      activities: [
        HoppaActivity(
          id: 'tx',
          title: 'Coffee',
          subtitle: '',
          amount: -1,
          currency: 'USD',
          kind: HoppaActivityKind.card,
          timeLabel: '',
          statusLabel: 'completed',
          transaction: transaction('tx').withCardFees([transaction('fee')]),
        )
      ],
      cards: [
        PaymentCard.fromJson({
          'id': 'card',
          'balance': 12.34,
          'currency': 'USD',
          'last4': '4321',
          'status': 'active'
        })
      ],
      onboardingProgress: 1,
      marketSentiment: '',
      requiresKyc: false,
      accountReady: true,
      exchangeEnabled: true,
      outflowsEnabled: true,
      referralsEnabled: false,
      vouchersEnabled: false,
      isBusinessAccount: false,
      portfolioEstimate: PortfolioEstimate.fromJson({
        'total': 42,
        'valuationRates': [
          {'currency': 'EUR', 'rate': 1.1}
        ]
      }),
    );

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('owner survives token rotation, isolates users, tenants and APIs', () {
    final owner = displayCacheOwner(token('a'), 'api');
    expect(owner, displayCacheOwner(token('a', expiry: 2), 'api'));
    expect(owner, isNot(displayCacheOwner(token('b'), 'api')));
    expect(owner, isNot(displayCacheOwner(token('a', tenant: 'b'), 'api')));
    expect(owner, isNot(displayCacheOwner(token('a'), 'other-api')));
    expect(displayCacheOwner('invalid', 'api'), isNull);
    expect(displayCacheOwner(null, 'api'), isNull);
  });

  test('Home restores before API completes, then replaces and persists data',
      () async {
    final storage = DisplaySnapshotStorage();
    await storage.write(
        'owner',
        'home',
        {
          'savedAt': DateTime.now().toIso8601String(),
          'data': encodeHoppaDashboardSnapshot(home('Saved customer')),
        },
        isCurrent: () => true);
    final fresh = Completer<HoppaDashboardSnapshot>();
    var requests = 0;
    final container = ProviderContainer(overrides: [
      displayCacheOwnerProvider.overrideWithValue('owner'),
      displaySnapshotStorageProvider.overrideWithValue(storage),
      hoppaDashboardProvider.overrideWith((ref) {
        requests++;
        return fresh.future;
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(dashboardDisplayProvider, (_, __) {});
    await flush();
    var view = container.read(dashboardDisplayProvider);
    expect(requests, 1);
    expect(view.value.requireValue.customerName, 'Saved customer');
    expect(view.isSaved, isTrue);
    expect(view.isRefreshing, isTrue);
    fresh.complete(home('Fresh customer'));
    await flush();
    view = container.read(dashboardDisplayProvider);
    expect(view.value.requireValue.customerName, 'Fresh customer');
    expect(view.isSaved, isFalse);
    expect(view.isRefreshing, isFalse);
    expect((await storage.read('owner', 'home'))!['data']['customerName'],
        'Fresh customer');
  });

  test(
      'Activity keeps saved rows on failure; successful empty refresh clears them',
      () async {
    final storage = DisplaySnapshotStorage();
    const scope = (accountId: '', cardId: '');
    await storage.write(
        'owner',
        'activity::',
        {
          'savedAt': DateTime.now().toIso8601String(),
          'data': encodeActivity([transaction('saved')]),
        },
        isCurrent: () => true);
    var request = Completer<List<LedgerTransaction>>();
    final container = ProviderContainer(overrides: [
      displayCacheOwnerProvider.overrideWithValue('owner'),
      displaySnapshotStorageProvider.overrideWithValue(storage),
      activityTransactionsProvider.overrideWith((ref) => request.future),
    ]);
    addTearDown(container.dispose);
    container.listen(activityDisplayProvider(scope), (_, __) {});
    await flush();
    request.completeError(StateError('offline'));
    await flush();
    var view = container.read(activityDisplayProvider(scope));
    expect(view.value.requireValue.single.id, 'saved');
    expect(view.refreshError, isA<StateError>());
    expect(view.isSaved, isTrue);
    expect(view.isRefreshing, isFalse);
    request = Completer<List<LedgerTransaction>>();
    container.invalidate(activityTransactionsProvider);
    await flush();
    expect(container.read(activityDisplayProvider(scope)).isRefreshing, isTrue);
    request.complete([]);
    await flush();
    view = container.read(activityDisplayProvider(scope));
    expect(view.value.requireValue, isEmpty);
    expect(view.isSaved, isFalse);
    expect(view.refreshError, isNull);
    expect(decodeActivity((await storage.read('owner', 'activity::'))!['data']),
        isEmpty);
  });

  test('account and card scopes never borrow the all-activity cache', () async {
    final storage = DisplaySnapshotStorage();
    await storage.write(
        'owner',
        'activity::',
        {
          'savedAt': DateTime.now().toIso8601String(),
          'data': encodeActivity([transaction('all')]),
        },
        isCurrent: () => true);
    final container = ProviderContainer(overrides: [
      displayCacheOwnerProvider.overrideWithValue('owner'),
      displaySnapshotStorageProvider.overrideWithValue(storage),
      activityAccountTransactionsProvider
          .overrideWith((ref, id) async => [transaction(id)]),
      activityCardTransactionsProvider
          .overrideWith((ref, id) async => [transaction(id)]),
    ]);
    addTearDown(container.dispose);
    final account =
        activityDisplayProvider((accountId: 'account-2', cardId: ''));
    final card = activityDisplayProvider((accountId: '', cardId: 'card-2'));
    container.listen(account, (_, __) {});
    container.listen(card, (_, __) {});
    await flush();
    expect(container.read(account).value.requireValue.single.id, 'account-2');
    expect(container.read(card).value.requireValue.single.id, 'card-2');
  });

  test('session boundary discards in-memory data and old in-flight completion',
      () async {
    var nextRequest = Completer<HoppaDashboardSnapshot>();
    final container = ProviderContainer(overrides: [
      authTokenProvider.overrideWith((ref) => token('a')),
      hoppaDashboardProvider.overrideWith((ref) {
        ref.watch(authSessionGenerationProvider);
        return nextRequest.future;
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(dashboardDisplayProvider, (_, __) {});
    nextRequest.complete(home('A'));
    await flush();
    expect(
        container
            .read(dashboardDisplayProvider)
            .value
            .requireValue
            .customerName,
        'A');
    nextRequest = Completer<HoppaDashboardSnapshot>();
    container.invalidate(hoppaDashboardProvider);
    await flush();
    final previousRequest = nextRequest;
    nextRequest = Completer<HoppaDashboardSnapshot>();
    container.read(authTokenProvider.notifier).state = token('b');
    container.read(authSessionGenerationProvider.notifier).state++;
    await flush();
    expect(container.read(dashboardDisplayProvider).value.hasValue, isFalse);
    previousRequest.complete(home('Late A'));
    await flush();
    expect(container.read(dashboardDisplayProvider).value.hasValue, isFalse);
    nextRequest.complete(home('B'));
    await flush();
    expect(
        container
            .read(dashboardDisplayProvider)
            .value
            .requireValue
            .customerName,
        'B');
  });

  test('entry refresh shares initial Home and Activity requests', () async {
    var homeCalls = 0;
    var activityCalls = 0;
    final homeRequest = Completer<HoppaDashboardSnapshot>();
    final activityRequest = Completer<List<LedgerTransaction>>();
    final container = ProviderContainer(overrides: [
      hoppaDashboardProvider.overrideWith((ref) {
        homeCalls++;
        return homeRequest.future;
      }),
      activityTransactionsProvider.overrideWith((ref) {
        activityCalls++;
        return activityRequest.future;
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(hoppaDashboardProvider, (_, __) {});
    container.listen(activityTransactionsProvider, (_, __) {});
    final refreshHome = container.read(refreshHoppaDashboardProvider)();
    final refreshActivity = container.read(refreshActivityProvider)();
    expect(homeCalls, 1);
    expect(activityCalls, 1);
    homeRequest.complete(home('Customer'));
    activityRequest.complete([]);
    await Future.wait([refreshHome, refreshActivity]);
    expect(homeCalls, 1);
    expect(activityCalls, 1);
  });

  test('expired session clears display even before generation advances',
      () async {
    var request = Completer<HoppaDashboardSnapshot>();
    final container = ProviderContainer(overrides: [
      authTokenProvider.overrideWith((ref) => token('a')),
      hoppaDashboardProvider.overrideWith((ref) => request.future),
    ]);
    addTearDown(container.dispose);
    container.listen(dashboardDisplayProvider, (_, __) {});
    request.complete(home('A'));
    await flush();
    request = Completer<HoppaDashboardSnapshot>();
    container.invalidate(hoppaDashboardProvider);
    await flush();
    container.read(authTokenProvider.notifier).state = null;
    request.complete(home('Late A'));
    await flush();
    expect(container.read(dashboardDisplayProvider).value.hasValue, isFalse);
    final storage = container.read(displaySnapshotStorageProvider);
    final owner = container.read(displayCacheOwnerProvider)!;
    expect(await storage.read(owner, 'home'), isNull);
  });

  test('cache miss preserves first-load and first-load error states', () async {
    final controller = DisplaySnapshotController<int>(
        storage: DisplaySnapshotStorage(),
        owner: 'owner',
        name: 'absent',
        encode: (v) => {'v': v},
        decode: (j) => j['v'] as int);
    addTearDown(controller.dispose);
    await flush();
    expect(controller.state.value.isLoading, isTrue);
    controller.update(AsyncError(StateError('offline'), StackTrace.current));
    expect(controller.state.value.hasError, isTrue);
    expect(controller.state.isSaved, isFalse);
  });

  test('late disk hydration cannot overwrite a faster API response', () async {
    final storage = _DelayedStorage();
    final controller = DisplaySnapshotController<int>(
        storage: storage,
        owner: 'owner',
        name: 'home',
        encode: (v) => {'v': v},
        decode: (j) => j['v'] as int);
    addTearDown(controller.dispose);
    controller.update(const AsyncData(2));
    storage.readResult.complete({
      'savedAt': DateTime.now().toIso8601String(),
      'data': {'v': 1}
    });
    await flush();
    expect(controller.state.value.requireValue, 2);
    expect(controller.state.isSaved, isFalse);
  });

  test('expired, corrupt and other-owner snapshots are cache misses', () async {
    final storage = DisplaySnapshotStorage();
    await storage.write(
        'a',
        'home',
        {
          'savedAt': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
          'data': {'v': 1}
        },
        isCurrent: () => true);
    expect(await storage.read('a', 'home'), isNull);
    expect(await storage.read('b', 'home'), isNull);
    FlutterSecureStorage.setMockInitialValues(
        {DisplaySnapshotStorage.key: 'corrupt'});
    expect(await storage.read('a', 'home'), isNull);
    await storage.write(
        'a',
        'home',
        {
          'savedAt': DateTime.now().toIso8601String(),
          'data': {'v': 2}
        },
        isCurrent: () => true);
    expect((await storage.read('a', 'home'))!['data']['v'], 2);
  });

  test('logout clears storage after queued writes', () async {
    final container = ProviderContainer(
        overrides: [authTokenProvider.overrideWith((ref) => token('a'))]);
    addTearDown(container.dispose);
    final storage = container.read(displaySnapshotStorageProvider);
    final write = storage.write(
        'a',
        'home',
        {
          'savedAt': DateTime.now().toIso8601String(),
          'data': {'v': 1}
        },
        isCurrent: () => true);
    container.read(authTokenProvider.notifier).state = null;
    await write;
    expect(await storage.read('a', 'home'), isNull);
  });

  test('serialized Home preserves precision, fees, dates, cards and valuation',
      () {
    final original = home('Customer');
    final encoded = encodeHoppaDashboardSnapshot(original);
    final restored =
        decodeHoppaDashboardSnapshot(jsonDecode(jsonEncode(encoded)));
    final tx = restored.activities.single.transaction!;
    expect(tx.amount.decimalAmount, -0.000012345);
    expect(tx.cardFees.single.id, 'fee');
    expect(tx.hasBookedAt, isFalse);
    expect(tx.isPrimary, isFalse);
    expect(tx.accountId, 'account');
    expect(tx.cardId, 'card');
    expect(tx.metadata, {'network': 'BTC'});
    expect(restored.cards.single.balance.decimalAmount, 12.34);
    expect(restored.portfolioEstimate!.valuationRates, {'EUR': 1.1});
    expect(encodeHoppaDashboardSnapshot(restored), encoded);
  });
}

class _DelayedStorage extends DisplaySnapshotStorage {
  final readResult = Completer<Map<String, dynamic>?>();
  @override
  Future<Map<String, dynamic>?> read(String owner, String name) =>
      readResult.future;
  @override
  Future<void> write(String owner, String name, Map<String, dynamic> entry,
      {required bool Function() isCurrent}) async {}
}

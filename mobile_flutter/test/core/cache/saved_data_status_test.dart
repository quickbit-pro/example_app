import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/cache/display_snapshot.dart';
import 'package:mobile_flutter/core/cache/display_snapshot_codecs.dart';
import 'package:mobile_flutter/core/cache/saved_data_status.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/transactions/application/activity_display_provider.dart';

void main() {
  testWidgets('cached content stays mounted through refresh, failure and retry',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = DisplaySnapshotStorage();
    final saved = LedgerTransaction.fromJson({
      'id': 'saved',
      'title': 'Saved payment',
      'amount': -12,
      'currency': 'USD',
      'type': 'card',
    });
    await storage.write(
        'owner',
        'activity::',
        {
          'savedAt': DateTime.now().toIso8601String(),
          'data': encodeActivity([saved]),
        },
        isCurrent: () => true);
    var request = Completer<List<LedgerTransaction>>();
    final container = ProviderContainer(overrides: [
      displayCacheOwnerProvider.overrideWithValue('owner'),
      displaySnapshotStorageProvider.overrideWithValue(storage),
      activityTransactionsProvider.overrideWith((ref) => request.future),
    ]);
    addTearDown(container.dispose);
    const pageKey = ValueKey('page');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Consumer(builder: (context, ref, _) {
          final snapshot =
              ref.watch(activityDisplayProvider((accountId: '', cardId: '')));
          return SavedDataStatus(
            snapshot: snapshot,
            onRetry: () async {
              ref.invalidate(activityTransactionsProvider);
              await ref.read(activityTransactionsProvider.future);
            },
            child: Scaffold(
              key: pageKey,
              body: Text(
                  snapshot.value.valueOrNull?.map((t) => t.title).join() ??
                      'Loading'),
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Saved payment'), findsOneWidget);
    expect(find.text('Updating saved data…'), findsOneWidget);
    expect(find.text('Loading'), findsNothing);
    final page = tester.element(find.byKey(pageKey));
    request.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Saved payment'), findsOneWidget);
    expect(find.text('Could not update. Showing saved data.'), findsOneWidget);
    expect(tester.element(find.byKey(pageKey)), same(page));
    request = Completer<List<LedgerTransaction>>();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Updating saved data…'), findsOneWidget);
    request.complete([
      LedgerTransaction.fromJson({
        'id': 'fresh',
        'title': 'Fresh payment',
        'amount': -13,
        'currency': 'USD',
        'type': 'card',
      })
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Fresh payment'), findsOneWidget);
    expect(find.text('Saved payment'), findsNothing);
    expect(find.text('Updating saved data…'), findsNothing);
    expect(tester.element(find.byKey(pageKey)), same(page));
    expect(tester.takeException(), isNull);
  });
}

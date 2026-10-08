import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/transactions/application/activity_account_options_provider.dart';
import 'package:mobile_flutter/features/transactions/domain/activity_account_option.dart';
import 'package:mobile_flutter/features/transactions/presentation/activity_account_dropdown.dart';

void main() {
  for (final width in [320.0, 393.0, 1440.0]) {
    testWidgets('account menu expands beyond a narrow button at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final option = ActivityAccountOption(
        key: 'budget:real-euro:EUR',
        label: 'Business travel and expenses account · EUR · BE***1234',
        scopeIds: ['real-euro'],
        currency: 'EUR',
        maskedIdentifier: 'BE***1234',
      );
      ActivityAccountOption? chosen;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            activityAccountOptionsProvider
                .overrideWith((ref) => ActivityAccountOptionsState(
                      options: [option],
                      isLoading: false,
                      errors: const [],
                      retry: () {},
                    )),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 150, right: 16),
              child: SizedBox(
                  width: 140,
                  child: ActivityAccountDropdown(
                    selected: null,
                    onChanged: (value) => chosen = value,
                  )),
            ),
          )))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activity-account-dropdown')));
      await tester.pumpAndSettle();
      final label = find.text(option.label).last;
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, greaterThan(200));
      final bounds = tester.getRect(label);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(width));
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(chosen?.key, option.key);
      expect(tester.takeException(), isNull);
    });
  }

  test('provider preserves a successful roster while another source fails',
      () async {
    final container = ProviderContainer(overrides: [
      accountsProvider.overrideWith((ref) async => [
            AccountBalance.fromJson({
              'id': 'local',
              'name': 'Local',
              'balance': {'currency': 'USD', 'minorUnits': 0}
            })
          ]),
      budgetsProvider
          .overrideWith((ref) async => throw StateError('unavailable')),
    ]);
    addTearDown(container.dispose);
    container.read(activityAccountOptionsProvider);
    await container.read(accountsProvider.future);
    try {
      await container.read(budgetsProvider.future);
    } catch (_) {}
    final state = container.read(activityAccountOptionsProvider);
    expect(state.options.single.key, 'account:local:USD');
    expect(state.errors, ['Bank accounts']);
    expect(state.isLoading, isFalse);
  });

  test(
      'provider combines bank budgets and local accounts without receiving matches',
      () async {
    final container = ProviderContainer(overrides: [
      accountsProvider.overrideWith((ref) async => [
            AccountBalance.fromJson({
              'id': 'local',
              'balance': {'currency': 'USD', 'minorUnits': 0}
            })
          ]),
      budgetsProvider.overrideWith((ref) async => [
            PlatformResource.fromJson({
              'id': 'budget',
              'balances': [
                {'currency': 'EUR', 'amount': 0},
                {'currency': 'RON', 'amount': 0},
              ],
            })
          ]),
      equalsBankingInfoProvider.overrideWith((ref) async => []),
    ]);
    addTearDown(container.dispose);
    container.read(activityAccountOptionsProvider);
    await container.read(accountsProvider.future);
    await container.read(budgetsProvider.future);
    container.read(activityAccountOptionsProvider);
    await container.read(equalsBankingInfoProvider.future);
    expect(
        container
            .read(activityAccountOptionsProvider)
            .options
            .map((option) => option.key),
        containsAll(
            ['account:local:USD', 'budget:budget:EUR', 'budget:budget:RON']));
  });

  testWidgets(
      'All accounts is available while rosters load and selection persists',
      (tester) async {
    final waiting = Completer<List<AccountBalance>>();
    final selected = ActivityAccountOption(
        key: 'budget:previous:EUR',
        label: 'Previous · EUR · BE***1234',
        scopeIds: ['previous'],
        currency: 'EUR');
    ActivityAccountOption? result = selected;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          accountsProvider.overrideWith((ref) => waiting.future),
          budgetsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Padding(
          padding: const EdgeInsets.all(20),
          child: ActivityAccountDropdown(
              selected: selected, onChanged: (value) => result = value),
        )))));
    await tester.pump();
    expect(find.text(selected.label), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-account-dropdown')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('All accounts'), findsOneWidget);
    await tester.tap(find.text('All accounts'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(result, isNull);
    waiting.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty rosters keep the All accounts control visible',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          accountsProvider.overrideWith((ref) async => []),
          budgetsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Padding(
          padding: const EdgeInsets.all(20),
          child: ActivityAccountDropdown(selected: null, onChanged: (_) {}),
        )))));
    await tester.pumpAndSettle();
    expect(find.text('All accounts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

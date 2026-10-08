import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/cards/presentation/order_card_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';

import 'order_card_discount_test.dart' show tier;

KycDetailedStatus status(String value, {bool? approved, String? action}) =>
    KycDetailedStatus.fromJson({
      'hoppaCardKycApproved': true,
      'cardIssuerKycApproved': approved,
      'interlace': {
        'status': value,
        'approved': approved,
        'requiredAction': action,
      },
      'equalsMoney': {'approved': true, 'accountId': 'existing-account'},
    });

class RecordingApi extends MobileBankingApi {
  RecordingApi() : super(Dio());
  int orders = 0;
  @override
  Future<void> orderCard({
    required String label,
    required bool virtual,
    String currency = 'USD',
    int? cardTypeId,
    String? productCode,
    String? phoneCode,
    String? phone,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? budgetId,
    String? discountCode,
    Map<String, dynamic>? legalAgreements,
  }) async {
    orders++;
  }
}

void main() {
  for (final value in ['submitted', 'pending', 'rejected', 'not_started', '']) {
    test('identity and bank approval do not unlock $value issuer status', () {
      expect(status(value, approved: false).interlaceKycApproved, isFalse);
    });
  }
  test(
      'only issuer approval unlocks orders; conflicting flags and actions block',
      () {
    expect(status('approved', approved: true).interlaceKycApproved, isTrue);
    expect(status('approved', approved: false).interlaceKycApproved, isFalse);
    expect(
        status('approved', approved: true, action: 'RESUBMIT_DOCUMENTS')
            .interlaceKycApproved,
        isFalse);
    expect(
        KycDetailedStatus.fromJson({'hoppaCardKycApproved': true})
            .interlaceKycApproved,
        isFalse);
  });
  test('dashboard requires the explicit issuer flag even with bank onboarding',
      () {
    for (final approved in [false, true]) {
      final snapshot = DashboardSnapshot(
        profile: UserProfile.fromJson({
          'kycStatus': 'approved',
          'onboardingStatus': 'completed',
          'interlaceKycApproved': approved
        }),
        accounts: const [],
        cards: const [],
        transactions: const [],
        onboarding: const [],
      );
      expect(snapshot.canUseBanking, isTrue);
      expect(snapshot.canOrderCard, approved);
    }
  });

  testWidgets(
      'direct order route blocks loading and pending; refresh unlocks approval',
      (tester) async {
    final result = Completer<KycDetailedStatus>();
    Future<KycDetailedStatus> current = result.future;
    final container = ProviderContainer(overrides: [
      kycDetailedStatusProvider.overrideWith((_) => current),
      currentTierProvider.overrideWith((_) async => tier),
      cardTierProvider('1').overrideWith((_) async => tier),
      tiersProvider.overrideWith((_) async => []),
      budgetsProvider.overrideWith((_) async => []),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OrderCardScreen())));
    await tester.pump();
    expect(find.text('Checking card verification'), findsOneWidget);
    expect(find.textContaining('Confirm & order'), findsNothing);
    result.complete(status('submitted', approved: false));
    await tester.pumpAndSettle();
    expect(find.text('Card verification pending'), findsOneWidget);
    expect(find.textContaining('Confirm & order'), findsNothing);
    expect(tester.takeException(), isNull);
    current = Future.value(status('approved', approved: true));
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(find.text('Card verification pending'), findsNothing);
    expect(find.byType(Form), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Confirm & order'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Confirm & order'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed issuer lookup never exposes the order form',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      kycDetailedStatusProvider
          .overrideWith((_) async => throw StateError('offline')),
      currentTierProvider.overrideWith((_) async => null),
      tiersProvider.overrideWith((_) async => []),
      budgetsProvider.overrideWith((_) async => []),
    ], child: const MaterialApp(home: OrderCardScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Unable to check card verification'), findsOneWidget);
    expect(find.textContaining('Confirm & order'), findsNothing);
  });

  test(
      'submission refreshes cached approval and never posts when it is no longer approved',
      () async {
    final api = RecordingApi();
    var current = status('approved', approved: true);
    final container = ProviderContainer(overrides: [
      mobileBankingApiProvider.overrideWithValue(api),
      kycDetailedStatusProvider.overrideWith((_) async => current),
    ]);
    addTearDown(container.dispose);
    expect(
        (await container.read(kycDetailedStatusProvider.future))
            .interlaceKycApproved,
        isTrue);
    await container.read(bankingActionControllerProvider.future);
    current = status('submitted', approved: false);
    await container
        .read(bankingActionControllerProvider.notifier)
        .orderCard(label: 'Example Visa TC', virtual: true);
    expect(api.orders, 0);
    expect(container.read(bankingActionControllerProvider).hasError, isTrue);
    current = status('approved', approved: true);
    await container
        .read(bankingActionControllerProvider.notifier)
        .orderCard(label: 'Example Visa TC', virtual: true);
    expect(api.orders, 1);
    expect(container.read(bankingActionControllerProvider).hasError, isFalse);
  });
}

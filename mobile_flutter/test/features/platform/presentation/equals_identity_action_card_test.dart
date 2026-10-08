import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/presentation/onboarding_banking_screen.dart';

class _Api extends MobilePlatformApi {
  _Api(this.status) : super(Dio());
  final KycDetailedStatus status;
  int reads = 0;
  @override
  Future<KycDetailedStatus> getDetailedKycStatus() async {
    reads++;
    return status;
  }
}

KycDetailedStatus _status({String? url}) => KycDetailedStatus.fromJson({
      'HoppaCardKycApproved': true,
      'CardIssuerKycApproved': true,
      'EqualsMoney': {
        'Status': 'pending_documents',
        'RequiredAction': 'identityVerificationCheck',
        'ActionUrl': url,
        'Approved': false,
      },
    });

Future<void> _pump(WidgetTester tester, _Api api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
    child: MaterialApp(home: Scaffold(body: Consumer(builder: (_, ref, __) {
      final current = ref.watch(kycDetailedStatusProvider).valueOrNull;
      return current == null
          ? const SizedBox()
          : EqualsMoneyRequiredActionCard(status: current);
    }))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Equals identityVerificationCheck exposes the verification action',
      (tester) async {
    await _pump(
        tester, _Api(_status(url: 'https://verify.example.test/session')));
    expect(find.widgetWithText(FilledButton, 'Complete identity verification'),
        findsOneWidget);
    expect(find.text('Continue EqualsMoney check'), findsNothing);
    expect(
        find.text(
            'Complete the secure EqualsMoney identity verification before the account can be approved.'),
        findsOneWidget);
  });

  testWidgets('missing URL explains the problem and lets the user refresh',
      (tester) async {
    final api = _Api(_status());
    await _pump(tester, api);
    expect(find.text('Complete identity verification'), findsNothing);
    expect(
        find.text(
            'EqualsMoney requires identity verification, but the verification link is currently unavailable. Refresh the status or contact support.'),
        findsOneWidget);
    expect(api.reads, 1);
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(api.reads, 2);
    expect(tester.takeException(), isNull);
  });
}

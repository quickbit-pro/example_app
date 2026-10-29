import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_verification_panel.dart';

class CddRequiredApi extends MobilePlatformApi {
  CddRequiredApi({this.tier = 'sdd', this.status = 'approved'}) : super(Dio());
  String tier, status;
  int starts = 0, resubmissions = 0, creations = 0;
  bool sent = false;
  @override
  Future<Map<String, dynamic>> getExchangeVerification() async => {
    'eligible': true, 'tier': tier, 'status': status,
    'hasProviderAccount': true,
    'provider': {'kycStatus': 'pending', 'nextAction': sent ? null : 'cdd_required'},
  };
  @override
  Future<Map<String, dynamic>> startExchangeVerification(String requestedTier) async {
    expect(requestedTier, 'cdd');
    starts++;
    tier = requestedTier;
    status = 'pending';
    return {'tier': tier, 'status': status};
  }
  @override
  Future<Map<String, dynamic>> getExchangeApplication() async => {
    'supported': true, 'readyToSubmit': true, 'kycLevel': 'CDD',
  };
  @override
  Future<Map<String, dynamic>> resubmitExchangeApplication(String id, {Map<String, String>? answers}) async {
    expect(tier, 'cdd');
    expect(status, 'approved');
    resubmissions++;
    sent = true;
    return {};
  }
  @override
  Future<Map<String, dynamic>> submitExchangeApplicationFromSumsub() async {
    creations++;
    return {};
  }
}

Future<void> mount(WidgetTester tester, CddRequiredApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
    child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExchangeVerificationPanel()))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('required CDD waits for approval and reuses organization', (tester) async {
    final api = CddRequiredApi();
    await mount(tester, api);
    expect(find.text('Activate Exchange'), findsNothing);
    expect(find.text('Resubmit verification'), findsNothing);
    expect(find.text('Change limits'), findsNothing);
    await tester.tap(find.text('Complete CDD verification'));
    await tester.pumpAndSettle();
    expect(api.starts, 1);
    expect(find.text('Your CDD verification is under review. You do not need to submit it again.'), findsOneWidget);
    expect(find.text('Submit CDD verification'), findsNothing);
    expect(api.resubmissions, 0);
    api.status = 'approved';
    await tester.tap(find.text('Refresh verification status'));
    await tester.pumpAndSettle();
    expect(find.text('Complete CDD verification'), findsNothing);
    await tester.tap(find.text('Submit CDD verification'));
    await tester.pumpAndSettle();
    expect(api.resubmissions, 1);
    expect(api.creations, 0);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Verification submitted')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final status in ['in_progress', 'resubmission_required']) {
    testWidgets('unfinished CDD can be resumed: $status', (tester) async {
      final api = CddRequiredApi(tier: 'cdd', status: status);
      await mount(tester, api);
      expect(find.text('Submit CDD verification'), findsNothing);
      await tester.tap(find.text('Continue CDD verification'));
      await tester.pumpAndSettle();
      expect(api.starts, 1);
      expect(api.resubmissions, 0);
    });
  }

  for (final status in ['pending', 'on_hold', 'rejected', 'unavailable']) {
    testWidgets('CDD $status cannot be restarted or submitted', (tester) async {
      final api = CddRequiredApi(tier: 'cdd', status: status);
      await mount(tester, api);
      expect(find.byType(FilledButton), findsNothing);
      expect(api.starts + api.resubmissions + api.creations, 0);
    });
  }
}

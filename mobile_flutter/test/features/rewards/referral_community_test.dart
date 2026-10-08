import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_community.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_community_screen.dart';

ReferralCommunity sample(bool enabled) => ReferralCommunity.fromJson({
      'Enabled': enabled,
      'Currency': 'USD',
      'Membership': enabled
          ? {
              'Plan': 'LEADER',
              'L2Bps': 1500,
              'L3Bps': 500,
              'Status': 'ACTIVE',
              'EnabledAt': '2026-10-06T09:00:00Z'
            }
          : null,
      'Generations': [
        for (var depth = 1; depth <= 3; depth++)
          {
            'Depth': depth,
            'Descendants': depth * 4,
            'Qualified': depth * 2,
            'Earning': depth,
            'Accrued': '0.30',
            'CashPaid': '0.20',
            'Outstanding': '0.10'
          }
      ]
    });

class CommunityApiFake extends MobilePlatformApi {
  CommunityApiFake() : super(Dio());
  @override
  Future<List<ReferralCommunityEarning>> getReferralCommunityEarnings(
          {String? programId, int page = 1}) async =>
      [];
}

void main() {
  test('community and earnings decode wire casing and decimal strings', () {
    final community = sample(true);
    expect(community.l2Percent, 15);
    expect(community.l3Percent, 5);
    expect(community.generations[2].depth, 3);
    expect(community.generations[2].outstanding, .1);
    final earning = ReferralCommunityEarning.fromJson({
      'depth': 3,
      'amount': '0.05',
      'appliedRate': '2.5',
      'requestedRate': '5',
      'reductionReason': 'RECURRING_MARGIN_BUDGET'
    });
    expect(earning.depth, 3);
    expect(earning.amount, .05);
    expect(earning.appliedRate, 2.5);
    expect(earning.reductionReason, 'RECURRING_MARGIN_BUDGET');
  });
  testWidgets('non-members never see the Community entry', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          referralCommunityProvider('p')
              .overrideWith((ref) async => sample(false))
        ],
        child: const MaterialApp(
            home: Scaffold(body: ReferralCommunityEntry(programId: 'p')))));
    await tester.pumpAndSettle();
    expect(find.text('Example Community'), findsNothing);
  });
  testWidgets(
      'enabled entry opens a dedicated community screen with protected Leader rates',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          referralCommunityProvider('p')
              .overrideWith((ref) async => sample(true)),
          mobilePlatformApiProvider.overrideWithValue(CommunityApiFake()),
        ],
        child: const MaterialApp(
            home: Scaffold(body: ReferralCommunityEntry(programId: 'p')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Community'));
    await tester.pumpAndSettle();
    expect(find.text('Community Leader'), findsOneWidget);
    expect(find.textContaining('15.00% of settled margin'), findsOneWidget);
    expect(find.textContaining('0.30% of gross top-up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('community screen fits a narrow phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          referralCommunityProvider('p')
              .overrideWith((ref) async => sample(true)),
          mobilePlatformApiProvider.overrideWithValue(CommunityApiFake()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: const ReferralCommunityScreen(programId: 'p'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

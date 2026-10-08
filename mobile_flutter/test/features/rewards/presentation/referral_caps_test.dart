import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_offer_card.dart';

void main() {
  for (final capped in [true, false]) {
    testWidgets('offer card distinguishes ${capped ? 'zero caps' : 'no caps'} at phone width', (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final offer = ReferralOffer(
        welcomeAmount: 3, qualificationRate: 1,
        topupCalculationType: 'PERCENT_OF_WL_FEE', topupRate: 8,
        earningWindowDays: 365, maximumRecurringReward: capped ? 0 : null,
        maxEligibleVolumePerRelationship: capped ? 0 : null,
        volumeCapSource: 'PROGRAM_DEFAULT', recurringRewardCapSource: 'LEVEL_CAP',
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: ReferralOfferCard(summary: ReferralSummary(offer: offer)),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Volume cap inherited from program default'), findsOneWidget);
      expect(find.textContaining('Later tier changes apply to new referrals'), findsOneWidget);
      if (capped) {
        expect(find.textContaining('no cap per friend'), findsNothing);
        expect(find.textContaining('up to \$0'), findsOneWidget);
        expect(find.textContaining('capped at \$0'), findsOneWidget);
      } else {
        expect(find.text('Eligible top-up volume: no cap per friend.'), findsOneWidget);
        expect(find.text('Recurring rewards: no cap per friend.'), findsOneWidget);
      }
    });
  }
  testWidgets('missing published offer never claims unlimited rewards', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ReferralOfferCard(summary: ReferralSummary()),
    ))));
    await tester.pumpAndSettle();
    expect(find.textContaining('no cap per friend'), findsNothing);
  });
}

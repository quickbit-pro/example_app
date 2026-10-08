import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_copy.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  test('cap fields preserve zero, unlimited and source through wire casing',
      () {
    final level = ReferralLevel.fromJson({
      'Name': 'Exclusive',
      'VolumeCapMode': 'UNLIMITED',
      'VolumeCapAmount': null,
      'RecurringRewardCapMode': 'CAPPED',
      'RecurringRewardCapAmount': 0,
      'EffectiveVolumeCap': null,
      'EffectiveRecurringRewardCap': 0,
      'VolumeCapSource': 'LEVEL_UNLIMITED',
      'RecurringRewardCapSource': 'LEVEL_CAP',
    });
    expect(level.volumeCapMode, 'UNLIMITED');
    expect(level.effectiveVolumeCap, isNull);
    expect(level.effectiveRecurringRewardCap, 0);
    expect(level.recurringRewardCapAmount, 0);
    expect(level.volumeCapSource, 'LEVEL_UNLIMITED');
    expect(ReferralLevel.fromJson({'name': 'Old'}).volumeCapSource, isNull);
  });

  test('accepted offer stays authoritative after current tier changes', () {
    final offer = ReferralOffer.fromJson({
      'topupCalculationType': 'PERCENT_OF_WL_FEE',
      'topupRate': 8,
      'maxEligibleVolumePerRelationship': 0,
      'maximumRecurringReward': null,
      'volumeCapSource': 'LEVEL_CAP',
      'recurringRewardCapSource': 'LEVEL_UNLIMITED',
      'earningWindowDays': 365,
      'welcomeAmount': 3,
      'qualificationRate': 1,
    });
    final effective = effectiveReferralOffer(ReferralSummary(
        offer: offer,
        currentLevel: const ReferralLevel(
            name: 'Exclusive',
            topupRate: 40,
            topupCalculationType: 'PERCENT_OF_WL_FEE')));
    expect(identical(effective, offer), isTrue);
    expect(effective.topupRate, 8);
    expect(effective.maxEligibleVolumePerRelationship, 0);
    expect(effective.maximumRecurringReward, isNull);
    expect(effective.volumeCapSource, 'LEVEL_CAP');
    expect(effective.earningWindowDays, 365);
    expect(effective.welcomeAmount, 3);
    expect(effective.qualificationRate, 1);
  });

  test(
      'illustration honors independent zero and absent caps and remaining volume',
      () {
    for (final volume in <double?>[null, 0, 100]) {
      for (final reward in <double?>[null, 0, 0.5]) {
        final estimate = estimateReferralReward(
            ReferralOffer(
                topupRate: 1,
                maxEligibleVolumePerRelationship: volume,
                maximumRecurringReward: reward),
            100,
            eligibleVolumeUsed: 50);
        final expected = volume == 0 || reward == 0
            ? 0
            : volume == 100 || reward == 0.5
                ? 0.5
                : 1;
        expect(estimate.amount, expected);
      }
    }
  });
}

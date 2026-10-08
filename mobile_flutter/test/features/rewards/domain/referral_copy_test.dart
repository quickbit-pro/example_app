import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_copy.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

const _offer = ReferralOffer(
  welcomeAmount: 3,
  qualificationRate: 1,
  topupRate: 0.25,
  earningWindowDays: 90,
  maxEligibleVolumePerRelationship: 5000,
  minimumTopup: 10,
);

ReferralFriend _friend(
  String stage, {
  String? earningUntil,
}) =>
    ReferralFriend.fromJson({
      'alias': 'user-1',
      'stage': stage,
      if (earningUntil != null) 'earningUntil': earningUntil,
    });

final _now = DateTime.utc(2026, 9, 15, 12);

void main() {
  group('effectiveReferralOffer', () {
    test("keeps server offer rates and caps across a later tier change", () {
      const summary = ReferralSummary(
        offer: _offer,
        currentLevel: ReferralLevel(
          name: 'Elite',
          qualificationRate: 2,
          topupRate: 0.5,
          topupCalculationType: 'PERCENT_OF_MARGIN',
        ),
      );
      final paying = effectiveReferralOffer(summary);
      expect(paying.qualificationRate, 1);
      expect(paying.topupRate, 0.25);
      expect(paying.topupCalculationType, 'PERCENT_OF_TOPUP');
      // Conditions, window and caps stay the published offer's.
      expect(paying.welcomeAmount, 3);
      expect(paying.earningWindowDays, 90);
      expect(paying.maxEligibleVolumePerRelationship, 5000);
      expect(paying.minimumTopup, 10);
    });

    test('keeps the offer when the level names no rate', () {
      const summary = ReferralSummary(
        offer: _offer,
        currentLevel: ReferralLevel(name: 'Pro'),
      );
      expect(effectiveReferralOffer(summary).topupRate, 0.25);
      expect(effectiveReferralOffer(summary).qualificationRate, 1);
    });
  });

  group('qualification steps', () {
    test('follow the offer flags in order', () {
      expect(referralQualificationSteps(_offer), [
        ReferralQualificationStep.verifyIdentity,
        ReferralQualificationStep.getPaidCard,
        ReferralQualificationStep.firstTopup,
      ]);
      expect(
        referralQualificationSteps(
          const ReferralOffer(requiresKyc: false, requiresPaidCard: false),
        ),
        [ReferralQualificationStep.firstTopup],
      );
      expect(
        referralQualificationSteps(const ReferralOffer(
          requiresKyc: false,
          requiresPaidCard: false,
          requiresTopup: false,
        )),
        isEmpty,
      );
    });
  });

  group('friend next step', () {
    test('names the first requirement the friend has not met', () {
      expect(referralFriendNextStep(_friend('INVITED'), _offer),
          ReferralFriendNextStep.verifyIdentity);
      expect(referralFriendNextStep(_friend('VERIFYING'), _offer),
          ReferralFriendNextStep.verifyIdentity);
      expect(referralFriendNextStep(_friend('CARD_ISSUED'), _offer),
          ReferralFriendNextStep.firstTopup);
      expect(referralFriendNextStep(_friend('WINDOW_ENDED'), _offer),
          ReferralFriendNextStep.windowEnded);
      expect(referralFriendNextStep(_friend('SOMETHING'), _offer),
          ReferralFriendNextStep.inProgress);
    });

    test('skips steps the offer does not require', () {
      const noKyc = ReferralOffer(requiresKyc: false);
      expect(referralFriendNextStep(_friend('INVITED'), noKyc),
          ReferralFriendNextStep.getPaidCard);
      const cardOnly = ReferralOffer(requiresKyc: false, requiresTopup: false);
      expect(referralFriendNextStep(_friend('CARD_ISSUED'), cardOnly),
          ReferralFriendNextStep.inProgress);
    });

    test('reads the earning window off a qualified friend', () {
      final earning =
          _friend('QUALIFIED', earningUntil: '2026-10-15T12:00:00Z');
      expect(referralFriendNextStep(earning, _offer, now: _now),
          ReferralFriendNextStep.earning);
      expect(referralEarningDaysLeft(earning, now: _now), 30);

      final ended = _friend('QUALIFIED', earningUntil: '2026-09-01T00:00:00Z');
      expect(referralFriendNextStep(ended, _offer, now: _now),
          ReferralFriendNextStep.windowEnded);
      expect(referralEarningDaysLeft(ended, now: _now), 0);

      final open = _friend('QUALIFIED');
      expect(referralFriendNextStep(open, _offer, now: _now),
          ReferralFriendNextStep.earning);
      expect(referralEarningDaysLeft(open, now: _now), isNull);
    });
  });

  group('estimateReferralReward', () {
    test('is rate × amount for a share of the top-up', () {
      final estimate = estimateReferralReward(_offer, 100);
      expect(estimate.amount, 0.25);
      expect(estimate.basis, ReferralRecurringBasis.topup);
      expect(estimate.isUpperBound, isFalse);
      expect(estimate.volumeCapped, isFalse);
      expect(estimate.eligibleAmount, 100);
    });

    test('rounds down to cents, as the ledger does', () {
      expect(estimateReferralReward(_offer, 33.33).amount, 0.08);
    });

    test('counts only the eligible volume under the per-friend cap', () {
      final estimate = estimateReferralReward(_offer, 6000);
      expect(estimate.eligibleAmount, 5000);
      expect(estimate.amount, 12.5);
      expect(estimate.volumeCapped, isTrue);

      final used =
          estimateReferralReward(_offer, 1000, eligibleVolumeUsed: 4800);
      expect(used.eligibleAmount, 200);
      expect(used.amount, 0.5);
      expect(used.volumeCapped, isTrue);
    });

    test('stops at the recurring reward cap', () {
      const capped = ReferralOffer(topupRate: 10, maximumRecurringReward: 5);
      final estimate = estimateReferralReward(capped, 100);
      expect(estimate.amount, 5);
      expect(estimate.rewardCapped, isTrue);
    });

    test('a fixed amount pays per top-up', () {
      const fixed = ReferralOffer(topupCalculationType: 'FIXED', topupRate: .5);
      expect(estimateReferralReward(fixed, 100).amount, 0.5);
      expect(estimateReferralReward(fixed, 100).basis,
          ReferralRecurringBasis.fixed);
      expect(estimateReferralReward(fixed, 0).amount, 0);
    });

    test('fee and margin shares are upper bounds until settlement', () {
      const margin = ReferralOffer(
          topupCalculationType: 'PERCENT_OF_MARGIN', topupRate: 30);
      final estimate = estimateReferralReward(margin, 100);
      expect(estimate.basis, ReferralRecurringBasis.margin);
      expect(estimate.isUpperBound, isTrue);
      expect(estimate.amount, 30);
      const fee = ReferralOffer(
          topupCalculationType: 'PERCENT_OF_WL_FEE', topupRate: 30);
      expect(estimateReferralReward(fee, 100).isUpperBound, isTrue);
    });

    test('never pays on a negative amount', () {
      expect(estimateReferralReward(_offer, -50).amount, 0);
    });
  });

  group('delivery states', () {
    test('map the ledger stage for the delivery mode', () {
      expect(
        referralRewardDelivery(ReferralRewardStage.pending,
            usesVouchers: false),
        ReferralRewardDelivery.awaitingConfirmation,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.ready, usesVouchers: false),
        ReferralRewardDelivery.awaitingCredit,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.ready, usesVouchers: true),
        ReferralRewardDelivery.readyToClaim,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.crediting,
            usesVouchers: false),
        ReferralRewardDelivery.awaitingCredit,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.paid, usesVouchers: false),
        ReferralRewardDelivery.credited,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.paid, usesVouchers: true),
        ReferralRewardDelivery.claimed,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.failed, usesVouchers: false),
        ReferralRewardDelivery.failed,
      );
      expect(
        referralRewardDelivery(ReferralRewardStage.unknown,
            usesVouchers: false),
        ReferralRewardDelivery.underReview,
      );
    });
  });

  group('filters', () {
    final rewards = [
      for (final stage in ['PENDING', 'READY', 'CREDITING', 'PAID', 'FAILED'])
        ReferralReward.fromJson(
            {'amount': 1, 'currency': 'USD', 'stage': stage}),
    ];

    test('the earnings filter narrows by delivery state and round-trips', () {
      expect(rewards.where(ReferralEarningsFilter.awaiting.matches).length, 3);
      expect(rewards.where(ReferralEarningsFilter.paid.matches).length, 1);
      expect(rewards.where(ReferralEarningsFilter.failed.matches).length, 1);
      expect(rewards.where(ReferralEarningsFilter.all.matches).length, 5);
      for (final filter in ReferralEarningsFilter.values) {
        expect(ReferralEarningsFilter.fromWire(filter.wire), filter);
      }
      expect(ReferralEarningsFilter.fromWire('nonsense'),
          ReferralEarningsFilter.all);
      expect(ReferralEarningsFilter.fromWire(null), ReferralEarningsFilter.all);
    });

    test('the friends filter narrows by where the friend stands', () {
      final friends = [
        _friend('INVITED'),
        _friend('CARD_ISSUED'),
        _friend('QUALIFIED', earningUntil: '2026-10-15T00:00:00Z'),
        _friend('QUALIFIED', earningUntil: '2026-09-01T00:00:00Z'),
        _friend('WINDOW_ENDED'),
      ];
      int count(ReferralFriendsFilter filter) =>
          friends.where((f) => filter.matches(f, _offer, now: _now)).length;
      expect(count(ReferralFriendsFilter.all), 5);
      expect(count(ReferralFriendsFilter.inProgress), 2);
      expect(count(ReferralFriendsFilter.earning), 1);
      expect(count(ReferralFriendsFilter.ended), 2);
    });
  });

  group('ordering', () {
    test('newest first, unknown dates last', () {
      final friends = sortReferralFriendsNewestFirst([
        _friend('INVITED'),
        ReferralFriend.fromJson(
            const {'alias': 'old', 'attributedAt': '2026-01-01T00:00:00Z'}),
        ReferralFriend.fromJson(
            const {'alias': 'new', 'attributedAt': '2026-09-01T00:00:00Z'}),
      ]);
      expect(friends.map((f) => f.alias), ['new', 'old', 'user-1']);

      final rewards = sortReferralRewardsNewestFirst([
        ReferralReward.fromJson(const {
          'id': 'a',
          'amount': 1,
          'occurredAt': '2026-09-01T00:00:00Z'
        }),
        ReferralReward.fromJson(const {
          'id': 'b',
          'amount': 1,
          'createdAt': '2026-09-03T00:00:00Z'
        }),
        ReferralReward.fromJson(const {'id': 'c', 'amount': 1}),
      ]);
      expect(rewards.map((r) => r.id), ['b', 'a', 'c']);
    });
  });
}

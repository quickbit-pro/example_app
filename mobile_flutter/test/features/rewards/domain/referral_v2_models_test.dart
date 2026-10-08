// The v2 referral shapes the mobile backend forwards from the platform.
//
// The parsers are tolerant on purpose: the platform emitted PascalCase for
// years and the mobile backend forwards camelCase, and a build in the field
// may still be talking to a backend without `rewards`, `friends`, `offer` or
// `terms`. These cases pin that every field has a home in both spellings and
// that a missing one degrades to a value the screen can render.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  test('promo policy parses both casings and preserves legacy defaults', () {
    expect(ReferralOffer.fromJson(const {}).promoCodePolicyEnabled, isFalse);
    expect(ReferralOffer.fromJson(const {'promoCodePolicyEnabled': true}).promoCodePolicyEnabled, isTrue);
    expect(ReferralOffer.fromJson(const {'PromoCodePolicyEnabled': true}).promoCodePolicyEnabled, isTrue);
  });
  test('residence restrictions parse both API casings without affecting legacy summaries', () {
    final excluded = ReferralSummary.fromJson(const {
      'CanInvite': false,
      'ParticipationEligibility': {'Status': 'INELIGIBLE', 'Reason': 'GEO_RESIDENCE_EXCLUDED'},
    });
    expect(excluded.residenceRestricted, isTrue);
    expect(excluded.residenceRestrictionMessage, contains('previously paid rewards remain unchanged'));
    final pending = ReferralSummary.fromJson(const {
      'canInvite': false,
      'participationEligibility': {'status': 'PENDING', 'reason': 'GEO_COUNTRY_UNVERIFIED'},
    });
    expect(pending.residenceRestricted, isTrue);
    expect(pending.residenceRestrictionMessage, contains('Verify your country of residence'));
    expect(ReferralSummary.fromJson(const {}).residenceRestricted, isFalse);
  });
  test('parses protected margin offer and sanitized reward explanation', () {
    final offer = ReferralOffer.fromJson(const {'TopupCalculationType': 'PERCENT_OF_MARGIN', 'TopupRate': '30', 'MaximumRecurringReward': '20', 'CustomerRecurringRate': '12'});
    expect(offer.maximumRecurringReward, 20); expect(offer.customerRecurringRate, 12);
    final reward = ReferralReward.fromJson(const {'Amount': '2.28', 'Explanation': {'Basis': 'PERCENT_OF_MARGIN', 'Rate': '30', 'TermsVersion': 3, 'Rounding': 'Rounded down to USD cents', 'DeliveryExplanation': 'Waiting for wallet credit'}});
    expect(reward.explanation?.rate, 30); expect(reward.explanation?.termsVersion, 3);
    expect(reward.explanation?.rounding, 'Rounded down to USD cents');
    expect(ReferralReward.fromJson(const {}).explanation, isNull);
  });
  group('ReferralSummary', () {
    test('parses the v2 shape in camelCase', () {
      final summary = ReferralSummary.fromJson(const {
        'enabled': true,
        'provider': 'INTERLACE',
        'referralCode': 'EXAMPLE28',
        'referralPath': 'https://example.com/r/EXAMPLE28',
        'currentLevel': {
          'id': '6f1c',
          'code': 'PRO',
          'name': 'Pro',
          'qualificationCalculationType': 'FIXED',
          'qualificationRate': 1,
          'topupCalculationType': 'PERCENT_OF_TOPUP',
          'topupRate': 0.25,
          'hidden': false,
        },
        'levels': [
          {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
          {'code': 'ELITE', 'name': 'Elite', 'minimumMetricValue': 5},
        ],
        'progress': {
          'basis': 'QUALIFIED_REFERRALS',
          'currentValue': 3,
          'nextThreshold': 5,
          'remaining': 2,
          'lookbackMonths': 12,
        },
        'referrals': {
          'invited': 8,
          'qualified': 3,
          'inProgress': 2,
          'earning': 3
        },
        'rewards': {
          'pending': '1.50',
          'ready': 2,
          'crediting': 0.5,
          'paid': 10,
          'failed': 0,
          'currency': 'USD',
        },
        'offer': {
          'welcomeAmount': 3,
          'welcomeCurrency': 'USD',
          'qualificationCalculationType': 'FIXED',
          'qualificationRate': 1,
          'topupCalculationType': 'PERCENT_OF_TOPUP',
          'topupRate': 0.25,
          'earningWindowDays': 365,
          'earningWindowStart': 'QUALIFICATION',
          'maxEligibleVolumePerRelationship': 10000,
          'requiresKyc': true,
          'requiresPaidCard': true,
          'requiresTopup': true,
          'minimumTopup': 10,
        },
        'terms': {
          'version': 2,
          'text': 'Programme terms.',
          'privacyNotice': 'We share your alias with your inviter.',
          'accepted': false,
          'acceptedVersion': 1,
          'acceptedAt': '2026-01-02T03:04:05Z',
        },
        'deliveryMode': 'WALLET_CREDIT',
        'minimumCreditAmount': 0.01,
        'accumulatedTowardsCredit': 2,
        'programId': 'c4b1',
        'programName': 'Example referrals',
        'programDescription': 'Your friend gets \$3 once verified; you earn '
            '\$1 plus 0.25% of their top-ups for a year.',
        'canInvite': true,
        'assignedLevel': false,
      });

      expect(summary.enabled, isTrue);
      expect(summary.referralCode, 'EXAMPLE28');
      expect(summary.currentLevel?.name, 'Pro');
      expect(summary.levels.map((l) => l.code), ['PRO', 'ELITE']);
      expect(summary.showsLevels, isTrue);
      expect(summary.progress.nextThreshold, 5);
      expect(summary.referrals.qualified, 3);
      expect(summary.referrals.earning, 3);
      expect(summary.rewards.pending, 1.5);
      expect(summary.rewards.earned, 14);
      expect(summary.offer?.welcomeAmount, 3);
      expect(summary.offer?.topupRate, 0.25);
      expect(summary.offer?.minimumTopup, 10);
      expect(summary.terms?.version, 2);
      expect(summary.terms?.accepted, isFalse);
      expect(summary.terms?.acceptedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(summary.mustAcceptTerms, isTrue);
      expect(summary.deliveryMode, 'WALLET_CREDIT');
      expect(summary.usesVouchers, isFalse);
      expect(summary.creditsWallet, isTrue);
      expect(summary.minimumCreditAmount, 0.01);
      expect(summary.accumulatedTowardsCredit, 2);
      expect(summary.programId, 'c4b1');
      expect(
        summary.programDescription,
        'Your friend gets \$3 once verified; you earn \$1 plus 0.25% of '
        'their top-ups for a year.',
      );
      expect(summary.hasProgramDescription, isTrue);
      expect(summary.canInvite, isTrue);
    });

    test('the programme description arrives in either casing or not at all',
        () {
      expect(
        ReferralSummary.fromJson(const {'ProgramDescription': 'In our words.'})
            .programDescription,
        'In our words.',
      );
      // The admin left the field empty: the API sends null, and a blank
      // string means the same thing.
      for (final blank in [null, '', '   ']) {
        final summary = ReferralSummary.fromJson({'programDescription': blank});
        expect(summary.programDescription, isNull, reason: '$blank');
        expect(summary.hasProgramDescription, isFalse, reason: '$blank');
      }
      expect(
        ReferralSummary.fromJson(const {}).hasProgramDescription,
        isFalse,
      );
    });

    test('accepts PascalCase and the legacy commissions block', () {
      final summary = ReferralSummary.fromJson(const {
        'ReferralCode': 'LEGACY1',
        'CurrentLevel': {'Name': 'Pro'},
        'Progress': {'CurrentValue': 3, 'NextThreshold': 5},
        'Referrals': {'Invited': 8, 'Successful': 3, 'InProgress': 2},
        'Commissions': {'Available': 1, 'Currency': 'EUR'},
      });

      expect(summary.enabled, isTrue);
      expect(summary.referralCode, 'LEGACY1');
      expect(summary.currentLevel?.name, 'Pro');
      expect(summary.referrals.qualified, 3);
      expect(summary.rewards.ready, 1);
      expect(summary.rewards.currency, 'EUR');
      // One level in the old shape is no ladder.
      expect(summary.showsLevels, isFalse);
      // No delivery mode published means the wallet-credit default, no terms
      // published means nothing to accept, and no offer means no headline.
      expect(summary.deliveryMode, 'WALLET_CREDIT');
      expect(summary.mustAcceptTerms, isFalse);
      expect(summary.offer, isNull);
    });

    test('terms with no text never gate, and a voucher mode is recognised', () {
      final summary = ReferralSummary.fromJson(const {
        'terms': {'version': 1, 'text': '', 'accepted': false},
        'deliveryMode': 'voucher_per_commission',
        'levels': [
          {'code': 'ONLY', 'name': 'Only'},
        ],
      });

      expect(summary.terms?.published, isFalse);
      expect(summary.mustAcceptTerms, isFalse);
      expect(summary.usesVouchers, isTrue);
      expect(summary.showsLevels, isFalse);
    });

    test('an explicit enabled=false is honoured', () {
      expect(
          ReferralSummary.fromJson(const {'enabled': false}).enabled, isFalse);
      expect(ReferralSummary.fromJson(const {'Enabled': 'false'}).enabled,
          isFalse);
    });
  });

  group('ReferralReward', () {
    test('parses a ledger row and maps the stage', () {
      final reward = ReferralReward.fromJson(const {
        'id': '9a8b',
        'eventType': 'CARD_TOPUP',
        'beneficiaryRole': 'REFERRER',
        'levelCode': 'PRO',
        'basisAmount': 100,
        'basisCurrency': 'USD',
        'amount': '0.25',
        'currency': 'USD',
        'deliveryMode': 'WALLET_CREDIT',
        'status': 'CREDITING',
        'stage': 'CREDITING',
        'creditId': 'cr1',
        'friendAlias': 'user-A1B2C',
        'occurredAt': '2026-09-01T10:00:00Z',
        'createdAt': '2026-09-01T10:00:01Z',
      });

      expect(reward.eventType, 'CARD_TOPUP');
      expect(reward.eventLabel, 'Top-up commission');
      expect(reward.amount, 0.25);
      expect(reward.stage, ReferralRewardStage.crediting);
      expect(reward.friendAlias, 'user-A1B2C');
      expect(reward.occurredAt, DateTime.utc(2026, 9, 1, 10));
      expect(reward.paidAt, isNull);
    });

    test('falls back to the status when stage is absent, incl. legacy names',
        () {
      ReferralRewardStage stageOf(String status) => ReferralReward.fromJson(
          {'amount': 1, 'currency': 'USD', 'status': status}).stage;

      expect(stageOf('READY'), ReferralRewardStage.ready);
      expect(stageOf('AVAILABLE'), ReferralRewardStage.ready);
      expect(stageOf('DELIVERY_PENDING'), ReferralRewardStage.pending);
      expect(stageOf('PROCESSING'), ReferralRewardStage.crediting);
      expect(stageOf('PAID'), ReferralRewardStage.paid);
      expect(stageOf('FAILED'), ReferralRewardStage.failed);
      expect(stageOf('HELD'), ReferralRewardStage.unknown);
    });

    test('groups rewards by stage, newest first, without failed rows', () {
      ReferralReward row(String stage, int day) => ReferralReward.fromJson({
            'amount': 1,
            'currency': 'USD',
            'stage': stage,
            'occurredAt': '2026-09-${day.toString().padLeft(2, '0')}T00:00:00Z',
          });
      final groups = groupReferralRewards([
        row('PAID', 1),
        row('PENDING', 3),
        row('READY', 2),
        row('PENDING', 5),
        row('FAILED', 4),
        row('CREDITING', 6),
      ]);

      expect(groups.keys.toList(), referralLedgerStages);
      expect(groups[ReferralRewardStage.pending]!.map((r) => r.occurredAt!.day),
          [5, 3]);
      expect(groups[ReferralRewardStage.ready], hasLength(1));
      expect(groups[ReferralRewardStage.crediting], hasLength(1));
      expect(groups[ReferralRewardStage.paid], hasLength(1));
      expect(groups.containsKey(ReferralRewardStage.failed), isFalse);
    });
  });

  group('ReferralFriend', () {
    test('parses a friend and prefers the typed name over the alias', () {
      final named = ReferralFriend.fromJson(const {
        'id': 'r1',
        'alias': 'user-A1B2C',
        'stage': 'QUALIFIED',
        'attributedAt': '2026-08-01T00:00:00Z',
        'qualifiedAt': '2026-08-10T00:00:00Z',
        'earningUntil': '2099-08-10T00:00:00Z',
        'earnedAmount': 4.5,
        'currency': 'USD',
        'recipientName': 'Maja',
      });
      final anonymous = ReferralFriend.fromJson(const {
        'Alias': 'user-Z9Y8X',
        'Stage': 'VERIFYING',
        'EarnedAmount': 0,
        'RecipientName': null,
      });

      expect(named.displayName, 'Maja');
      expect(named.stage, ReferralFriendStage.qualified);
      expect(named.isEarning, isTrue);
      expect(named.earnedAmount, 4.5);
      expect(anonymous.displayName, 'user-Z9Y8X');
      expect(anonymous.stage, ReferralFriendStage.verifying);
      expect(anonymous.isEarning, isFalse);
    });

    test('unknown stages stay renderable', () {
      expect(ReferralFriendStage.fromWire('SOMETHING_NEW'),
          ReferralFriendStage.unknown);
      expect(ReferralFriendStage.fromWire('window_ended'),
          ReferralFriendStage.windowEnded);
    });
  });

  group('ReferralWelcome', () {
    test('parses check-referral fields and tolerates their absence', () {
      final full = ReferralWelcome.fromJson(const {
        'valid': true,
        'inviterDisplayName': 'John',
        'welcomeAmount': 3,
        'welcomeCurrency': 'USD',
        'termsVersion': 2,
      });
      final bare = ReferralWelcome.fromJson(const {'Valid': true});

      expect(full.inviterDisplayName, 'John');
      expect(full.hasWelcome, isTrue);
      expect(full.termsVersion, 2);
      expect(bare.valid, isTrue);
      expect(bare.hasWelcome, isFalse);
      expect(bare.termsVersion, isNull);
      expect(bare.inviterDisplayName, isNull);
    });
  });

  group('offer copy', () {
    test('formats amounts without trailing cents and rates compactly', () {
      expect(formatReferralAmount('USD', 3), r'$3');
      expect(formatReferralAmount('USD', 2.5), r'$2.50');
      expect(formatReferralAmount('EUR', 1000), '€1,000');
      expect(formatReferralPercent(0.25), '0.25%');
      expect(formatReferralPercent(10), '10%');
    });

    test('describes the referrer reward from the published rates', () {
      expect(
        describeReferrerReward(const ReferralOffer(
          qualificationRate: 1,
          topupRate: 0.25,
        )),
        r'$1 + 0.25%',
      );
      expect(
        describeReferrerReward(const ReferralOffer(
          qualificationCalculationType: 'PERCENT_OF_CARD_FEE',
          qualificationRate: 50,
          topupCalculationType: 'FIXED',
          topupRate: 0.1,
        )),
        r'50% + $0.10',
      );
      expect(describeReferrerReward(const ReferralOffer()), isNull);
    });
  });

  group('RewardsSnapshot', () {
    const config = MobileTenantConfig(
      companyName: 'Acme',
      brandName: 'Acme',
      referralsEnabled: true,
      referralRegistrationMode: 'optional',
      vouchersEnabled: true,
      existingAccountClaimEnabled: false,
      boomFiExchangeEnabled: false,
      walletOutflowsEnabled: false,
      equalsMoneyEnabled: true,
    );

    test('shows voucher sections only for voucher delivery', () {
      expect(
        const RewardsSnapshot(
          config: config,
          referralSummary: {'deliveryMode': 'WALLET_CREDIT'},
        ).showsVoucherSections,
        isFalse,
      );
      expect(
        const RewardsSnapshot(
          config: config,
          referralSummary: {'deliveryMode': 'AUTOMATIC_TRANSFER'},
        ).showsVoucherSections,
        isTrue,
      );
      // A voucher-only tenant keeps its voucher entry.
      expect(
        const RewardsSnapshot(
          config: MobileTenantConfig(
            companyName: 'Acme',
            brandName: 'Acme',
            referralsEnabled: false,
            referralRegistrationMode: 'disabled',
            vouchersEnabled: true,
            existingAccountClaimEnabled: false,
            boomFiExchangeEnabled: false,
            walletOutflowsEnabled: false,
            equalsMoneyEnabled: true,
          ),
        ).showsVoucherSections,
        isTrue,
      );
    });
  });

  group('ReferralLevel conditions', () {
    test('reads both conditions and treats zero or null as none', () {
      final both = ReferralLevel.fromJson(const {
        'name': 'Elite',
        'minimumMetricValue': 5,
        'minimumQualifiedReferrals': 5,
        'minimumTopupVolume': '2000.00',
      });
      expect(both.minimumQualifiedReferrals, 5);
      expect(both.minimumTopupVolume, 2000);
      expect(both.hasConditions, isTrue);

      final volumeOnly = ReferralLevel.fromJson(const {
        'Name': 'Elite',
        'MinimumMetricValue': 0,
        'MinimumQualifiedReferrals': null,
        'MinimumTopupVolume': 2000,
      });
      expect(volumeOnly.minimumQualifiedReferrals, isNull);
      expect(volumeOnly.minimumTopupVolume, 2000);

      final starting = ReferralLevel.fromJson(const {
        'name': 'Pro',
        'minimumMetricValue': 0,
        'minimumQualifiedReferrals': 0,
        'minimumTopupVolume': 0,
      });
      expect(starting.hasConditions, isFalse);
    });

    test('an old backend with only the single threshold means referrals', () {
      final level = ReferralLevel.fromJson(const {
        'name': 'Elite',
        'minimumMetricValue': 5,
      });
      expect(level.minimumQualifiedReferrals, 5);
      expect(level.minimumTopupVolume, isNull);
      expect(
        ReferralLevel.fromJson(const {'name': 'Pro', 'minimumMetricValue': 0})
            .hasConditions,
        isFalse,
      );
    });
  });

  group('ReferralProgress conditions', () {
    test('parses the per-condition fields', () {
      final progress = ReferralProgress.fromJson(const {
        'basis': 'SUCCESSFUL_REFERRAL_COUNT',
        'currentValue': 3,
        'nextThreshold': 5,
        'remaining': 2,
        'lookbackMonths': 6,
        'qualifiedReferrals': 3,
        'topupVolume': 1400,
        'topupVolumeCurrency': 'USD',
        'nextMinimumQualifiedReferrals': 5,
        'nextMinimumTopupVolume': 2000,
        'remainingQualifiedReferrals': 2,
        'remainingTopupVolume': 600,
      });
      expect(progress.qualifiedReferrals, 3);
      expect(progress.topupVolume, 1400);
      expect(progress.topupVolumeCurrency, 'USD');
      expect(progress.nextMinimumQualifiedReferrals, 5);
      expect(progress.nextMinimumTopupVolume, 2000);
      expect(progress.remainingQualifiedReferrals, 2);
      expect(progress.remainingTopupVolume, 600);
      expect(progress.nextConditions, hasLength(2));
      // 60% on referrals, 70% on top-ups: the rail shows referrals.
      expect(progress.focusCondition?.kind,
          ReferralConditionKind.qualifiedReferrals);
      expect(progress.focusCondition?.remaining, 2);
    });

    test('the focus is the condition with the smaller fraction', () {
      final progress = ReferralProgress.fromJson(const {
        'qualifiedReferrals': 5,
        'topupVolume': 500,
        'nextMinimumQualifiedReferrals': 5,
        'nextMinimumTopupVolume': 2000,
      });
      final focus = progress.focusCondition!;
      expect(focus.kind, ReferralConditionKind.topupVolume);
      expect(focus.fraction, 0.25);
      expect(focus.remaining, 1500);
      expect(focus.met, isFalse);
      // The met one still reports zero left, never a negative.
      expect(progress.nextConditions.first.met, isTrue);
      expect(progress.nextConditions.first.remaining, 0);
      expect(progress.remainingQualifiedReferrals, 0);
    });

    test('an old backend with only the single threshold still has a ladder',
        () {
      final progress = ReferralProgress.fromJson(const {
        'CurrentValue': 3,
        'NextThreshold': 5,
        'Remaining': 2,
      });
      expect(progress.qualifiedReferrals, 3);
      expect(progress.topupVolume, 0);
      expect(progress.nextMinimumQualifiedReferrals, 5);
      expect(progress.nextMinimumTopupVolume, isNull);
      expect(progress.remainingQualifiedReferrals, 2);
      expect(progress.remainingTopupVolume, isNull);
      expect(progress.nextConditions, hasLength(1));
      expect(progress.focusCondition?.fraction, 0.6);
    });

    test('a next level without conditions, or none at all, has no focus', () {
      expect(ReferralProgress.fromJson(const {}).focusCondition, isNull);
      expect(
        ReferralProgress.fromJson(const {
          'currentValue': 3,
          'nextThreshold': null,
          'nextMinimumQualifiedReferrals': null,
          'nextMinimumTopupVolume': 0,
        }).nextConditions,
        isEmpty,
      );
    });
  });
}

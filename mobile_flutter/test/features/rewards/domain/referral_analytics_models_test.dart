// The member analytics shape (contract 2026-09-15).
//
// The resource is newer than the rest of the member API, so the parser has
// to read both spellings, sort what the platform sends, drop rows it cannot
// place, and turn an empty body into zeros rather than a failure. These
// cases pin that, and the one derived question the screens ask — "did
// anything happen in this period?".
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  group('ReferralMemberAnalytics', () {
    test('parses the contract shape in camelCase, weeks sorted', () {
      final analytics = ReferralMemberAnalytics.fromJson(const {
        'from': '2026-08-16T00:00:00Z',
        'to': '2026-09-15T00:00:00Z',
        'range': '30d',
        'currency': 'USD',
        'generatedAt': '2026-09-15T08:00:00Z',
        'journey': {
          'invited': 2,
          'verified': 1,
          'cardIssued': 1,
          'qualified': 1,
          'earning': 3,
          'windowEnded': 0,
        },
        'totals': {
          'attributed': 8,
          'qualified': 3,
          'conversionRate': 0.375,
          'rewardsAccrued': 13.5,
          'rewardsPaid': 10,
          'rewardsPending': 3.5,
        },
        'weekly': [
          {
            'weekStart': '2026-09-07T00:00:00Z',
            'attributed': 1,
            'qualified': 0,
            'rewardsAccrued': 0.5,
            'rewardsPaid': 0,
          },
          {
            'weekStart': '2026-08-31T00:00:00Z',
            'attributed': 3,
            'qualified': 2,
            'rewardsAccrued': 6,
            'rewardsPaid': 4,
          },
          {'attributed': 9, 'qualified': 9},
        ],
        'topFriends': [
          {
            'alias': 'user-A1B2C',
            'stage': 'QUALIFIED',
            'earned': 4.5,
            'qualifiedAt': '2026-09-01T00:00:00Z',
          },
          {'alias': '', 'stage': 'INVITED', 'earned': 0},
        ],
      });

      expect(analytics.from, DateTime.utc(2026, 8, 16));
      expect(analytics.to, DateTime.utc(2026, 9, 15));
      expect(analytics.range, ReferralAnalyticsRange.thirtyDays);
      expect(analytics.currency, 'USD');
      expect(analytics.generatedAt, DateTime.utc(2026, 9, 15, 8));
      expect(analytics.journey.invited, 2);
      expect(analytics.journey.verified, 1);
      expect(analytics.journey.cardIssued, 1);
      expect(analytics.journey.qualified, 1);
      expect(analytics.journey.earning, 3);
      expect(analytics.journey.windowEnded, 0);
      expect(analytics.journey.total, 8);
      expect(
        analytics.journey.stages.map((stage) => stage.id),
        ['invited', 'verified', 'cardIssued', 'qualified', 'earning', 'windowEnded'],
      );
      expect(analytics.totals.attributed, 8);
      expect(analytics.totals.qualified, 3);
      expect(analytics.totals.conversionRate, 0.375);
      expect(analytics.totals.rewardsAccrued, 13.5);
      expect(analytics.totals.rewardsPaid, 10);
      expect(analytics.totals.rewardsPending, 3.5);
      // Oldest week first; a row without a week start has no place on
      // the axis and is dropped.
      expect(analytics.weekly.map((week) => week.weekStart),
          [DateTime.utc(2026, 8, 31), DateTime.utc(2026, 9, 7)]);
      expect(analytics.weekly.first.attributed, 3);
      expect(analytics.weekly.first.qualified, 2);
      expect(analytics.weekly.first.rewardsAccrued, 6);
      expect(analytics.weekly.first.rewardsPaid, 4);
      // A friend without a pseudonym cannot be listed.
      final friend = analytics.topFriends.single;
      expect(friend.alias, 'user-A1B2C');
      expect(friend.stage, ReferralFriendStage.qualified);
      expect(friend.earned, 4.5);
      expect(friend.qualifiedAt, DateTime.utc(2026, 9, 1));
      expect(analytics.isEmpty, isFalse);
    });

    test('reads the PascalCase the platform used to emit', () {
      final analytics = ReferralMemberAnalytics.fromJson(const {
        'Range': 'MONTH',
        'Currency': 'EUR',
        'Journey': {'Invited': '4', 'Qualified': 2},
        'Totals': {'Attributed': 4, 'Qualified': 2, 'ConversionRate': '0.5'},
        'Weekly': [
          {'WeekStart': '2026-09-01T00:00:00Z', 'Qualified': 2},
        ],
        'TopFriends': [
          {'Alias': 'user-Q1', 'Stage': 'EARNING', 'Earned': '1.25'},
        ],
      });
      expect(analytics.range, ReferralAnalyticsRange.month);
      expect(analytics.currency, 'EUR');
      expect(analytics.journey.invited, 4);
      expect(analytics.journey.qualified, 2);
      expect(analytics.totals.conversionRate, 0.5);
      expect(analytics.weekly.single.qualified, 2);
      // The analytics journey names a friend inside the window "earning";
      // for the stage chip that is a qualified friend.
      expect(analytics.topFriends.single.stage, ReferralFriendStage.qualified);
      expect(analytics.topFriends.single.earned, 1.25);
    });

    test('an empty body is zeros, and an empty period says so', () {
      final blank = ReferralMemberAnalytics.fromJson(const {});
      expect(blank.range, ReferralAnalyticsRange.thirtyDays);
      expect(blank.currency, 'USD');
      expect(blank.journey.total, 0);
      expect(blank.totals.attributed, 0);
      expect(blank.weekly, isEmpty);
      expect(blank.topFriends, isEmpty);
      expect(blank.isEmpty, isTrue);

      // Weeks with zeros are kept by the platform and do not count as
      // activity; one reward in one week does.
      final quiet = ReferralMemberAnalytics.fromJson(const {
        'weekly': [
          {'weekStart': '2026-09-01T00:00:00Z'},
          {'weekStart': '2026-09-08T00:00:00Z'},
        ],
      });
      expect(quiet.isEmpty, isTrue);
      final active = ReferralMemberAnalytics.fromJson(const {
        'weekly': [
          {'weekStart': '2026-09-01T00:00:00Z', 'rewardsAccrued': 0.25},
        ],
      });
      expect(active.isEmpty, isFalse);
    });

    test('clamps a conversion rate and negative counts', () {
      final analytics = ReferralMemberAnalytics.fromJson(const {
        'journey': {'invited': -3},
        'totals': {'conversionRate': 1.4},
      });
      expect(analytics.journey.invited, 0);
      expect(analytics.totals.conversionRate, 1);
    });
  });

  group('ReferralAnalyticsRange', () {
    test('reads the wire values and defaults to 30 days', () {
      expect(ReferralAnalyticsRange.fromWire('7d'),
          ReferralAnalyticsRange.sevenDays);
      expect(ReferralAnalyticsRange.fromWire(' 90D '),
          ReferralAnalyticsRange.ninetyDays);
      expect(ReferralAnalyticsRange.fromWire('month'),
          ReferralAnalyticsRange.month);
      expect(ReferralAnalyticsRange.fromWire(null),
          ReferralAnalyticsRange.thirtyDays);
      expect(ReferralAnalyticsRange.fromWire('year'),
          ReferralAnalyticsRange.thirtyDays);
      expect(ReferralAnalyticsRange.sevenDays.days, 7);
      expect(ReferralAnalyticsRange.month.days, isNull);
    });
  });

  test('friend stage tolerates the journey outcome names', () {
    expect(ReferralFriendStage.fromWire('VERIFIED'),
        ReferralFriendStage.verifying);
    expect(ReferralFriendStage.fromWire('EARNING'),
        ReferralFriendStage.qualified);
    expect(ReferralFriendStage.fromWire('CARD_ISSUED'),
        ReferralFriendStage.cardIssued);
  });
}

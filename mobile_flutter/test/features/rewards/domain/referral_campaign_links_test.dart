// Campaign links (contract 2026-09-15, blueprint p27): the member's tracking
// records. These cases pin what the app decides on its own — the parser's
// tolerance of both spellings and missing fields, the status a link reads
// as once its expiry has passed, which actions each status allows, the
// form rules that mirror the platform's code rules, and the request body
// the facade receives — and that a link never carries a rate.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

final _now = DateTime.utc(2026, 9, 15, 12);

Map<String, dynamic> _link({Map<String, Object?> over = const {}}) => {
      'id': 'link-1',
      'programId': 'prog-1',
      'programName': 'Partners',
      'name': 'Autumn newsletter',
      'code': 'AUTUMN26',
      'channel': 'EMAIL',
      'locale': 'de',
      'destination': 'signup',
      'status': 'active',
      'activeFrom': '2026-09-01T00:00:00Z',
      'expiresAt': null,
      'createdAt': '2026-09-01T08:00:00Z',
      'shareUrl': 'https://example.com/signup?ref=AUTUMN26',
      'signupCount': 8,
      'qualifiedCount': 2,
      'offerVersionId': 'ov-1',
      'suggestedCaption': 'Join me on Example and get \$3.',
      ...over,
    };

void main() {
  group('ReferralCampaignLink', () {
    test('parses camelCase and PascalCase, normalising channel and status',
        () {
      final camel = ReferralCampaignLink.fromJson(_link());
      expect(camel.id, 'link-1');
      expect(camel.channel, 'email');
      expect(camel.channelValue, ReferralCampaignChannel.email);
      expect(camel.status, ReferralCampaignLinkStatus.active);
      expect(camel.signupCount, 8);
      expect(camel.qualifiedCount, 2);
      expect(camel.shareText, 'https://example.com/signup?ref=AUTUMN26');
      expect(camel.suggestedCaption, startsWith('Join me'));

      final pascal = ReferralCampaignLink.fromJson(const {
        'Id': 'link-2',
        'Name': 'Meetup',
        'Code': 'MEETUP-1',
        'Channel': 'event',
        'Status': 'PAUSED',
        'SignupCount': -3,
      });
      expect(pascal.id, 'link-2');
      expect(pascal.status, ReferralCampaignLinkStatus.paused);
      expect(pascal.signupCount, 0, reason: 'negative counts read as none');
      expect(pascal.shareText, 'MEETUP-1', reason: 'no address: the code');
      expect(pascal.locale, 'en');
      expect(pascal.destination, 'signup');
    });

    test('an unknown status parses without throwing', () {
      final link = ReferralCampaignLink.fromJson(_link(over: {'status': 'X'}));
      expect(link.status, ReferralCampaignLinkStatus.unknown);
      expect(ReferralCampaignLinkStatus.fromWire(''),
          ReferralCampaignLinkStatus.unknown);
    });

    test('a passed expiry reads as expired; archived stays archived', () {
      final live = ReferralCampaignLink.fromJson(_link());
      expect(live.effectiveStatus(_now), ReferralCampaignLinkStatus.active);
      expect(live.isActive(_now), isTrue);

      final expired = ReferralCampaignLink.fromJson(
          _link(over: {'expiresAt': '2026-09-01T00:00:00Z'}));
      expect(expired.effectiveStatus(_now), ReferralCampaignLinkStatus.expired);
      expect(expired.isActive(_now), isFalse);

      final future = ReferralCampaignLink.fromJson(
          _link(over: {'expiresAt': '2026-10-01T00:00:00Z'}));
      expect(future.isActive(_now), isTrue);

      final archived = ReferralCampaignLink.fromJson(_link(
          over: {'status': 'ARCHIVED', 'expiresAt': '2026-09-01T00:00:00Z'}));
      expect(
          archived.effectiveStatus(_now), ReferralCampaignLinkStatus.archived);
    });

    test('actions follow the lifecycle', () {
      final active = ReferralCampaignLink.fromJson(_link());
      expect(active.canPause(_now), isTrue);
      expect(active.canResume(_now), isFalse);
      expect(active.canArchive(_now), isTrue);

      final paused =
          ReferralCampaignLink.fromJson(_link(over: {'status': 'PAUSED'}));
      expect(paused.canPause(_now), isFalse);
      expect(paused.canResume(_now), isTrue);
      expect(paused.canArchive(_now), isTrue);

      final expired = ReferralCampaignLink.fromJson(
          _link(over: {'expiresAt': '2026-09-01T00:00:00Z'}));
      expect(expired.canPause(_now), isFalse);
      expect(expired.canResume(_now), isFalse);
      expect(expired.canArchive(_now), isTrue);

      final archived =
          ReferralCampaignLink.fromJson(_link(over: {'status': 'ARCHIVED'}));
      expect(archived.canArchive(_now), isFalse);
    });

    test('sorts newest first, archived last, undated at the end', () {
      final links = [
        ReferralCampaignLink.fromJson(
            _link(over: {'id': 'old', 'createdAt': '2026-08-01T00:00:00Z'})),
        ReferralCampaignLink.fromJson(_link(over: {
          'id': 'gone',
          'status': 'ARCHIVED',
          'createdAt': '2026-09-10T00:00:00Z',
        })),
        ReferralCampaignLink.fromJson(
            _link(over: {'id': 'undated', 'createdAt': null})),
        ReferralCampaignLink.fromJson(
            _link(over: {'id': 'new', 'createdAt': '2026-09-05T00:00:00Z'})),
      ];
      expect(
        sortReferralCampaignLinks(links, _now).map((link) => link.id),
        ['new', 'old', 'undated', 'gone'],
      );
      expect(activeReferralCampaignLinks(links, _now).map((l) => l.id),
          ['old', 'undated', 'new']);
    });
  });

  group('ReferralCampaignLinkPerformance', () {
    test('parses the contract figures and an empty body as zeros', () {
      final figures = ReferralCampaignLinkPerformance.fromJson(const {
        'Signups': 12,
        'Verified': 9,
        'Qualified': 4,
        'Earning': 3,
        'RewardsAccrued': 18.5,
        'RewardsPaid': 10,
        'Currency': 'USD',
      });
      expect(figures.signups, 12);
      expect(figures.verified, 9);
      expect(figures.qualified, 4);
      expect(figures.earning, 3);
      expect(figures.rewardsAccrued, 18.5);
      expect(figures.rewardsPaid, 10);
      expect(figures.isEmpty, isFalse);

      final empty = ReferralCampaignLinkPerformance.fromJson(const {});
      expect(empty.isEmpty, isTrue);
      expect(empty.currency, 'USD');
    });
  });

  group('analytics campaigns', () {
    test('parses campaign rows and drops rows without an identity', () {
      final analytics = ReferralMemberAnalytics.fromJson(const {
        'range': '30d',
        'campaigns': [
          {
            'linkId': 'link-1',
            'name': 'Autumn newsletter',
            'code': 'AUTUMN26',
            'signups': 5,
            'qualified': 2,
            'rewardsAccrued': 6.25,
          },
          {'name': 'nameless', 'signups': 1},
        ],
      });
      expect(analytics.campaigns, hasLength(1));
      final row = analytics.campaigns.single;
      expect(row.linkId, 'link-1');
      expect(row.code, 'AUTUMN26');
      expect(row.signups, 5);
      expect(row.qualified, 2);
      expect(row.rewardsAccrued, 6.25);
    });

    test('an older platform sends no campaigns', () {
      expect(ReferralMemberAnalytics.fromJson(const {}).campaigns, isEmpty);
    });
  });

  group('creation rules', () {
    test('name is 1–80 characters after trimming', () {
      expect(referralCampaignNameError('  '), isNotNull);
      expect(referralCampaignNameError(null), isNotNull);
      expect(referralCampaignNameError(' Autumn '), isNull);
      expect(referralCampaignNameError('a' * 80), isNull);
      expect(referralCampaignNameError('a' * 81), isNotNull);
    });

    test('a custom code is optional, 6–24 of [A-Za-z0-9_-], not reserved',
        () {
      expect(referralCampaignCodeError(''), isNull);
      expect(referralCampaignCodeError(null), isNull);
      expect(referralCampaignCodeError('autumn-26'), isNull);
      expect(referralCampaignCodeError('AB_12'), isNotNull, reason: 'short');
      expect(referralCampaignCodeError('a' * 25), isNotNull, reason: 'long');
      expect(referralCampaignCodeError('has space'), isNotNull);
      expect(referralCampaignCodeError('naïve1'), isNotNull);
      expect(referralCampaignCodeError('signup'), isNotNull);
      expect(referralCampaignCodeError('ADMIN'), isNotNull);
    });

    test('an expiry has to be in the future', () {
      expect(referralCampaignExpiryError(null, _now), isNull);
      expect(referralCampaignExpiryError(_now, _now), isNotNull);
      expect(
          referralCampaignExpiryError(
              _now.add(const Duration(days: 1)), _now),
          isNull);
    });

    test('the request body carries only what was given, code upper-cased',
        () {
      const full = ReferralCampaignLinkDraft(
        name: ' Autumn newsletter ',
        channel: ReferralCampaignChannel.email,
        programId: 'prog-1',
        code: ' autumn26 ',
        locale: 'de',
      );
      expect(full.toJson(), {
        'programId': 'prog-1',
        'name': 'Autumn newsletter',
        'channel': 'email',
        'code': 'AUTUMN26',
        'locale': 'de',
      });
      final dated = ReferralCampaignLinkDraft(
        name: 'Meetup',
        channel: ReferralCampaignChannel.event,
        expiresAt: DateTime.utc(2026, 12, 31),
      );
      expect(dated.toJson(), {
        'name': 'Meetup',
        'channel': 'event',
        'expiresAt': '2026-12-31T00:00:00.000Z',
      });
      expect(dated.toJson().containsKey('code'), isFalse);
      expect(dated.toJson().keys, isNot(contains('rate')));
    });

    test('programme choices: the summary first, then those links add', () {
      final summary = ReferralSummary.fromJson(const {
        'programId': 'prog-1',
        'programName': 'Public',
      });
      final links = [
        ReferralCampaignLink.fromJson(_link(over: {'programName': ''})),
        ReferralCampaignLink.fromJson(_link(
            over: {'id': 'l2', 'programId': 'prog-2', 'programName': 'VIP'})),
        ReferralCampaignLink.fromJson(_link(over: {'id': 'l3', 'programId': null})),
      ];
      expect(referralCampaignProgrammes(summary, links), [
        (id: 'prog-1', name: 'Public'),
        (id: 'prog-2', name: 'VIP'),
      ]);
      expect(referralCampaignProgrammes(const ReferralSummary(), const []),
          isEmpty);
    });
  });

  group('clicks and destinations (addendum A)', () {
    test('a link carries click counters only once the platform sends them',
        () {
      final tracked = ReferralCampaignLink.fromJson(
          _link(over: {'clickCount': 40, 'uniqueClickCount': 32}));
      expect(tracked.clicksTracked, isTrue);
      expect(tracked.clickCount, 40);
      expect(tracked.uniqueClickCount, 32);
      expect(tracked.clickToSignupRate, 0.25);

      final pascal = ReferralCampaignLink.fromJson(
          _link(over: {'ClickCount': '3', 'UniqueClickCount': -1}));
      expect(pascal.clicksTracked, isTrue);
      expect(pascal.clickCount, 3);
      expect(pascal.uniqueClickCount, 0);
      expect(pascal.clickToSignupRate, isNull, reason: 'no unique click yet');

      final older = ReferralCampaignLink.fromJson(_link());
      expect(older.clicksTracked, isFalse);
      expect(older.clickCount, 0);
      expect(older.clickToSignupRate, isNull);
    });

    test('rate is sign-ups per unique click at 4 dp, formatted as a percent',
        () {
      expect(referralClickToSignupRate(8, 32), 0.25);
      expect(referralClickToSignupRate(1, 3), 0.3333);
      expect(referralClickToSignupRate(0, 5), 0);
      expect(referralClickToSignupRate(5, 0), isNull);
      expect(formatReferralRate(0.25), '25%');
      expect(formatReferralRate(0.3333), '33.3%');
      expect(formatReferralRate(0), '0%');
      expect(formatReferralRate(1.5), '150%');
      expect(formatReferralRate(null), isNull);
    });

    test('performance takes the platform rate, computes it otherwise', () {
      final served = ReferralCampaignLinkPerformance.fromJson({
        'signups': 8,
        'clicks': 40,
        'uniqueClicks': 32,
        'clickToSignupRate': 0.2513,
      });
      expect(served.clicksTracked, isTrue);
      expect(served.clicks, 40);
      expect(served.uniqueClicks, 32);
      expect(served.clickToSignupRate, 0.2513);
      expect(served.isEmpty, isFalse);

      final computed = ReferralCampaignLinkPerformance.fromJson(
          {'Signups': 2, 'Clicks': 10, 'UniqueClicks': 8});
      expect(computed.clickToSignupRate, 0.25);

      final noVisitors = ReferralCampaignLinkPerformance.fromJson(
          {'signups': 0, 'clicks': 0, 'uniqueClicks': 0, 'clickToSignupRate': null});
      expect(noVisitors.clickToSignupRate, isNull);
      expect(noVisitors.isEmpty, isTrue);

      final clicksOnly = ReferralCampaignLinkPerformance.fromJson(
          {'signups': 0, 'clicks': 3, 'uniqueClicks': 3});
      expect(clicksOnly.isEmpty, isFalse, reason: 'a visit is a figure');

      final older = ReferralCampaignLinkPerformance.fromJson({'signups': 4});
      expect(older.clicksTracked, isFalse);
      expect(older.clicks, 0);
      expect(older.clickToSignupRate, isNull);
    });

    test('analytics campaign rows carry clicks, zero when absent', () {
      final row = ReferralCampaignRow.fromJson(
          {'linkId': 'l1', 'code': 'A', 'clicks': 12, 'signups': 3});
      expect(row.clicks, 12);
      expect(ReferralCampaignRow.fromJson({'linkId': 'l1'}).clicks, 0);
    });

    test('destinations are the allowlist with human labels', () {
      expect(ReferralCampaignDestination.values.map((d) => d.wire),
          ['signup', 'home', 'cards', 'topup', 'rewards']);
      expect(ReferralCampaignDestination.fromWire(' Cards '),
          ReferralCampaignDestination.cards);
      expect(ReferralCampaignDestination.fromWire('login'), isNull);
      expect(ReferralCampaignDestination.fromWire(null), isNull);
      expect(ReferralCampaignDestination.topup.label, 'Add money');
      expect(ReferralCampaignDestination.signup.label, 'Sign-up page');
      expect(ReferralCampaignDestination.home.label, 'Home after sign-up');
      expect(
        ReferralCampaignLink.fromJson(_link(over: {'destination': 'TOPUP'}))
            .destinationValue,
        ReferralCampaignDestination.topup,
      );
    });

    test('the draft sends the destination word, or nothing for the default',
        () {
      const withDestination = ReferralCampaignLinkDraft(
        name: 'Autumn',
        channel: ReferralCampaignChannel.email,
        destination: ReferralCampaignDestination.rewards,
      );
      expect(withDestination.toJson()['destination'], 'rewards');
      const plain = ReferralCampaignLinkDraft(
        name: 'Autumn',
        channel: ReferralCampaignChannel.email,
      );
      expect(plain.toJson().containsKey('destination'), isFalse);
    });

    test('the referral check says what kind of code it was and where it leads',
        () {
      final campaign = ReferralWelcome.fromJson({
        'valid': true,
        'kind': 'campaign_link',
        'destination': 'Cards',
        'welcomeAmount': 3,
      });
      expect(campaign.isCampaignLink, isTrue);
      expect(campaign.kind, 'CAMPAIGN_LINK');
      expect(campaign.destination, 'cards');

      final personal =
          ReferralWelcome.fromJson({'valid': true, 'kind': 'PERSONAL'});
      expect(personal.isCampaignLink, isFalse);
      expect(personal.destination, isNull);

      final older = ReferralWelcome.fromJson({'valid': true});
      expect(older.isCampaignLink, isFalse, reason: 'no kind = personal');
      expect(const ReferralWelcome.inactiveCampaignLink().isCampaignLink,
          isFalse);
    });
  });

  group('inactive campaign link answer', () {
    test('is read from the code, the detail or a raw platform body', () {
      expect(isReferralCampaignLinkInactive(const {
        'code': 'auth.referral.campaign_link_inactive',
        'detail': 'CAMPAIGN_LINK_INACTIVE',
      }), isTrue);
      expect(
          isReferralCampaignLinkInactive(
              '{"code":"CAMPAIGN_LINK_INACTIVE","message":"Link paused"}'),
          isTrue);
      expect(isReferralCampaignLinkInactive(const {'code': 'REFERRAL_UNKNOWN'}),
          isFalse);
      expect(isReferralCampaignLinkInactive(null), isFalse);
      const welcome = ReferralWelcome.inactiveCampaignLink();
      expect(welcome.valid, isFalse);
      expect(welcome.campaignLinkInactive, isTrue);
      expect(ReferralWelcome.fromJson(const {'valid': true}).campaignLinkInactive,
          isFalse);
    });
  });
}

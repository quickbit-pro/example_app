// The referral programme v2 on the Rewards screen.
//
// Four things the platform change put on this page, each pinned because each
// is easy to lose in a refactor: the offer leads and is built from the API's
// own figures; the terms gate stands where the invite card will be until the
// current version is accepted, and accepting it is one round trip; the ledger
// is grouped by delivery stage under the minimum-credit sentence; and the
// voucher panels are only mounted when the programme actually delivers
// vouchers. The friends list and the level card ride along.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/rewards_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _exampleBranding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

const _tenantBranding = AppBranding(
  appName: 'Hoppa',
  brandId: 'generic',
  primarySeedHex: '7C5CFF',
  accentSeedHex: '2DD4BF',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'Hoppa',
);

const _config = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: true,
  referralRegistrationMode: 'optional',
  vouchersEnabled: true,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: false,
  walletOutflowsEnabled: false,
  equalsMoneyEnabled: true,
);

const _offer = {
  'welcomeAmount': 3,
  'welcomeCurrency': 'USD',
  'qualificationCalculationType': 'FIXED',
  'qualificationRate': 1,
  'topupCalculationType': 'PERCENT_OF_TOPUP',
  'topupRate': 0.25,
  'earningWindowDays': 365,
  'requiresKyc': true,
  'requiresPaidCard': true,
  'requiresTopup': true,
};

/// A wallet-credit programme with terms already accepted: the everyday case.
Map<String, dynamic> _summary({
  String deliveryMode = 'WALLET_CREDIT',
  bool termsAccepted = true,
  List<Map<String, Object>> levels = const [
    {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
  ],
  double minimumCreditAmount = 5,
  double accumulated = 2.5,
  String? programDescription,
  Map<String, Object?> progress = const {'currentValue': 3, 'nextThreshold': 5},
}) =>
    {
      'enabled': true,
      'referralCode': termsAccepted ? 'EXAMPLE28' : null,
      'referralPath': termsAccepted ? 'https://example.com/r/EXAMPLE28' : null,
      'currentLevel': levels.first,
      'levels': levels,
      'progress': progress,
      'referrals': {
        'invited': 8,
        'qualified': 3,
        'inProgress': 2,
        'earning': 3
      },
      'rewards': {
        'pending': 2,
        'ready': 1,
        'crediting': 0.5,
        'paid': 10,
        'failed': 0,
        'currency': 'USD',
      },
      'offer': _offer,
      'terms': {
        'version': 2,
        'text': 'Programme terms: rewards are paid at qualification.',
        'privacyNotice': 'Your inviter sees a pseudonym for you.',
        'accepted': termsAccepted,
      },
      'deliveryMode': deliveryMode,
      'minimumCreditAmount': minimumCreditAmount,
      'accumulatedTowardsCredit': accumulated,
      'programName': 'Example referrals',
      'programDescription': programDescription,
      'canInvite': true,
    };

/// What the tenant wrote in the programme's Description, in words the
/// generated sentence could not have produced.
const _tenantWording =
    'Your friend gets \$3 the moment they verify. You get \$1, and a quarter '
    'of a percent of everything they load for a year.';

/// The sentence the app builds from the offer's flags when the tenant wrote
/// nothing.
const _generatedDetail =
    'Paid once your friend verifies their identity, gets a paid card and '
    'makes their first top-up.';

final _rewards = [
  for (final (stage, amount, day) in [
    ('PENDING', 2.0, 5),
    ('READY', 1.0, 4),
    ('CREDITING', 0.5, 3),
    ('PAID', 10.0, 2),
  ])
    ReferralReward.fromJson({
      'eventType': stage == 'PAID' ? 'QUALIFICATION' : 'CARD_TOPUP',
      'amount': amount,
      'currency': 'USD',
      'stage': stage,
      'friendAlias': 'user-A1B2C',
      'occurredAt': '2026-09-0${day}T10:00:00Z',
    }),
];

final _friends = [
  ReferralFriend.fromJson(const {
    'alias': 'user-A1B2C',
    'stage': 'QUALIFIED',
    'attributedAt': '2026-08-01T00:00:00Z',
    'earnedAmount': 4.5,
    'currency': 'USD',
    'recipientName': 'Maja',
  }),
  ReferralFriend.fromJson(const {
    'alias': 'user-Z9Y8X',
    'stage': 'VERIFYING',
    'attributedAt': '2026-08-20T00:00:00Z',
    'earnedAmount': 0,
    'currency': 'USD',
  }),
];

/// Records terms acceptances; the snapshot the provider serves is swapped by
/// the test so the reload after acceptance shows the unlocked page.
class _FakeApi extends MobilePlatformApi {
  _FakeApi() : super(Dio());

  final accepted = <int>[];
  void Function()? onAccept;

  @override
  Future<ActionResult> acceptReferralTerms(int termsVersion) async {
    accepted.add(termsVersion);
    onAccept?.call();
    return const ActionResult(message: 'Terms accepted');
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required RewardsSnapshot Function() snapshot,
  AppBranding branding = _exampleBranding,
  _FakeApi? api,
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final themes = buildAppThemes(branding);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rewardsSnapshotProvider.overrideWith((ref) async => snapshot()),
        if (api != null) mobilePlatformApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: themes.dark,
        themeMode: ThemeMode.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            disableAnimations: true,
          ),
          child: const RewardsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _offstage(Key key) => find.byKey(key, skipOffstage: false);

/// Scrolls the page so the widget with [key] sits mid-viewport, where a tap
/// lands on it rather than on the app bar or below the fold.
Future<void> _centre(WidgetTester tester, Key key) async {
  await Scrollable.ensureVisible(
    tester.element(_offstage(key)),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
}

/// What the Example offer card states from [_offer]: both rewards, the three
/// steps, the window.
void _expectExampleOffer(WidgetTester tester) {
  expect(
    tester.widget<Text>(find.byKey(const Key('referral_offer_friend'))).data,
    r'Friend gets $3',
  );
  expect(
    tester.widget<Text>(find.byKey(const Key('referral_offer_you'))).data,
    r'You get $1 + 0.25% of eligible credited top-ups',
  );
  expect(find.text('How your friend qualifies'), findsOneWidget);
  expect(find.text('Verify their identity'), findsOneWidget);
  expect(find.text('Get a paid card'), findsOneWidget);
  expect(find.text('Make a first eligible external top-up'), findsOneWidget);
  expect(find.text('0.25% for 365 days'), findsOneWidget);
}

void main() {
  for (final branding in [_exampleBranding, _tenantBranding]) {
    final example = branding.brandId == 'example';
    group('offer headline (${branding.brandId})', () {
      testWidgets('leads with the offer built from the API figures',
          (tester) async {
        await _pump(
          tester,
          branding: branding,
          snapshot: () => RewardsSnapshot(
            config: _config,
            referralSummary: _summary(),
          ),
        );

        expect(tester.takeException(), isNull);
        if (example) {
          // The Example card: both rewards on their own lines, the checklist
          // the friend meets, the window — every figure the API's.
          _expectExampleOffer(tester);
          return;
        }
        final headline = tester.widget<Text>(
          find.byKey(const Key('referral_offer_headline')),
        );
        expect(headline.data, r'$3 for them. $1 + 0.25% for you.');
        expect(find.textContaining(_generatedDetail), findsOneWidget);
        expect(
          find.textContaining('Then 0.25% of every top-up for 365 days.'),
          findsOneWidget,
        );
      });

      testWidgets("explains the offer in the tenant's own words when it has",
          (tester) async {
        await _pump(
          tester,
          branding: branding,
          snapshot: () => RewardsSnapshot(
            config: _config,
            referralSummary: _summary(programDescription: _tenantWording),
          ),
        );

        expect(tester.takeException(), isNull);
        // Marketing copy supplements the mandatory qualification conditions.
        if (example) {
          _expectExampleOffer(tester);
          expect(
            tester
                .widget<Text>(find.byKey(const Key('referral_offer_description')))
                .data,
            _tenantWording,
          );
          return;
        }
        final headline = tester.widget<Text>(
          find.byKey(const Key('referral_offer_headline')),
        );
        expect(headline.data, r'$3 for them. $1 + 0.25% for you.');
        final detail = tester.widget<Text>(
          find.byKey(const Key('referral_offer_detail')),
        );
        expect(detail.data, contains(_tenantWording));
        expect(find.textContaining(_generatedDetail), findsOneWidget);
        expect(
          find.textContaining('Then 0.25% of every top-up'),
          findsOneWidget,
        );
      });

      testWidgets(
          'falls back to the generated sentence for a blank description',
          (tester) async {
        await _pump(
          tester,
          branding: branding,
          snapshot: () => RewardsSnapshot(
            config: _config,
            referralSummary: _summary(programDescription: '   '),
          ),
        );

        expect(tester.takeException(), isNull);
        if (example) {
          _expectExampleOffer(tester);
          expect(find.byKey(const Key('referral_offer_description')),
              findsNothing);
          return;
        }
        final detail = tester.widget<Text>(
          find.byKey(const Key('referral_offer_detail')),
        );
        expect(detail.data, contains(_generatedDetail));
        expect(detail.data, contains('Then 0.25% of every top-up'));
      });
    });
  }

  group('terms gate', () {
    testWidgets('stands in for the invite until accepted, then unlocks',
        (tester) async {
      final api = _FakeApi();
      var accepted = false;
      api.onAccept = () => accepted = true;
      await _pump(
        tester,
        api: api,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(termsAccepted: accepted),
        ),
      );

      expect(find.byKey(const Key('referral_terms_gate')), findsOneWidget);
      expect(find.text('Before you share'), findsOneWidget);
      expect(
        find.text('Programme terms: rewards are paid at qualification.'),
        findsOneWidget,
      );
      expect(
          find.text('Your inviter sees a pseudonym for you.'), findsOneWidget);
      // No code, no link, no share: nothing to share yet.
      expect(_offstage(const Key('referral_terms_gate')), findsOneWidget);
      expect(find.text('INVITE CODE', skipOffstage: false), findsNothing);
      expect(_offstage(const Key('referral_copy_link')), findsNothing);
      expect(_offstage(const Key('referral_share')), findsNothing);

      // The button waits for the tick.
      await _centre(tester, const Key('referral_terms_accept'));
      await tester.tap(find.byKey(const Key('referral_terms_accept')));
      await tester.pumpAndSettle();
      expect(api.accepted, isEmpty);

      await _centre(tester, const Key('referral_terms_checkbox'));
      await tester.tap(find.byKey(const Key('referral_terms_checkbox')));
      await tester.pumpAndSettle();
      await _centre(tester, const Key('referral_terms_accept'));
      await tester.tap(find.byKey(const Key('referral_terms_accept')));
      await tester.pumpAndSettle();

      // One acceptance at the published version, then the reload carries
      // the code and the gate is gone.
      expect(api.accepted, [2]);
      expect(find.text('Terms accepted. You can share your invite now.'),
          findsOneWidget);
      expect(_offstage(const Key('referral_terms_gate')), findsNothing);
      expect(find.text('INVITE CODE', skipOffstage: false), findsOneWidget);
      expect(_offstage(const Key('referral_copy_link')), findsOneWidget);
      expect(_offstage(const Key('referral_share')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is not shown when the current terms are accepted',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
        ),
      );

      expect(_offstage(const Key('referral_terms_gate')), findsNothing);
      expect(find.text('INVITE CODE', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a white-label tenant gets the same gate in its own tree',
        (tester) async {
      await _pump(
        tester,
        branding: _tenantBranding,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(termsAccepted: false),
        ),
      );

      expect(_offstage(const Key('referral_terms_gate')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Accept and continue'),
          findsOneWidget);
      expect(
          find.text('Your referral code', skipOffstage: false), findsNothing);
      expect(find.text('Email invite', skipOffstage: false), findsNothing);
    });
  });

  group('rewards ledger', () {
    testWidgets('shows the three most recent rewards with where each stands',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralRewards: _rewards,
        ),
      );

      // Delivery is stated on the offer card, in the programme's own terms:
      // the minimum the wallet credits at.
      final sentence = tester.widget<Text>(
        _offstage(const Key('referral_minimum_credit')),
      );
      expect(
        sentence.data,
        r'Rewards are added to your USD balance automatically once they '
        r'reach $5.',
      );

      await tester.scrollUntilVisible(
        _offstage(const Key('referral_rewards')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent rewards'), findsOneWidget);
      // Newest first, three of the four: the paid qualification on day 2 is
      // the oldest and waits for the full ledger behind "See all".
      expect(find.text('Top-up commission', skipOffstage: false),
          findsNWidgets(3));
      expect(find.text('Friend qualified', skipOffstage: false), findsNothing);
      expect(find.text(r'$2.00', skipOffstage: false), findsOneWidget);
      expect(find.text(r'$1.00', skipOffstage: false), findsOneWidget);
      expect(find.text(r'$0.50', skipOffstage: false), findsOneWidget);
      // Where each stands, in the copy contract's words: a pending reward
      // never reads as paid.
      expect(find.text('Pending', skipOffstage: false), findsOneWidget);
      expect(find.text('Crediting', skipOffstage: false), findsNWidgets(2));
      expect(find.textContaining('Added to', skipOffstage: false),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so when nothing has been earned yet', (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: {
            ..._summary(accumulated: 0),
            'rewards': {
              'pending': 0,
              'ready': 0,
              'crediting': 0,
              'paid': 0,
              'failed': 0,
              'currency': 'USD',
            },
          },
        ),
      );

      expect(_offstage(const Key('referral_rewards_empty')), findsOneWidget);
      expect(_offstage(const Key('referral_rewards_pending')), findsNothing);
      expect(_offstage(const Key('referral_accumulated')), findsNothing);
    });
  });

  group('voucher sections', () {
    testWidgets('are not mounted for a wallet-credit programme',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          voucherStatus: const {'enabled': true},
        ),
      );

      expect(find.text('REWARDS EARNED'), findsOneWidget);
      // The list builds lazily, so the absence is only meaningful once the
      // last section — the funnel — has been built.
      await tester.scrollUntilVisible(
        find.text('Converted', skipOffstage: false),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_offstage(const Key('rewards_voucher_sections')), findsNothing);
      expect(find.text('VOUCHER CODE', skipOffstage: false), findsNothing);
      expect(find.text('Vouchers are not available', skipOffstage: false),
          findsNothing);
    });

    for (final mode in ['AUTOMATIC_TRANSFER', 'VOUCHER_PER_COMMISSION']) {
      testWidgets('are mounted for $mode', (tester) async {
        await _pump(
          tester,
          snapshot: () => RewardsSnapshot(
            config: _config,
            referralSummary: _summary(deliveryMode: mode),
            voucherStatus: const {'enabled': true},
            assignedVouchers: const [
              {
                'AssignmentId': 'v1',
                'Name': 'Welcome voucher',
                'Amount': 3,
                'Currency': 'USD',
                'Status': 'assigned',
                'RedemptionType': 'account_credit',
              },
            ],
          ),
        );

        expect(find.text('REWARDS AVAILABLE'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('VOUCHER CODE', skipOffstage: false),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
            _offstage(const Key('rewards_voucher_sections')), findsOneWidget);
        expect(
            find.text('Welcome voucher', skipOffstage: false), findsOneWidget);
        expect(
          _offstage(const Key('referral_voucher_delivery')),
          findsOneWidget,
        );
        expect(_offstage(const Key('referral_minimum_credit')), findsNothing);
      });
    }
  });

  group('friends', () {
    testWidgets('lists the typed name or the alias, the stage and earnings',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralFriends: _friends,
        ),
      );

      await tester.scrollUntilVisible(
        _offstage(const Key('referral_friends')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Maja'), findsOneWidget);
      expect(find.text('user-Z9Y8X'), findsOneWidget);
      expect(find.text('Verifying'), findsOneWidget);
      expect(find.text(r'$4.50'), findsOneWidget);
      expect(find.text(r'$0.00'), findsOneWidget);
      // The pseudonym is never shown for a friend the inviter named.
      expect(find.text('user-A1B2C'), findsNothing);
    });

    testWidgets('has an empty state', (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
        ),
      );

      expect(_offstage(const Key('referral_friends_empty')), findsOneWidget);
    });
  });

  group('levels', () {
    testWidgets('a single visible level shows no ladder and no level card',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
        ),
      );

      expect(_offstage(const Key('referral_levels')), findsNothing);
      expect(find.text('NEXT LEVEL', skipOffstage: false), findsNothing);
      expect(find.text('Pro', skipOffstage: false), findsNothing);
    });

    testWidgets('two visible levels show the ladder and the level card',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(levels: const [
            {
              'code': 'PRO',
              'name': 'Pro',
              'minimumMetricValue': 0,
              'qualificationRate': 1,
              'topupRate': 0.25,
            },
            {
              'code': 'ELITE',
              'name': 'Elite',
              'minimumMetricValue': 5,
              'qualificationRate': 2,
              'topupRate': 0.5,
            },
          ]),
        ),
      );

      expect(find.text('NEXT LEVEL'), findsOneWidget);
      expect(find.text('3 of 5'), findsOneWidget);
      await tester.scrollUntilVisible(
        _offstage(const Key('referral_levels')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Elite'), findsOneWidget);
      expect(
        find.text(r'$2 + 0.5% · from 5 qualified referrals'),
        findsOneWidget,
      );
      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets(
        'two conditions: the rail shows the further one and the caption '
        'accounts for both', (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(
            levels: const [
              {
                'code': 'PRO',
                'name': 'Pro',
                'minimumMetricValue': 0,
                'qualificationRate': 1,
                'topupRate': 0.25,
              },
              {
                'code': 'ELITE',
                'name': 'Elite',
                'minimumMetricValue': 5,
                'minimumQualifiedReferrals': 5,
                'minimumTopupVolume': 2000,
                'qualificationRate': 2,
                'topupRate': 0.5,
              },
              {
                'code': 'WHALE',
                'name': 'Whale',
                'minimumMetricValue': 0,
                'minimumTopupVolume': 10000,
                'qualificationRate': 2,
                'topupRate': 0.5,
              },
            ],
            // 3 of 5 referrals (60%) but only $1,400 of $2,000 (70%): the
            // referrals condition is further from met, so the rail shows it.
            progress: const {
              'basis': 'SUCCESSFUL_REFERRAL_COUNT',
              'currentValue': 3,
              'nextThreshold': 5,
              'remaining': 2,
              'qualifiedReferrals': 3,
              'topupVolume': 1400,
              'topupVolumeCurrency': 'USD',
              'nextMinimumQualifiedReferrals': 5,
              'nextMinimumTopupVolume': 2000,
              'remainingQualifiedReferrals': 2,
              'remainingTopupVolume': 600,
            },
          ),
        ),
      );

      expect(find.text('NEXT LEVEL'), findsOneWidget);
      expect(find.text('3 of 5'), findsOneWidget);
      expect(find.text(r'2 more referrals · $600 more in top-ups'),
          findsOneWidget);
      await tester.scrollUntilVisible(
        _offstage(const Key('referral_levels')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(r'$1 + 0.25% · starting level'), findsOneWidget);
      expect(
        find.text(
            r'$2 + 0.5% · from 5 qualified referrals and $2,000 in top-ups'),
        findsOneWidget,
      );
      expect(find.text(r'$2 + 0.5% · from $10,000 in top-ups'), findsOneWidget);
    });

    testWidgets('a top-up-only next level measures money on the rail',
        (tester) async {
      await _pump(
        tester,
        snapshot: () => RewardsSnapshot(
          config: _config,
          referralSummary: _summary(
            levels: const [
              {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
              {
                'code': 'ELITE',
                'name': 'Elite',
                'minimumMetricValue': 0,
                'minimumTopupVolume': 2000,
              },
            ],
            progress: const {
              'currentValue': 3,
              'nextThreshold': null,
              'qualifiedReferrals': 3,
              'topupVolume': 1400,
              'nextMinimumTopupVolume': 2000,
              'remainingTopupVolume': 600,
            },
          ),
        ),
      );

      expect(find.text(r'$1,400 of $2,000'), findsOneWidget);
      expect(find.text(r'$600 more to go'), findsOneWidget);
    });
  });
}

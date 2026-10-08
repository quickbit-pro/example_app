// The phone's Invite & Earn summary (blueprint p18, p20).
//
// What the customer instruction pins for the phone: the main summaries. Four
// figures that answer "how is it going", an offer a customer could explain to
// a friend, the three most recent friends and rewards, and a way into each
// full list. Each case here is something a refactor could quietly lose: a
// tile printing the wrong total, the checklist dropping a step the offer
// requires, "See all" going nowhere, a pending reward reading as paid, or
// "Load more" replacing the page instead of appending to it.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_copy.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_earnings_screen.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_friends_screen.dart';
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

const _config = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: true,
  referralRegistrationMode: 'optional',
  vouchersEnabled: false,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: false,
  walletOutflowsEnabled: false,
  equalsMoneyEnabled: true,
);

/// The public Example offer as the blueprint states it: $3 for the friend,
/// $1 + 0.25% for the inviter, 90 days, $5,000 of eligible volume, a $10
/// first top-up.
const _offer = {
  'welcomeAmount': 3,
  'welcomeCurrency': 'USD',
  'qualificationCalculationType': 'FIXED',
  'qualificationRate': 1,
  'topupCalculationType': 'PERCENT_OF_TOPUP',
  'topupRate': 0.25,
  'earningWindowDays': 90,
  'maxEligibleVolumePerRelationship': 5000,
  'requiresKyc': true,
  'requiresPaidCard': true,
  'requiresTopup': true,
  'minimumTopup': 10,
};

Map<String, dynamic> _summary({
  String deliveryMode = 'WALLET_CREDIT',
  String? programDescription,
}) =>
    {
      'enabled': true,
      'referralCode': 'EXAMPLE28',
      'referralPath': 'https://example.com/r/EXAMPLE28',
      'currentLevel': {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
      'levels': [
        {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
      ],
      'progress': {'currentValue': 3, 'nextThreshold': 5},
      'referrals': {
        'invited': 8,
        'qualified': 3,
        'inProgress': 2,
        'earning': 3,
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
        'accepted': true,
        'acceptedVersion': 2,
        'acceptedAt': '2026-08-01T09:00:00Z',
      },
      'deliveryMode': deliveryMode,
      'minimumCreditAmount': 0,
      'accumulatedTowardsCredit': 0,
      'programId': 'prog-1',
      'programName': 'Example referrals',
      'programDescription': programDescription,
      'canInvite': true,
    };

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
      if (stage == 'PAID') 'paidAt': '2026-09-02T12:00:00Z',
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
    'earningUntil': '2099-01-01T00:00:00Z',
  }),
  ReferralFriend.fromJson(const {
    'alias': 'user-Z9Y8X',
    'stage': 'VERIFYING',
    'attributedAt': '2026-08-20T00:00:00Z',
    'earnedAmount': 0,
    'currency': 'USD',
  }),
];

/// A full first page of friends, so the list has a next page to load.
List<ReferralFriend> _fullPage(int size) => [
      for (var i = 0; i < size; i++)
        ReferralFriend.fromJson({
          'alias': 'user-P1-$i',
          'stage': 'INVITED',
          'attributedAt': '2026-07-01T00:00:00Z',
          'earnedAmount': 0,
          'currency': 'USD',
        }),
    ];

/// Serves the friends and rewards pages a test hands it, and records which
/// pages were asked for.
class _FakeApi extends MobilePlatformApi {
  _FakeApi() : super(Dio());

  final friendPages = <int>[];
  List<ReferralFriend> Function(int page)? friendsPage;

  @override
  Future<List<ReferralFriend>> getReferralFriends({
    String? programId,
    int page = 1,
    int pageSize = 50,
  }) async {
    friendPages.add(page);
    return friendsPage?.call(page) ?? const [];
  }
}

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  required RewardsSnapshot snapshot,
  _FakeApi? api,
  String initialLocation = '/rewards',
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/rewards',
        builder: (context, state) => const RewardsScreen(),
        routes: [
          GoRoute(
            path: 'friends',
            builder: (context, state) => const ReferralFriendsScreen(),
          ),
          GoRoute(
            path: 'earnings',
            builder: (context, state) => ReferralEarningsScreen(
              initialFilter: ReferralEarningsFilter.fromWire(
                state.uri.queryParameters['status'],
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  final themes = buildAppThemes(_exampleBranding);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rewardsSnapshotProvider.overrideWith((ref) async => snapshot),
        if (api != null) mobilePlatformApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp.router(
        theme: themes.dark,
        themeMode: ThemeMode.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

Finder _offstage(Key key) => find.byKey(key, skipOffstage: false);

/// Text on the earnings screen only, whether or not it has scrolled into
/// view: the Rewards page underneath it in the stack is not counted.
Finder _onEarnings(String text) => find.descendant(
      of: find.byType(ReferralEarningsScreen, skipOffstage: false),
      matching: find.text(text, skipOffstage: false),
    );

/// Brings [finder] into the viewport and gives the layout a frame, so a tap
/// lands on current geometry rather than the pre-scroll one.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone explains residence restriction and hides invitations', (tester) async {
    await _pumpApp(tester, snapshot: RewardsSnapshot(
      config: _config,
      referralSummary: {
        ..._summary(),
        'canInvite': false,
        'participationEligibility': {'status': 'INELIGIBLE', 'reason': 'GEO_RESIDENCE_EXCLUDED'},
      },
      referralRewards: const [],
      referralFriends: const [],
    ));
    expect(find.text('Referral participation unavailable', skipOffstage: false), findsOneWidget);
    expect(find.text('Invite friends', skipOffstage: false), findsNothing);
    expect(find.text('Share invite', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
  group('Invite & Earn tiles', () {
    testWidgets('carry the four summary figures', (tester) async {
      await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
        ),
      );

      expect(tester.takeException(), isNull);
      final tiles = _offstage(const Key('referral_summary_tiles'));
      expect(tiles, findsOneWidget);
      Finder inTiles(String text) => find.descendant(
            of: tiles,
            matching: find.text(text, skipOffstage: false),
          );
      // Qualified friends is the funnel's qualified count; Earned is
      // everything not lost; Awaiting credit is pending + ready + crediting;
      // Paid to wallet is what landed.
      expect(inTiles('Qualified friends'), findsOneWidget);
      expect(inTiles('3'), findsOneWidget);
      expect(inTiles('Earned'), findsOneWidget);
      expect(inTiles(r'$13.50'), findsOneWidget);
      expect(inTiles('Awaiting credit'), findsOneWidget);
      expect(inTiles(r'$3.50'), findsOneWidget);
      expect(inTiles('Paid reward ledger'), findsOneWidget);
      expect(inTiles(r'$10.00'), findsOneWidget);
    });

    testWidgets('voucher programmes relabel the delivery tiles',
        (tester) async {
      await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(deliveryMode: 'VOUCHER_PER_COMMISSION'),
        ),
      );

      final tiles = _offstage(const Key('referral_summary_tiles'));
      Finder inTiles(String text) => find.descendant(
            of: tiles,
            matching: find.text(text, skipOffstage: false),
          );
      expect(inTiles('Ready to claim'), findsOneWidget);
      expect(inTiles('Claimed'), findsOneWidget);
      expect(inTiles('Awaiting credit'), findsNothing);
      expect(inTiles('Paid reward ledger'), findsNothing);
    });

    testWidgets('a tile opens the ledger filtered to its state',
        (tester) async {
      final router = await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralRewards: _rewards,
        ),
      );

      final awaiting = _offstage(const Key('referral_tile_awaiting'));
      await _reveal(tester, awaiting);
      await tester.tap(awaiting);
      await tester.pumpAndSettle();

      expect(_location(router), '/rewards/earnings?status=awaiting');
      expect(find.text('Earnings'), findsOneWidget);
      // The totals strip and its reporting note lead the ledger.
      expect(find.byKey(const Key('referral_totals')), findsOneWidget);
      expect(
        find.text('Figures update after provider confirmation · USD'),
        findsOneWidget,
      );
      // Only the three rows that are not yet in the balance. Scoped to the
      // ledger screen: the Rewards page underneath is still in the stack.
      expect(_onEarnings('Top-up commission'), findsNWidgets(3));
      expect(_onEarnings('Friend qualified'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Invite & Earn offer card', () {
    testWidgets('states both rewards, the checklist, the window and delivery',
        (tester) async {
      await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(
            programDescription: 'Bring a friend, both of you win.',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('referral_offer_friend')))
            .data,
        r'Friend gets $3',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_offer_you'))).data,
        r'You get $1 + 0.25% of eligible credited top-ups',
      );
      // The tenant's description sits above the numbered checklist.
      final description = find.byKey(const Key('referral_offer_description'));
      final steps = find.byKey(const Key('referral_offer_steps'));
      expect(tester.getTopLeft(description).dy,
          lessThan(tester.getTopLeft(steps).dy));
      for (final number in ['1', '2', '3']) {
        expect(find.descendant(of: steps, matching: find.text(number)),
            findsOneWidget);
      }
      expect(find.text('Verify their identity'), findsOneWidget);
      expect(find.text('Get a paid card'), findsOneWidget);
      expect(find.text(r'First eligible external top-up of at least $10'),
          findsOneWidget);
      // Window and cap on one line, delivery on the next.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('referral_offer_window')))
            .data,
        r'0.25% for 90 days, up to $5,000 in eligible credited top-ups per friend',
      );
      expect(
        find.text(
            'Wallet credits arrive automatically after provider confirmation.'),
        findsOneWidget,
      );
    });

    testWidgets('View full reward terms opens the text with its version',
        (tester) async {
      await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
        ),
      );

      final link = _offstage(const Key('referral_offer_terms_link'));
      await _reveal(tester, link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.text('Reward terms'), findsOneWidget);
      expect(
        find.text('Programme terms: rewards are paid at qualification.'),
        findsOneWidget,
      );
      final meta =
          tester.widget<Text>(find.byKey(const Key('referral_terms_meta')));
      expect(meta.data, startsWith('Terms version: 2 · Accepted on '));
      expect(tester.takeException(), isNull);
    });
  });

  group('Invite & Earn lists', () {
    testWidgets('See all opens the friends list and Back returns',
        (tester) async {
      final router = await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralFriends: _friends,
          referralRewards: _rewards,
        ),
      );

      // The friends preview shows what each friend still has to do.
      final friends = _offstage(const Key('referral_friends'));
      await _reveal(tester, friends);
      expect(find.text('Maja'), findsOneWidget);
      expect(find.text('Next: verify their identity'), findsOneWidget);
      // A qualified friend inside the window shows the window, not a step.
      expect(find.textContaining('days of earning left'), findsOneWidget);

      final seeAll =
          find.descendant(of: friends, matching: find.text('See all'));
      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards/friends');
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Maja'), findsOneWidget);
      expect(find.text('user-Z9Y8X'), findsOneWidget);
      expect(find.text('Earning'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards');
      expect(tester.takeException(), isNull);
    });

    testWidgets('See all opens the full ledger', (tester) async {
      final router = await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralRewards: _rewards,
        ),
      );

      final rewards = _offstage(const Key('referral_rewards'));
      await _reveal(tester, rewards);
      await tester.tap(
        find.descendant(of: rewards, matching: find.text('See all')),
      );
      await tester.pumpAndSettle();

      expect(_location(router), '/rewards/earnings');
      // The whole ledger, the paid qualification included.
      expect(_onEarnings('Friend qualified'), findsOneWidget);
      expect(_onEarnings('Top-up commission'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pending reward opens a receipt that is still waiting',
        (tester) async {
      await _pumpApp(
        tester,
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralRewards: _rewards,
        ),
      );

      final rewards = _offstage(const Key('referral_rewards'));
      await _reveal(tester, rewards);
      // Newest first: the first row is the pending top-up commission.
      expect(find.text('Pending'), findsOneWidget);
      await tester.tap(find.text('Top-up commission').first);
      await tester.pumpAndSettle();

      expect(find.text('How this reward was calculated'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
                find.byKey(const Key('referral_reward_explanation_amount')))
            .data,
        r'$2.00',
      );
      expect(find.text('Waiting for provider confirmation'), findsOneWidget);
      expect(find.textContaining('Added to'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Load more appends the next page of friends', (tester) async {
      final api = _FakeApi()
        ..friendsPage = (page) => [
              for (var i = 0; i < 10; i++)
                ReferralFriend.fromJson({
                  'alias': 'user-P$page-$i',
                  'stage': 'INVITED',
                  'attributedAt': '2026-06-01T00:00:00Z',
                  'earnedAmount': 0,
                  'currency': 'USD',
                }),
            ];
      await _pumpApp(
        tester,
        api: api,
        initialLocation: '/rewards/friends',
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralFriends: _fullPage(50),
        ),
      );

      // The first page came with the snapshot: no request yet, and a full
      // page means there may be more.
      expect(api.friendPages, isEmpty);
      // On-stage finders only: an offstage-inclusive one would satisfy
      // scrollUntilVisible before the button is actually in reach.
      final loadMore = find.byKey(const Key('referral_load_more'));
      await tester.scrollUntilVisible(
        loadMore,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      expect(api.friendPages, [2]);
      // The next page sits under the first, and a short page ends the list.
      await tester.scrollUntilVisible(
        find.text('user-P2-9'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('user-P2-9'), findsOneWidget);
      expect(_offstage(const Key('referral_load_more')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'on a desktop shell the friends route forwards to the '
        'workspace tab', (tester) async {
      final router = await _pumpApp(
        tester,
        width: 1440,
        initialLocation: '/rewards/friends',
        snapshot: RewardsSnapshot(
          config: _config,
          referralSummary: _summary(),
          referralFriends: _friends,
        ),
      );

      expect(_location(router), '/rewards?tab=friends');
      expect(tester.takeException(), isNull);
    });
  });
}

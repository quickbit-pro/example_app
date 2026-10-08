// The desktop partner workspace (blueprint p14, p17, p19–20).
//
// The customer instruction for the web view is "access to everything", and
// everything is what the member API exposes: the summary, the ledger with
// its explanations, the friends, the terms, the invitations. These cases pin
// the shape that carries it — a tab that lives in the URL and survives a
// reload, tables that render the API's own fields, a receipt that opens in a
// drawer, a calculator whose sums are the ledger's, paging that appends —
// and the two rules the blueprint will not bend on: the terms gate stands
// where the share action would be, and a pending reward never reads as paid.
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
import 'package:qr_flutter/qr_flutter.dart';

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
  bool termsAccepted = true,
  Map<String, Object?> offer = _offer,
}) =>
    {
      'enabled': true,
      'referralCode': termsAccepted ? 'EXAMPLE28' : null,
      'referralPath': termsAccepted ? 'https://example.com/r/EXAMPLE28' : null,
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
      'offer': offer,
      'terms': {
        'version': 2,
        'text': 'Programme terms: rewards are paid at qualification.',
        'accepted': termsAccepted,
        'acceptedVersion': termsAccepted ? 2 : null,
        'acceptedAt': termsAccepted ? '2026-08-01T09:00:00Z' : null,
      },
      'deliveryMode': 'WALLET_CREDIT',
      'minimumCreditAmount': 0,
      'accumulatedTowardsCredit': 0,
      'programId': 'prog-1',
      'programName': 'Example referrals',
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
      'id': 'reward-$day',
      'eventType': stage == 'PAID' ? 'QUALIFICATION' : 'CARD_TOPUP',
      'amount': amount,
      'currency': 'USD',
      'stage': stage,
      'friendAlias': 'user-A1B2C',
      'occurredAt': '2026-09-0${day}T10:00:00Z',
      if (stage == 'PAID') 'paidAt': '2026-09-02T12:00:00Z',
      if (stage == 'PENDING')
        'explanation': {
          'basis': 'PERCENT_OF_TOPUP',
          'rate': 0.25,
          'termsVersion': 2,
          'rounding': 'Rounded down to USD cents',
          'deliveryExplanation': 'Waiting for provider confirmation',
        },
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
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/rewards',
        builder: (context, state) => RewardsScreen(
          initialTab: state.uri.queryParameters['tab'],
        ),
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

Finder _nav(String label) => find.descendant(
      of: _offstage(const Key('referral_workspace_nav')),
      matching: find.text(label, skipOffstage: false),
    );

/// Brings [finder] into the viewport and gives the layout a frame.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

RewardsSnapshot _snapshot({
  bool termsAccepted = true,
  Map<String, Object?> offer = _offer,
  List<ReferralFriend>? friends,
}) =>
    RewardsSnapshot(
      config: _config,
      referralSummary: _summary(termsAccepted: termsAccepted, offer: offer),
      referralRewards: _rewards,
      referralFriends: friends ?? _friends,
    );

void main() {
  for (final reason in ['GEO_RESIDENCE_EXCLUDED', 'GEO_COUNTRY_UNVERIFIED']) {
    testWidgets('residence gate replaces terms and sharing: $reason', (tester) async {
      await _pumpApp(tester, initialLocation: '/rewards?tab=share', snapshot: RewardsSnapshot(
        config: _config,
        referralSummary: {
          ..._summary(termsAccepted: false),
          'canInvite': false,
          'participationEligibility': {'status': reason == 'GEO_RESIDENCE_EXCLUDED' ? 'INELIGIBLE' : 'PENDING', 'reason': reason},
        },
        referralRewards: _rewards,
        referralFriends: _friends,
      ));
      expect(find.text('Referral participation unavailable', skipOffstage: false), findsOneWidget);
      expect(_offstage(const Key('referral_terms_gate')), findsNothing);
      expect(_offstage(const Key('referral_link_row')), findsNothing);
      expect(_offstage(const Key('referral_email_panel')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  group('workspace navigation', () {
    testWidgets('keeps the tab in the URL and restores it on reload',
        (tester) async {
      // A reload at ?tab=friends lands on Friends, not Overview.
      final router = await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=friends',
        snapshot: _snapshot(),
      );
      expect(tester.takeException(), isNull);
      expect(
          _offstage(const Key('referral_workspace_friends')), findsOneWidget);
      expect(_offstage(const Key('referral_friends_table')), findsOneWidget);

      await tester.tap(_nav('Earnings'));
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards?tab=earnings');
      expect(
          _offstage(const Key('referral_workspace_earnings')), findsOneWidget);
      expect(_offstage(const Key('referral_earnings_table')), findsOneWidget);

      await tester.tap(_nav('Overview'));
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards');
      expect(
          _offstage(const Key('referral_workspace_overview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses top tabs below 1000 px and a sidebar above',
        (tester) async {
      await _pumpApp(tester, width: 900, snapshot: _snapshot());
      expect(_offstage(const Key('referral_workspace_tabs')), findsOneWidget);
      expect(_offstage(const Key('referral_workspace_nav')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the phone routes forward to the workspace tab',
        (tester) async {
      final router = await _pumpApp(
        tester,
        initialLocation: '/rewards/earnings?status=paid',
        snapshot: _snapshot(),
      );
      expect(_location(router), '/rewards?tab=earnings');
      expect(
          _offstage(const Key('referral_workspace_earnings')), findsOneWidget);
    });
  });

  group('overview', () {
    testWidgets('carries the hero, the KPI tiles, the link and the lists',
        (tester) async {
      await _pumpApp(tester, snapshot: _snapshot());

      expect(tester.takeException(), isNull);
      expect(find.text('REWARDS EARNED'), findsOneWidget);
      Finder inTile(Key key, String text) => find.descendant(
            of: _offstage(key),
            matching: find.text(text, skipOffstage: false),
          );
      expect(inTile(const Key('referral_kpi_paid'), 'Paid reward ledger'),
          findsOneWidget);
      expect(inTile(const Key('referral_kpi_paid'), r'$10.00'), findsOneWidget);
      expect(
          inTile(const Key('referral_kpi_pending'), r'$3.50'), findsOneWidget);
      expect(
        inTile(const Key('referral_kpi_pending'),
            'Waiting for provider confirmation'),
        findsOneWidget,
      );
      expect(inTile(const Key('referral_kpi_qualified'), '3'), findsOneWidget);
      expect(
        find.text('Figures update after provider confirmation · USD',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SelectableText>(
                _offstage(const Key('referral_workspace_link')))
            .data,
        'https://example.com/r/EXAMPLE28',
      );

      // Recent activity: all four rewards, newest first; the friend earning
      // now is the qualified one inside her window.
      final activity = _offstage(const Key('referral_recent_activity'));
      await _reveal(tester, activity);
      expect(
        find.descendant(of: activity, matching: find.text('Top-up commission')),
        findsNWidgets(3),
      );
      expect(
        find.descendant(of: activity, matching: find.text('Friend qualified')),
        findsOneWidget,
      );
      final earning = _offstage(const Key('referral_friends_earning'));
      expect(find.descendant(of: earning, matching: find.text('Maja')),
          findsOneWidget);
      expect(
        find.descendant(
            of: earning, matching: find.textContaining('Earning until')),
        findsOneWidget,
      );
    });

    testWidgets('the QR button opens the link as a code', (tester) async {
      await _pumpApp(tester, snapshot: _snapshot());
      final qr = _offstage(const Key('referral_workspace_qr'));
      await _reveal(tester, qr);
      await tester.tap(qr);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('referral_qr_dialog')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the terms gate stands where the share action would be',
        (tester) async {
      final router = await _pumpApp(
        tester,
        snapshot: _snapshot(termsAccepted: false),
      );
      expect(_offstage(const Key('referral_terms_gate')), findsOneWidget);
      expect(_offstage(const Key('referral_link_row')), findsNothing);

      await tester.tap(_nav('Share'));
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards?tab=share');
      expect(_offstage(const Key('referral_terms_gate')), findsOneWidget);
      expect(_offstage(const Key('referral_link_row')), findsNothing);
      expect(_offstage(const Key('referral_email_panel')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('friends table', () {
    testWidgets('renders the API fields and filters by stage and search',
        (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=friends',
        snapshot: _snapshot(),
      );
      final table = _offstage(const Key('referral_friends_table'));
      Finder inTable(String text) => find.descendant(
            of: table,
            matching: find.text(text, skipOffstage: false),
          );
      for (final header in [
        'Friend',
        'Stage',
        'Joined',
        'Next requirement',
        'Earning until',
        'Earned',
      ]) {
        expect(inTable(header), findsOneWidget, reason: header);
      }
      expect(inTable('Maja'), findsOneWidget);
      expect(inTable('Qualified'), findsOneWidget);
      expect(inTable('user-Z9Y8X'), findsOneWidget);
      expect(inTable('Next: verify their identity'), findsOneWidget);
      expect(inTable(r'$4.50'), findsOneWidget);
      // Never the pseudonym of a friend the inviter named.
      expect(inTable('user-A1B2C'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('referral_friends_search')), 'maja');
      await tester.pumpAndSettle();
      expect(inTable('Maja'), findsOneWidget);
      expect(inTable('user-Z9Y8X'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('referral_friends_search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Earning'));
      await tester.pumpAndSettle();
      expect(inTable('Maja'), findsOneWidget);
      expect(inTable('user-Z9Y8X'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Load more appends the next page', (tester) async {
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
        initialLocation: '/rewards?tab=friends',
        snapshot: _snapshot(friends: _fullPage(50)),
      );
      expect(api.friendPages, isEmpty);

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
      expect(
        find.descendant(
          of: _offstage(const Key('referral_friends_table')),
          matching: find.text('user-P2-9', skipOffstage: false),
        ),
        findsOneWidget,
      );
      // A short page ends the list.
      expect(_offstage(const Key('referral_load_more')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('earnings table', () {
    testWidgets('renders the ledger and opens the explanation drawer',
        (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=earnings',
        snapshot: _snapshot(),
      );
      final table = _offstage(const Key('referral_earnings_table'));
      Finder inTable(String text) => find.descendant(
            of: table,
            matching: find.text(text, skipOffstage: false),
          );
      for (final header in [
        'Date',
        'Event',
        'Friend',
        'Basis · rate',
        'Status',
        'Amount',
      ]) {
        expect(inTable(header), findsOneWidget, reason: header);
      }
      expect(inTable('Top-up commission'), findsNWidgets(3));
      expect(inTable('Friend qualified'), findsOneWidget);
      expect(inTable('Eligible credited top-up · 0.25%'), findsOneWidget);
      // A pending reward never reads as paid; a legacy paid row without allocation evidence stays unverified.
      expect(inTable('Pending'), findsOneWidget);
      expect(inTable('Details unavailable'), findsOneWidget);
      expect(_offstage(const Key('referral_totals')), findsOneWidget);

      // The newest row is the pending top-up commission with an explanation.
      final row = _offstage(const ValueKey('referral_reward_reward-5'));
      await _reveal(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      final drawer = find.byKey(const Key('referral_reward_drawer'));
      expect(drawer, findsOneWidget);
      Finder inDrawer(String text) =>
          find.descendant(of: drawer, matching: find.text(text));
      expect(inDrawer('How this reward was calculated'), findsOneWidget);
      expect(inDrawer(r'$2.00'), findsOneWidget);
      expect(inDrawer('Waiting for provider confirmation'), findsWidgets);
      expect(inDrawer('Eligible credited top-up'), findsOneWidget);
      expect(inDrawer('0.25%'), findsOneWidget);
      expect(inDrawer('2'), findsOneWidget);
      expect(inDrawer('Rounded down to USD cents'), findsOneWidget);
      expect(
          find.descendant(
              of: drawer, matching: find.textContaining('Added to')),
          findsNothing);

      await tester.tap(find.descendant(
        of: drawer,
        matching: find.byTooltip('Close'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_reward_drawer')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the status filter narrows the rows', (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=earnings',
        snapshot: _snapshot(),
      );
      await tester.tap(find.text('Paid reward ledger').last);
      await tester.pumpAndSettle();
      final table = _offstage(const Key('referral_earnings_table'));
      expect(
        find.descendant(of: table, matching: find.text('Friend qualified')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text('Top-up commission')),
        findsNothing,
      );
    });
  });

  group('offer & terms', () {
    testWidgets('shows the offer, the terms with their version, and the sums',
        (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=offer',
        snapshot: _snapshot(),
      );
      expect(tester.takeException(), isNull);
      expect(_offstage(const Key('referral_offer_card')), findsOneWidget);
      expect(_offstage(const Key('referral_terms_panel')), findsOneWidget);
      expect(
        tester.widget<Text>(_offstage(const Key('referral_terms_meta'))).data,
        startsWith('Terms version: 2 · Accepted on '),
      );

      // Rate × amount for a share of the top-up: $100 at 0.25% is $0.25.
      Text headline() => tester
          .widget<Text>(_offstage(const Key('referral_calculator_headline')));
      expect(headline().data, r'You receive $0.25');
      expect(
        _offstage(const Key('referral_calculator_disclaimer')),
        findsOneWidget,
      );
      expect(
        find.text(
            r'Up to $5,000 in eligible credited top-ups counts per friend.',
            skipOffstage: false),
        findsOneWidget,
      );

      await tester.enterText(
          find.byKey(const Key('referral_calculator_amount')), '200');
      await tester.pumpAndSettle();
      expect(headline().data, r'You receive $0.50');
      expect(_offstage(const Key('referral_calculator_cap')), findsNothing);

      // Over the per-friend volume cap only the eligible part counts, and
      // the panel says so.
      await tester.enterText(
          find.byKey(const Key('referral_calculator_amount')), '6000');
      await tester.pumpAndSettle();
      expect(headline().data, r'You receive $12.50');
      expect(
        tester
            .widget<Text>(_offstage(const Key('referral_calculator_cap')))
            .data,
        r'Only $5,000 of this top-up would be eligible under the $5,000 limit per friend.',
      );
    });

    testWidgets('a margin share is shown as an upper bound', (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=offer',
        snapshot: _snapshot(offer: {
          ..._offer,
          'topupCalculationType': 'PERCENT_OF_MARGIN',
          'topupRate': 30,
        }),
      );
      expect(
        tester
            .widget<Text>(_offstage(const Key('referral_calculator_headline')))
            .data,
        r'Up to $30',
      );
      expect(
        find.textContaining('Depends on the settled margin.',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('share', () {
    testWidgets('carries the link, the code, the caption and the email form',
        (tester) async {
      await _pumpApp(
        tester,
        initialLocation: '/rewards?tab=share',
        snapshot: _snapshot(),
      );
      expect(tester.takeException(), isNull);
      expect(_offstage(const Key('referral_link_row')), findsOneWidget);
      expect(
        tester
            .widget<Text>(_offstage(const Key('referral_workspace_code')))
            .data,
        'Code EXAMPLE28',
      );
      expect(_offstage(const Key('referral_share_caption')), findsOneWidget);
      expect(
        find.textContaining('https://example.com/r/EXAMPLE28',
            skipOffstage: false),
        findsWidgets,
      );
      expect(_offstage(const Key('referral_email_panel')), findsOneWidget);
      expect(_offstage(const Key('referral_invitation_send')), findsOneWidget);
      expect(
          _offstage(const Key('referral_how_sharing_works')), findsOneWidget);
      expect(
        find.textContaining('No automatic messages are sent.',
            skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}

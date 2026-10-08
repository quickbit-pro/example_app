// Member analytics on the rewards page (contract 2026-09-15).
//
// On the desktop workspace: the period selector asks the provider for the
// period it names and the KPI tiles say which period they show; the
// conversion journey renders the six counts and the rate; the trend panel
// switches series; an empty period shows the next action; and a backend
// without the resource leaves every analytics block out while the tiles
// keep their all-time figures. On the phone: one line under the tiles from
// the month range, opening the earnings list.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
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

const _offer = {
  'welcomeAmount': 3,
  'welcomeCurrency': 'USD',
  'qualificationCalculationType': 'FIXED',
  'qualificationRate': 1,
  'topupCalculationType': 'PERCENT_OF_TOPUP',
  'topupRate': 0.25,
  'earningWindowDays': 90,
  'requiresKyc': true,
  'requiresPaidCard': true,
  'requiresTopup': true,
  'minimumTopup': 10,
};

const _summary = {
  'enabled': true,
  'referralCode': 'EXAMPLE28',
  'referralPath': 'https://example.com/r/EXAMPLE28',
  'currentLevel': {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
  'levels': [
    {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
  ],
  'progress': {'currentValue': 3, 'nextThreshold': 5},
  'referrals': {'invited': 8, 'qualified': 3, 'inProgress': 2, 'earning': 3},
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
    'text': 'Programme terms.',
    'accepted': true,
    'acceptedVersion': 2,
    'acceptedAt': '2026-08-01T09:00:00Z',
  },
  'deliveryMode': 'WALLET_CREDIT',
  'minimumCreditAmount': 0,
  'accumulatedTowardsCredit': 0,
  'programId': 'prog-1',
  'programName': 'Example referrals',
  'canInvite': true,
};

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
];

/// The platform's answer for a period. The qualified count is the range's
/// day count so a test can tell which period the tiles show; the month
/// range carries the fixture the phone line states.
ReferralMemberAnalytics _analytics(ReferralAnalyticsRange range) {
  final weeks = range == ReferralAnalyticsRange.ninetyDays ? 13 : 5;
  return ReferralMemberAnalytics.fromJson({
    'from': '2026-08-16T00:00:00Z',
    'to': '2026-09-15T00:00:00Z',
    'range': range.wire,
    'currency': 'USD',
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
      'qualified': range.days ?? 3,
      'conversionRate': 0.375,
      'rewardsAccrued': 13.5,
      'rewardsPaid': 10,
      'rewardsPending': 3.5,
    },
    'weekly': [
      for (var i = 0; i < weeks; i++)
        {
          'weekStart': DateTime.utc(2026, 6, 15).add(Duration(days: 7 * i)).toIso8601String(),
          'attributed': i % 3,
          'qualified': i % 2,
          'rewardsAccrued': i * 1.5,
          'rewardsPaid': i.toDouble(),
        },
    ],
    'topFriends': [
      {
        'alias': 'user-A1B2C',
        'stage': 'QUALIFIED',
        'earned': 4.5,
        'qualifiedAt': '2026-09-01T00:00:00Z',
      },
      {'alias': 'user-Z9Y8X', 'stage': 'VERIFYING', 'earned': 0},
    ],
  });
}

final _empty = ReferralMemberAnalytics.fromJson({
  'range': '30d',
  'currency': 'USD',
  'weekly': [
    for (var i = 0; i < 5; i++)
      {
        'weekStart':
            DateTime.utc(2026, 8, 17).add(Duration(days: 7 * i)).toIso8601String(),
      },
  ],
});

typedef _Analytics = ReferralMemberAnalytics? Function(ReferralAnalyticsRange);

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  required _Analytics analytics,
  required List<ReferralAnalyticsRange> requested,
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/rewards',
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
        rewardsSnapshotProvider.overrideWith((ref) async => RewardsSnapshot(
              config: _config,
              referralSummary: _summary,
              referralFriends: _friends,
            )),
        referralAnalyticsProvider.overrideWith((ref, range) async {
          requested.add(range);
          return analytics(range);
        }),
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

Finder _within(Key key, String text) => find.descendant(
      of: _offstage(key),
      matching: find.text(text, skipOffstage: false),
    );

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  group('workspace overview', () {
    testWidgets('the period selector re-requests and recaptions the tiles',
        (tester) async {
      final requested = <ReferralAnalyticsRange>[];
      await _pumpApp(tester, analytics: _analytics, requested: requested);
      expect(tester.takeException(), isNull);

      // Opens on 30 days: one request, and the tiles carry the period.
      expect(requested, [ReferralAnalyticsRange.thirtyDays]);
      const qualified = Key('referral_kpi_qualified');
      expect(_within(qualified, '30'), findsOneWidget);
      expect(_within(qualified, 'in the last 30 days'), findsOneWidget);
      expect(_within(const Key('referral_kpi_paid'), 'in the last 30 days'),
          findsOneWidget);
      expect(_within(const Key('referral_kpi_pending'), r'$3.50'),
          findsOneWidget);

      final selector = _offstage(const Key('referral_period_selector'));
      await _reveal(tester, selector);
      await tester.tap(find.descendant(of: selector, matching: find.text('7 days')));
      await tester.pumpAndSettle();
      expect(requested.last, ReferralAnalyticsRange.sevenDays);
      expect(_within(qualified, '7'), findsOneWidget);
      expect(_within(qualified, 'in the last 7 days'), findsOneWidget);

      await tester.tap(
          find.descendant(of: selector, matching: find.text('This month')));
      await tester.pumpAndSettle();
      expect(requested.last, ReferralAnalyticsRange.month);
      expect(_within(qualified, 'this month'), findsOneWidget);
      // Going back to a period already fetched does not ask again.
      await tester.tap(find.descendant(of: selector, matching: find.text('7 days')));
      await tester.pumpAndSettle();
      expect(requested.where((range) => range == ReferralAnalyticsRange.sevenDays),
          hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the journey strip renders the six counts and the rate',
        (tester) async {
      await _pumpApp(tester, analytics: _analytics, requested: []);
      final strip = _offstage(const Key('referral_journey_strip'));
      await _reveal(tester, strip);

      for (final (id, label, count) in [
        ('invited', 'Invited', '2'),
        ('verified', 'Verified', '1'),
        ('cardIssued', 'Card issued', '1'),
        ('qualified', 'Qualified', '1'),
        ('earning', 'Earning', '3'),
        ('windowEnded', 'Window ended', '0'),
      ]) {
        final stage = Key('referral_journey_$id');
        expect(_within(stage, label), findsOneWidget, reason: id);
        expect(_within(stage, count), findsOneWidget, reason: id);
      }
      expect(
        tester.widget<Text>(_offstage(const Key('referral_journey_rate'))).data,
        '38%',
      );
      expect(find.descendant(of: strip, matching: find.text('30 of 8 qualified')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the trend panel switches series and lists the top friends',
        (tester) async {
      await _pumpApp(tester, analytics: _analytics, requested: []);
      final panel = _offstage(const Key('referral_trend_panel'));
      await _reveal(tester, panel);

      expect(_offstage(const ValueKey('referral_trend_friends')), findsOneWidget);
      expect(find.descendant(of: panel, matching: find.byType(BarChart)),
          findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Attributed')),
          findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Qualified')),
          findsOneWidget);

      await tester.tap(find.descendant(
        of: _offstage(const Key('referral_trend_tabs')),
        matching: find.text('Earnings'),
      ));
      await tester.pumpAndSettle();
      expect(_offstage(const ValueKey('referral_trend_earnings')), findsOneWidget);
      expect(_offstage(const ValueKey('referral_trend_friends')), findsNothing);
      expect(find.descendant(of: panel, matching: find.text('Accrued')),
          findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Paid')),
          findsOneWidget);

      // The top friends: pseudonym, stage, earned — never a name or a
      // balance.
      const top = Key('referral_top_friends');
      expect(_within(top, 'Top friends'), findsOneWidget);
      expect(_within(top, 'user-A1B2C'), findsOneWidget);
      expect(_within(top, r'$4.50'), findsOneWidget);
      expect(_within(top, 'Qualified'), findsOneWidget);
      expect(_within(top, 'user-Z9Y8X'), findsOneWidget);
      expect(_within(top, 'Verifying'), findsOneWidget);
      expect(_within(top, 'Maja'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty period shows the next action', (tester) async {
      final router = await _pumpApp(
        tester,
        analytics: (_) => _empty,
        requested: [],
      );
      final empty = _offstage(const Key('referral_analytics_empty'));
      expect(empty, findsOneWidget);
      expect(_offstage(const Key('referral_journey_strip')), findsNothing);
      expect(_offstage(const Key('referral_trend_panel')), findsNothing);
      expect(
        find.descendant(of: empty, matching: find.text('No activity in this period')),
        findsOneWidget,
      );
      // The tiles still say which period they show.
      expect(_within(const Key('referral_kpi_qualified'), '0'), findsOneWidget);
      expect(_within(const Key('referral_kpi_qualified'), 'in the last 30 days'),
          findsOneWidget);

      await _reveal(tester, empty);
      await tester.tap(
          find.descendant(of: empty, matching: find.text('Share your link')));
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards?tab=share');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a backend without analytics leaves the blocks out',
        (tester) async {
      await _pumpApp(tester, analytics: (_) => null, requested: []);
      expect(tester.takeException(), isNull);
      expect(_offstage(const Key('referral_period_selector')), findsNothing);
      expect(_offstage(const Key('referral_analytics')), findsNothing);
      expect(_offstage(const Key('referral_analytics_empty')), findsNothing);
      expect(_offstage(const Key('referral_analytics_error')), findsNothing);
      // All-time tiles under their own notes, as before.
      expect(_within(const Key('referral_kpi_paid'), r'$10.00'), findsOneWidget);
      expect(_within(const Key('referral_kpi_paid'), 'Already in your wallet'),
          findsOneWidget);
      expect(_within(const Key('referral_kpi_qualified'), '3'), findsOneWidget);
      expect(find.textContaining('in the last', skipOffstage: false),
          findsNothing);
    });
  });

  group('phone summary', () {
    testWidgets('the month line states the month and opens the earnings list',
        (tester) async {
      final requested = <ReferralAnalyticsRange>[];
      final router = await _pumpApp(
        tester,
        width: 375,
        analytics: _analytics,
        requested: requested,
      );
      expect(tester.takeException(), isNull);
      expect(requested, containsAll([
        ReferralAnalyticsRange.month,
        ReferralAnalyticsRange.ninetyDays,
      ]));

      final line = _offstage(const Key('referral_month_line'));
      await _reveal(tester, line);
      expect(
        tester.widget<Text>(_offstage(const Key('referral_month_line_text'))).data,
        r'This month: 3 qualified friends · $13.50 earned',
      );
      expect(_offstage(const Key('referral_month_sparkline')), findsOneWidget);
      // Under the tiles, above the friends preview.
      expect(
        tester.getTopLeft(line).dy,
        greaterThan(tester.getBottomLeft(
                _offstage(const Key('referral_summary_tiles')))
            .dy - 1),
      );

      await tester.tap(line);
      await tester.pumpAndSettle();
      expect(_location(router), '/rewards/earnings');
      expect(find.text('Earnings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one qualified friend reads in the singular', (tester) async {
      await _pumpApp(
        tester,
        width: 375,
        analytics: (range) => ReferralMemberAnalytics.fromJson(const {
          'range': 'month',
          'currency': 'USD',
          'totals': {'qualified': 1, 'rewardsAccrued': 1},
        }),
        requested: [],
      );
      expect(
        tester.widget<Text>(_offstage(const Key('referral_month_line_text'))).data,
        r'This month: 1 qualified friend · $1.00 earned',
      );
      // Fewer than two weeks: no sparkline.
      expect(_offstage(const Key('referral_month_sparkline')), findsNothing);
    });

    testWidgets('a backend without analytics mounts nothing', (tester) async {
      await _pumpApp(tester, width: 375, analytics: (_) => null, requested: []);
      expect(tester.takeException(), isNull);
      expect(_offstage(const Key('referral_month_line')), findsNothing);
      expect(_offstage(const Key('referral_month_line_loading')), findsNothing);
      expect(_offstage(const Key('referral_summary_tiles')), findsOneWidget);
    });
  });
}

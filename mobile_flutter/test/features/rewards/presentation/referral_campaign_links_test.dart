// Campaign links on the workspace and the phone (contract 2026-09-15,
// blueprint p17 and p27).
//
// These cases pin the shape the contract asks for: a Links tab that only
// exists once the platform serves links, a list that renders the API's own
// fields, a guided form that ends on the created link with Copy, QR and
// caption, status changes that go through a confirmation and the API, a
// performance panel with the period selector, the Overview's campaign table
// fed by analytics, and the phone's secondary list that mounts only when a
// link is active.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_campaign_links.dart';
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

const _summary = {
  'enabled': true,
  'referralCode': 'EXAMPLE28',
  'referralPath': 'https://example.com/r/EXAMPLE28',
  'referrals': {'invited': 8, 'qualified': 3, 'inProgress': 2, 'earning': 3},
  'rewards': {'pending': 2, 'paid': 10, 'currency': 'USD'},
  'offer': {
    'welcomeAmount': 3,
    'welcomeCurrency': 'USD',
    'qualificationCalculationType': 'FIXED',
    'qualificationRate': 1,
    'topupCalculationType': 'PERCENT_OF_TOPUP',
    'topupRate': 0.25,
    'requiresTopup': true,
  },
  'terms': {'version': 2, 'accepted': true, 'acceptedVersion': 2},
  'deliveryMode': 'WALLET_CREDIT',
  'programId': 'prog-1',
  'programName': 'Example referrals',
  'canInvite': true,
};

ReferralCampaignLink _link({
  String id = 'link-1',
  String name = 'Autumn newsletter',
  String code = 'AUTUMN26',
  String status = 'ACTIVE',
  String? expiresAt,
  int? clickCount,
  int? uniqueClickCount,
}) =>
    ReferralCampaignLink.fromJson({
      'id': id,
      'programId': 'prog-1',
      'programName': 'Example referrals',
      'name': name,
      'code': code,
      'channel': 'email',
      'locale': 'en',
      'status': status,
      'createdAt': '2026-09-01T08:00:00Z',
      'expiresAt': expiresAt,
      'shareUrl': 'https://example.com/signup?ref=$code',
      'signupCount': 8,
      'qualifiedCount': 2,
      // Click counters (addendum A) only when the case asks for a platform
      // that counts them.
      if (clickCount != null) 'clickCount': clickCount,
      if (uniqueClickCount != null) 'uniqueClickCount': uniqueClickCount,
      'suggestedCaption': 'Join me on Example and get \$3 after your first top-up.',
    });

DioException _http(int status) {
  final request = RequestOptions(path: '/links');
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

class _FakeApi extends MobilePlatformApi {
  _FakeApi() : super(Dio());

  List<ReferralCampaignLink> links = [_link()];
  Object? linksFailure;
  Object? createFailure;
  var listCalls = 0;
  final created = <ReferralCampaignLinkDraft>[];
  final updates = <({String id, ReferralCampaignLinkStatus? status})>[];
  final performanceRanges = <ReferralAnalyticsRange>[];
  List<ReferralCampaignRow> campaigns = const [];

  /// The platform counts clicks: performance answers carry them.
  bool performanceWithClicks = false;

  @override
  Future<List<ReferralCampaignLink>> getReferralCampaignLinks({
    String? programId,
    ReferralCampaignLinkStatus? status,
  }) async {
    listCalls++;
    if (linksFailure != null) throw linksFailure!;
    return links;
  }

  @override
  Future<ReferralCampaignLink> createReferralCampaignLink(
    ReferralCampaignLinkDraft draft,
  ) async {
    created.add(draft);
    if (createFailure != null) throw createFailure!;
    final link = _link(
      id: 'link-new',
      name: draft.name.trim(),
      code: draft.code?.trim().isNotEmpty == true
          ? draft.code!.trim().toUpperCase()
          : 'AUTUMN-X9Q2',
    );
    links = [...links, link];
    return link;
  }

  @override
  Future<ReferralCampaignLink> updateReferralCampaignLink(
    String linkId, {
    ReferralCampaignLinkStatus? status,
    String? name,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async {
    updates.add((id: linkId, status: status));
    links = [
      for (final link in links)
        link.id == linkId
            ? _link(id: link.id, name: link.name, code: link.code, status: status!.wire)
            : link,
    ];
    return links.firstWhere((link) => link.id == linkId);
  }

  @override
  Future<ReferralCampaignLinkPerformance> getReferralCampaignLinkPerformance(
    String linkId, {
    ReferralAnalyticsRange range = ReferralAnalyticsRange.thirtyDays,
  }) async {
    performanceRanges.add(range);
    return ReferralCampaignLinkPerformance(
      signups: range == ReferralAnalyticsRange.sevenDays ? 2 : 8,
      verified: 6,
      qualified: 2,
      earning: 2,
      rewardsAccrued: 4.5,
      rewardsPaid: 1,
      clicks: performanceWithClicks ? 40 : 0,
      uniqueClicks: performanceWithClicks ? 32 : 0,
      clickToSignupRate: performanceWithClicks ? 0.25 : null,
      clicksTracked: performanceWithClicks,
    );
  }

  @override
  Future<ReferralMemberAnalytics> getReferralMemberAnalytics({
    String? programId,
    ReferralAnalyticsRange range = ReferralAnalyticsRange.thirtyDays,
    DateTime? from,
    DateTime? to,
  }) async {
    return ReferralMemberAnalytics(
      range: range,
      totals: const ReferralAnalyticsTotals(attributed: 5, qualified: 2),
      campaigns: campaigns,
    );
  }

  @override
  Future<List<ReferralFriend>> getReferralFriends({
    String? programId,
    int page = 1,
    int pageSize = 50,
  }) async =>
      const [];

  @override
  Future<List<ReferralReward>> getReferralRewards({
    String? programId,
    int page = 1,
    int pageSize = 50,
  }) async =>
      const [];
}

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  required _FakeApi api,
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
      ),
    ],
  );
  addTearDown(router.dispose);
  final themes = buildAppThemes(_exampleBranding);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rewardsSnapshotProvider.overrideWith((ref) async =>
            const RewardsSnapshot(config: _config, referralSummary: _summary)),
        mobilePlatformApiProvider.overrideWithValue(api),
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

Finder _offstage(Key key) => find.byKey(key, skipOffstage: false);

Finder _nav(String label) => find.descendant(
      of: _offstage(const Key('referral_workspace_nav')),
      matching: find.text(label, skipOffstage: false),
    );

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  final clipboard = <String>[];
  setUp(() {
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      if (call.method == 'Clipboard.getData') return {'text': ''};
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('Links tab', () {
    testWidgets('exists only once the platform serves campaign links',
        (tester) async {
      final api = _FakeApi()..linksFailure = _http(404);
      await _pumpApp(tester, api: api);
      expect(_nav('Links'), findsNothing);
      expect(_nav('Share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists the member links with their figures', (tester) async {
      final api = _FakeApi()
        ..links = [
          _link(),
          _link(id: 'link-2', name: 'Meetup', code: 'MEETUP-1', status: 'PAUSED'),
        ]
        ..campaigns = const [
          ReferralCampaignRow(
            linkId: 'link-1',
            name: 'Autumn newsletter',
            code: 'AUTUMN26',
            signups: 5,
            qualified: 2,
            rewardsAccrued: 6.25,
          ),
        ];
      final router = await _pumpApp(tester, api: api);
      await tester.tap(_nav('Links'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(),
          '/rewards?tab=links');
      expect(_offstage(const Key('referral_links_list')), findsOneWidget);
      expect(find.text('Autumn newsletter', skipOffstage: false), findsOneWidget);
      expect(find.text('AUTUMN26', skipOffstage: false), findsOneWidget);
      expect(find.text('Meetup', skipOffstage: false), findsOneWidget);
      expect(
        tester.widget<Text>(_offstage(const Key('referral_link_signups_link-1'))).data,
        '8',
      );
      expect(
        tester.widget<Text>(_offstage(const Key('referral_link_qualified_link-1'))).data,
        '2',
      );
      // Earnings for the period come from the analytics campaign rows.
      expect(
        tester.widget<Text>(_offstage(const Key('referral_link_earned_link-1'))).data,
        contains('6.25'),
      );
      expect(
        tester.widget<Text>(_offstage(const Key('referral_link_earned_link-2'))).data,
        contains('0.00'),
      );
      expect(find.text('Paused', skipOffstage: false), findsOneWidget);
      expect(_offstage(const Key('referral_links_period_note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows clicks, unique clicks and the rate once counted',
        (tester) async {
      final api = _FakeApi()
        ..links = [
          _link(clickCount: 40, uniqueClickCount: 32),
          _link(id: 'link-2', name: 'Meetup', code: 'MEETUP-1'),
        ];
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');
      String figure(String key) =>
          tester.widget<Text>(_offstage(Key('referral_link_${key}_link-1'))).data!;
      expect(figure('clicks'), '40');
      expect(figure('unique_clicks'), '32');
      expect(figure('signups'), '8');
      expect(figure('rate'), '25%');
      // A link from a platform that predates clicks shows no click figure.
      expect(_offstage(const Key('referral_link_clicks_link-2')), findsNothing);
      expect(_offstage(const Key('referral_link_rate_link-2')), findsNothing);
      expect(_offstage(const Key('referral_link_signups_link-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers a destination with human labels and sends the word',
        (tester) async {
      final api = _FakeApi()..links = [];
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');
      await tester.tap(_offstage(const Key('referral_links_create')));
      await tester.pumpAndSettle();
      final destination = find.byKey(const Key('referral_link_destination'));
      await tester.ensureVisible(destination);
      await tester.pumpAndSettle();
      expect(find.text('Sign-up page'), findsOneWidget, reason: 'the default');
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(find.text('Home after sign-up'), findsOneWidget);
      expect(find.text('Add money'), findsOneWidget);
      await tester.tap(find.text('Cards').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('referral_link_name')), 'Cards flyer');
      await tester.tap(find.byKey(const Key('referral_link_submit')));
      await tester.pumpAndSettle();
      final draft = api.created.single;
      expect(draft.destination, ReferralCampaignDestination.cards);
      expect(draft.toJson()['destination'], 'cards');
      expect(find.byKey(const Key('referral_link_created')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('creates a link through the guided form and ends on the link',
        (tester) async {
      final api = _FakeApi()..links = [];
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');
      expect(_offstage(const Key('referral_links_empty')), findsOneWidget);

      await tester.tap(_offstage(const Key('referral_links_create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_link_creator')), findsOneWidget);
      // The offer preview sentence comes from the programme figures.
      expect(find.byKey(const Key('referral_link_offer_preview')), findsOneWidget);
      expect(find.textContaining('for them.'), findsOneWidget);
      // One programme: no picker.
      expect(find.byKey(const Key('referral_link_programme')), findsNothing);

      // Validation stands in the way of an empty name and a bad code.
      await tester.enterText(find.byKey(const Key('referral_link_code')), 'ab');
      await tester.tap(find.byKey(const Key('referral_link_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name for this link'), findsOneWidget);
      expect(find.text('Use 6–24 letters, digits, hyphens or underscores'),
          findsOneWidget);
      expect(api.created, isEmpty);

      await tester.enterText(
          find.byKey(const Key('referral_link_name')), ' Autumn newsletter ');
      await tester.enterText(find.byKey(const Key('referral_link_code')), '');
      await tester.tap(find.byKey(const Key('referral_link_submit')));
      await tester.pumpAndSettle();

      final draft = api.created.single;
      expect(draft.name, ' Autumn newsletter ');
      expect(draft.channel, ReferralCampaignChannel.social);
      expect(draft.programId, 'prog-1');
      expect(draft.toJson().containsKey('code'), isFalse);
      expect(draft.locale, 'en');

      expect(find.byKey(const Key('referral_link_created')), findsOneWidget);
      expect(
        tester.widget<SelectableText>(
            find.byKey(const Key('referral_link_created_address'))).data,
        'https://example.com/signup?ref=AUTUMN-X9Q2',
      );
      expect(find.text('Code AUTUMN-X9Q2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('referral_link_created_copy')));
      await tester.pumpAndSettle();
      expect(clipboard.last, 'https://example.com/signup?ref=AUTUMN-X9Q2');
      await tester.tap(find.byKey(const Key('referral_link_created_caption')));
      await tester.pumpAndSettle();
      expect(clipboard.last, contains('Join me on Example'));
      await tester.tap(find.byKey(const Key('referral_link_created_qr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_qr_dialog')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final listCallsBefore = api.listCalls;
      await tester.tap(find.byKey(const Key('referral_link_created_done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_link_created')), findsNothing);
      expect(api.listCalls, greaterThan(listCallsBefore));
      expect(_offstage(const Key('referral_link_link-new')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the platform message when creation is refused',
        (tester) async {
      final request = RequestOptions(path: '/links');
      final api = _FakeApi()
        ..links = []
        ..createFailure = DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: request,
            statusCode: 409,
            data: {
              'title': 'That code is already in use.',
              'code': 'mobile.referrals.links.campaign_code_taken',
              'status': 409,
            },
          ),
        );
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');
      await tester.tap(_offstage(const Key('referral_links_create')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('referral_link_name')), 'Autumn');
      await tester.enterText(find.byKey(const Key('referral_link_code')), 'AUTUMN26');
      await tester.tap(find.byKey(const Key('referral_link_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_link_creator')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_link_creator_error'))).data,
        'That code is already in use.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('pauses a link after confirmation and archives one',
        (tester) async {
      final api = _FakeApi();
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');

      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      expect(find.text('Pause link'), findsOneWidget);
      expect(find.text('Resume link'), findsNothing);
      await tester.tap(find.text('Pause link'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_link_confirm')), findsOneWidget);
      expect(api.updates, isEmpty, reason: 'nothing changes before confirming');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.updates, isEmpty);

      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause link'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('referral_link_confirm_yes')));
      await tester.pumpAndSettle();
      expect(api.updates, [(id: 'link-1', status: ReferralCampaignLinkStatus.paused)]);
      expect(find.text('Paused', skipOffstage: false), findsOneWidget);

      // A paused link offers Resume, which needs no confirmation.
      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      expect(find.text('Pause link'), findsNothing);
      await tester.tap(find.text('Resume link'));
      await tester.pumpAndSettle();
      expect(api.updates.last.status, ReferralCampaignLinkStatus.active);

      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive link'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('referral_link_confirm_yes')));
      await tester.pumpAndSettle();
      expect(api.updates.last.status, ReferralCampaignLinkStatus.archived);
      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      expect(find.text('Archive link'), findsNothing);
      expect(find.text('Copy link'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens a performance panel with the period selector',
        (tester) async {
      final api = _FakeApi();
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');
      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral_link_performance')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_link_performance_signups'))).data,
        '8',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_link_performance_accrued'))).data,
        contains('4.50'),
      );
      expect(find.text('in the last 30 days'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byKey(const Key('referral_link_performance')),
        matching: find.text('7 days'),
      ));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_link_performance_signups'))).data,
        '2',
      );
      expect(api.performanceRanges,
          [ReferralAnalyticsRange.thirtyDays, ReferralAnalyticsRange.sevenDays]);
      // No click figures from a platform that does not count them.
      expect(find.byKey(const Key('referral_link_performance_clicks')), findsNothing);
      expect(find.byKey(const Key('referral_link_performance_clicks_note')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the performance panel shows clicks, unique clicks and the rate',
        (tester) async {
      final api = _FakeApi()..performanceWithClicks = true;
      await _pumpApp(tester, api: api, initialLocation: '/rewards?tab=links');
      await tester.tap(_offstage(const Key('referral_link_menu_link-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      String tile(String key) => tester
          .widget<Text>(find.byKey(Key('referral_link_performance_$key')))
          .data!;
      expect(tile('clicks'), '40');
      expect(tile('unique_clicks'), '32');
      expect(tile('rate'), '25%');
      expect(tile('signups'), '8');
      expect(find.byKey(const Key('referral_link_performance_clicks_note')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Overview', () {
    testWidgets('shows the campaign performance table from analytics',
        (tester) async {
      final api = _FakeApi()
        ..campaigns = const [
          ReferralCampaignRow(
            linkId: 'link-1',
            name: 'Autumn newsletter',
            code: 'AUTUMN26',
            clicks: 12,
            signups: 5,
            qualified: 2,
            rewardsAccrued: 6.25,
          ),
          ReferralCampaignRow(
            linkId: 'link-9',
            name: 'Old flyer',
            code: 'FLYER-1',
            signups: 1,
            qualified: 0,
            rewardsAccrued: 0,
          ),
        ];
      await _pumpApp(tester, api: api);
      final table = _offstage(const Key('referral_campaign_performance_table'));
      expect(table, findsOneWidget);
      await _reveal(tester, table);
      expect(find.text('Autumn newsletter'), findsOneWidget);
      expect(find.text('Old flyer'), findsOneWidget);
      expect(find.textContaining('6.25'), findsOneWidget);
      // Addendum A: the table carries the period's clicks per link.
      expect(find.descendant(of: table, matching: find.text('Clicks')),
          findsOneWidget);
      expect(find.descendant(of: table, matching: find.text('12')),
          findsOneWidget);
      // "Manage links" takes the member to the Links tab.
      await tester.tap(find.byKey(const Key('referral_campaign_performance_manage')));
      await tester.pumpAndSettle();
      expect(_offstage(const Key('referral_workspace_links')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaves the table out without campaign rows', (tester) async {
      await _pumpApp(tester, api: _FakeApi());
      expect(_offstage(const Key('referral_campaign_performance')), findsNothing);
    });
  });

  group('phone', () {
    testWidgets('lists active campaign links under the share actions',
        (tester) async {
      final api = _FakeApi()
        ..links = [
          _link(),
          _link(id: 'link-2', name: 'Meetup', code: 'MEETUP-1', status: 'PAUSED'),
          _link(id: 'link-3', name: 'Old', code: 'OLD-2026',
              expiresAt: '2026-01-01T00:00:00Z'),
        ];
      await _pumpApp(tester, api: api, width: 375);
      final list = _offstage(const Key('referral_campaign_links_phone'));
      expect(list, findsOneWidget);
      expect(_offstage(const Key('referral_campaign_link_phone_link-1')), findsOneWidget);
      expect(_offstage(const Key('referral_campaign_link_phone_link-2')), findsNothing,
          reason: 'paused links are not handed out');
      expect(_offstage(const Key('referral_campaign_link_phone_link-3')), findsNothing,
          reason: 'expired links are not handed out');
      await _reveal(tester, list);
      await tester.tap(find.byKey(const Key('referral_campaign_link_phone_link-1')));
      await tester.pumpAndSettle();
      expect(clipboard.last, 'https://example.com/signup?ref=AUTUMN26');
      expect(tester.takeException(), isNull);
    });

    testWidgets('mounts nothing without links or without the resource',
        (tester) async {
      await _pumpApp(tester, api: _FakeApi()..links = [], width: 375);
      expect(_offstage(const Key('referral_campaign_links_phone')), findsNothing);
      await _pumpApp(tester, api: _FakeApi()..linksFailure = _http(404), width: 375);
      expect(_offstage(const Key('referral_campaign_links_phone')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('pure parts', () {
    testWidgets('caption prefers the platform sentence and falls back to the invitation',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));
      final summary = ReferralSummary.fromJson(_summary);
      expect(
        referralCampaignCaption(context, appName: 'EXAMPLE', summary: summary, link: _link()),
        'Join me on Example and get \$3 after your first top-up.',
      );
      final bare = ReferralCampaignLink.fromJson(const {
        'id': 'x', 'code': 'BARE-1', 'shareUrl': 'https://example.com/signup?ref=BARE-1',
      });
      final caption = referralCampaignCaption(
          context, appName: 'EXAMPLE', summary: summary, link: bare);
      expect(caption, contains('EXAMPLE'));
      expect(caption, contains('BARE-1'));
      expect(caption, contains('https://example.com/signup?ref=BARE-1'));
      expect(referralCampaignOfferPreview(context, summary),
          '\$3 for them. \$1 + 0.25% for you.');
      expect(referralCampaignOfferPreview(context, const ReferralSummary()),
          'Invite friends and earn rewards.');
    });
  });
}

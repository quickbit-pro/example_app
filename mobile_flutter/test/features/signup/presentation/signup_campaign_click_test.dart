// Sign-up with a campaign link (addendum A of the campaign links contract):
// a code that check-referral reports as a campaign link records one click
// with the install's visitor id — never a personal code, never a dead link,
// never twice for the same code — and the completed sign-up hands the
// allowlisted `next` destination to the sign-in route.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/data/visitor_id_store.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends MobilePlatformApi {
  _FakeApi(this.answers) : super(Dio());

  final Map<String, ReferralWelcome?> answers;
  final checked = <String>[];
  final clicks = <({String code, String visitorId, String? locale})>[];
  bool clickThrows = false;

  @override
  Future<ReferralWelcome?> checkReferralCode(String referralCode) async {
    checked.add(referralCode.trim());
    return answers[referralCode.trim()];
  }

  @override
  Future<void> recordCampaignLinkClick(
    String code, {
    required String visitorId,
    String? locale,
  }) async {
    clicks.add((code: code, visitorId: visitorId, locale: locale));
    if (clickThrows) throw StateError('telemetry down');
  }
}

/// Lets a test complete the sign-up the way the real controller does once
/// the account exists: by publishing the action's result.
class _FakeActionController extends PlatformActionController {
  void complete(ActionResult result) => state = AsyncData(result);
}

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

const _campaign = ReferralWelcome(
  inviterDisplayName: 'Maja',
  welcomeAmount: 3,
  kind: 'CAMPAIGN_LINK',
  destination: 'rewards',
);

List<Override> _overrides(_FakeApi api) => [
      mobilePlatformApiProvider.overrideWithValue(api),
      mobileTenantConfigProvider.overrideWith((ref) async => _config),
      platformActionControllerProvider.overrideWith(_FakeActionController.new),
    ];

Future<void> _pump(WidgetTester tester, _FakeApi api,
    {String code = 'AUTUMN26'}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(api),
      child: MaterialApp(
        home: SignupScreen(
          initialReferralCode: code,
          referralSource: 'LINK',
          initialStep: 2,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Finder _codeField() =>
    find.byKey(const Key('signup_referral_code'), skipOffstage: false);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a campaign link records one click with the install visitor id',
      (tester) async {
    final api = _FakeApi({'AUTUMN26': _campaign});
    await _pump(tester, api);
    expect(api.checked, ['AUTUMN26']);
    final click = api.clicks.single;
    expect(click.code, 'AUTUMN26');
    expect(VisitorIdStore.isVisitorId(click.visitorId), isTrue);
    expect(click.locale, 'en');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(VisitorIdStore.preferenceKey), click.visitorId,
        reason: 'the id is persisted for the next visit');
    // The sign-up itself is untouched: the code stays, prefilled and locked.
    final field = tester.widget<EditableText>(find.descendant(
        of: _codeField(), matching: find.byType(EditableText, skipOffstage: false)));
    expect(field.controller.text, 'AUTUMN26');
    expect(field.readOnly, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same install sends the same visitor id next time',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      VisitorIdStore.preferenceKey: '5b2f7c3e-1c7a-4c1e-9f3d-2a6e8b4d9c10',
    });
    final api = _FakeApi({'AUTUMN26': _campaign});
    await _pump(tester, api);
    expect(api.clicks.single.visitorId, '5b2f7c3e-1c7a-4c1e-9f3d-2a6e8b4d9c10');
  });

  testWidgets('a dead link, a personal code and an unknown code click nothing',
      (tester) async {
    final api = _FakeApi({
      'OLDLINK': const ReferralWelcome.inactiveCampaignLink(),
      'FRIEND1': const ReferralWelcome(inviterDisplayName: 'Alex', kind: 'PERSONAL'),
    });
    // The dead link is announced and leaves the field open for another code.
    await _pump(tester, api, code: 'OLDLINK');
    expect(find.byKey(const Key('signup_referral_link_inactive'), skipOffstage: false),
        findsOneWidget);
    expect(api.clicks, isEmpty);
    await tester.enterText(_codeField(), 'FRIEND1');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(api.checked, ['OLDLINK', 'FRIEND1']);
    expect(api.clicks, isEmpty, reason: 'a personal code is no campaign');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a personal code prefilled from a link clicks nothing either',
      (tester) async {
    final api = _FakeApi({
      'FRIEND1': const ReferralWelcome(inviterDisplayName: 'Alex', kind: 'PERSONAL'),
    });
    await _pump(tester, api, code: 'FRIEND1');
    expect(api.checked, ['FRIEND1']);
    expect(api.clicks, isEmpty);
    // An unknown code (null answer) is not a campaign either.
    await _pump(tester, _FakeApi({}), code: 'NOPE');
    expect(api.clicks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing click never reaches the screen', (tester) async {
    final api = _FakeApi({'AUTUMN26': _campaign})..clickThrows = true;
    await _pump(tester, api);
    expect(api.clicks, hasLength(1));
    expect(find.byKey(const Key('signup_referral_link_inactive'), skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('destination after sign-up', () {
    Future<GoRouter> pumpRouter(WidgetTester tester, _FakeApi api,
        {String? next, String? code = 'AUTUMN26'}) async {
      final router = GoRouter(
        initialLocation: '/signup',
        routes: [
          GoRoute(
            path: '/signup',
            builder: (context, state) => SignupScreen(
              initialReferralCode: code,
              referralSource: code == null ? 'MANUAL_CODE' : 'LINK',
              next: next,
              initialStep: 2,
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) =>
                Text('login from=${state.uri.queryParameters['from']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(api),
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      return router;
    }

    Future<void> completeSignup(WidgetTester tester) async {
      final element = tester.element(find.byType(SignupScreen));
      final controller = ProviderScope.containerOf(element)
          .read(platformActionControllerProvider.notifier);
      (controller as _FakeActionController)
          .complete(const ActionResult(message: 'Account created'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I will do this at sign in'));
      await tester.pumpAndSettle();
    }

    testWidgets('the URL next wins and rides to sign-in as from',
        (tester) async {
      final api = _FakeApi({'AUTUMN26': _campaign});
      final router = await pumpRouter(tester, api, next: 'cards');
      await completeSignup(tester);
      expect(router.routeInformationProvider.value.uri.toString(),
          '/login?from=%2Fcards');
      expect(find.text('login from=/cards'), findsOneWidget);
    });

    testWidgets("without next, the link's own destination is honoured",
        (tester) async {
      final api = _FakeApi({'AUTUMN26': _campaign});
      final router = await pumpRouter(tester, api);
      await completeSignup(tester);
      expect(router.routeInformationProvider.value.uri.toString(),
          '/login?from=%2Frewards');
    });

    testWidgets('a personal code or no code lands on the plain sign-in',
        (tester) async {
      final personal = _FakeApi({
        'FRIEND1': const ReferralWelcome(kind: 'PERSONAL', destination: 'cards'),
      });
      var router = await pumpRouter(tester, personal, code: 'FRIEND1');
      await completeSignup(tester);
      expect(router.routeInformationProvider.value.uri.toString(), '/login');

      router = await pumpRouter(tester, _FakeApi({}), code: null);
      await completeSignup(tester);
      expect(router.routeInformationProvider.value.uri.toString(), '/login');
    });
  });
}

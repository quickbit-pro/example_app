import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/router/app_router.dart';
import 'package:mobile_flutter/app/routes.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/onboarding/presentation/required_tier_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';

const _tierId = 7;
final _tier = PlatformResource.fromJson(const {'Id': _tierId, 'Name': 'Basic'});
final _profile = UserProfile.fromJson(const {
  'id': 'customer',
  'accountType': 'personal',
  'kycStatus': 'approved',
});

class _Auth extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
        session: AuthSession(
          accessToken: 'test-token',
          refreshToken: '',
          userName: 'Customer',
          email: 'customer@example.test',
        ),
      );
}

class _TierApi extends MobilePlatformApi {
  _TierApi({this.saved = false, this.failLookup = false}) : super(Dio());

  bool saved;
  bool failLookup;
  int selectionCalls = 0;

  @override
  Future<PlatformResource> getCurrentTier() async {
    if (failLookup) throw StateError('Tier lookup failed');
    return saved ? _tier : PlatformResource.fromJson(const {});
  }

  @override
  Future<ActionResult> selectTier({
    required int tierId,
    String? tierCycle,
    bool onboarding = false,
  }) async {
    expect(tierId, _tierId);
    expect(onboarding, isTrue);
    selectionCalls++;
    return const ActionResult(message: 'Tier selection submitted');
  }
}

Future<GoRouter> _start(WidgetTester tester, _TierApi api) async {
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_Auth.new),
    authTokenProvider.overrideWith((ref) => 'test-token'),
    mobilePlatformApiProvider.overrideWithValue(api),
    bankingProfileProvider.overrideWith((ref) async => _profile),
    tiersProvider.overrideWith((ref) async => [_tier]),
    cardTierProvider(_tierId.toString())
        .overrideWith((ref) async => PlatformResource.fromJson(const {})),
    dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
          profile: _profile,
          accounts: const [],
          cards: const [],
          transactions: const [],
          onboarding: const [],
        )),
  ]);
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
  final router = container.read(routerProvider);
  router.go(
      '${AppRoutes.login}?from=${Uri.encodeComponent(AppRoutes.accountSetup)}');
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('tier selection blocks login and direct links until saved',
      (tester) async {
    final api = _TierApi();
    final router = await _start(tester, api);

    expect(find.byType(RequiredTierScreen), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);

    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.chooseTier);

    router.go(AppRoutes.accountSetup);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose this plan'));
    await tester.tap(find.text('Choose this plan'));
    await tester.pumpAndSettle();

    expect(api.selectionCalls, 1);
    expect(find.byType(RequiredTierScreen), findsOneWidget);

    api.saved = true;
    await tester.ensureVisible(find.text('Check status'));
    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();

    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.accountSetup);
    expect(find.byType(RequiredTierScreen), findsNothing);
  });

  testWidgets('saved tier goes directly to the requested route',
      (tester) async {
    final router = await _start(tester, _TierApi(saved: true));

    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.accountSetup);
    expect(find.byType(RequiredTierScreen), findsNothing);
  });

  testWidgets('tier lookup errors allow retry without opening the app',
      (tester) async {
    final api = _TierApi(failLookup: true);
    final router = await _start(tester, api);

    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.chooseTier);
    expect(find.text('Could not check your tier'), findsOneWidget);
    expect(find.text('Basic'), findsNothing);

    api.failLookup = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Basic'), findsOneWidget);
    expect(
        router.routeInformationProvider.value.uri.path, AppRoutes.chooseTier);
  });
}

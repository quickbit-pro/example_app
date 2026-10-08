// The analytics provider: one value per period, scoped to the summary's
// programme, and "not served" answered as null rather than as a failure.
//
// A build in the field may talk to a backend that predates the analytics
// resource; the screens must keep every other section and simply leave the
// analytics out. Anything other than a 404 is still a failure the workspace
// can offer a retry for.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

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
  'referrals': {'invited': 8, 'qualified': 3, 'inProgress': 2, 'earning': 3},
  'rewards': {'pending': 2, 'paid': 10, 'currency': 'USD'},
  'programId': 'prog-1',
  'canInvite': true,
};

class _FakeApi extends MobilePlatformApi {
  _FakeApi() : super(Dio());

  final calls = <({String? programId, ReferralAnalyticsRange range})>[];
  Object? failure;

  @override
  Future<ReferralMemberAnalytics> getReferralMemberAnalytics({
    String? programId,
    ReferralAnalyticsRange range = ReferralAnalyticsRange.thirtyDays,
    DateTime? from,
    DateTime? to,
  }) async {
    calls.add((programId: programId, range: range));
    if (failure != null) throw failure!;
    return ReferralMemberAnalytics(
      range: range,
      totals: ReferralAnalyticsTotals(qualified: range.days ?? 0),
    );
  }
}

DioException _http(int status) {
  final request = RequestOptions(path: '/api/v1/mobile/rewards/referrals/analytics');
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

ProviderContainer _container(_FakeApi api, {RewardsSnapshot? snapshot}) {
  final container = ProviderContainer(overrides: [
    mobilePlatformApiProvider.overrideWithValue(api),
    rewardsSnapshotProvider.overrideWith((ref) async =>
        snapshot ??
        const RewardsSnapshot(config: _config, referralSummary: _summary)),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('requests each period once, scoped to the summary programme', () async {
    final api = _FakeApi();
    final container = _container(api);

    final week = await container
        .read(referralAnalyticsProvider(ReferralAnalyticsRange.sevenDays).future);
    expect(week?.totals.qualified, 7);
    expect(api.calls, [(programId: 'prog-1', range: ReferralAnalyticsRange.sevenDays)]);

    // The same key is the same value; another key is another request.
    await container
        .read(referralAnalyticsProvider(ReferralAnalyticsRange.sevenDays).future);
    expect(api.calls, hasLength(1));
    final month = await container
        .read(referralAnalyticsProvider(ReferralAnalyticsRange.month).future);
    expect(month?.range, ReferralAnalyticsRange.month);
    expect(api.calls.last.range, ReferralAnalyticsRange.month);
    expect(api.calls, hasLength(2));
  });

  test('a backend without the resource answers null, not an error', () async {
    final api = _FakeApi()..failure = _http(404);
    final container = _container(api);

    final analytics = await container
        .read(referralAnalyticsProvider(ReferralAnalyticsRange.thirtyDays).future);
    expect(analytics, isNull);
    expect(api.calls, hasLength(1));
  });

  test('any other failure is still a failure', () async {
    final api = _FakeApi()..failure = _http(503);
    final container = _container(api);

    await expectLater(
      container.read(
          referralAnalyticsProvider(ReferralAnalyticsRange.thirtyDays).future),
      throwsA(isA<DioException>()),
    );
  });

  test('referrals off is null without a request', () async {
    final api = _FakeApi();
    final container = _container(
      api,
      snapshot: const RewardsSnapshot(
        config: MobileTenantConfig(
          companyName: 'Example',
          brandName: 'Example',
          referralsEnabled: false,
          referralRegistrationMode: 'optional',
          vouchersEnabled: false,
          existingAccountClaimEnabled: false,
          boomFiExchangeEnabled: false,
          walletOutflowsEnabled: false,
          equalsMoneyEnabled: true,
        ),
      ),
    );

    final analytics = await container
        .read(referralAnalyticsProvider(ReferralAnalyticsRange.month).future);
    expect(analytics, isNull);
    expect(api.calls, isEmpty);
  });
}

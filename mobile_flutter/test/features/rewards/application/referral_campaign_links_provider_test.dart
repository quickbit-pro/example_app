// The campaign links provider: the member's links, "not deployed" answered as
// null (the tab and the phone list stay out), an empty list kept as an empty
// list (the tab shows its empty state), and everything else a failure.
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
  'programId': 'prog-1',
  'canInvite': true,
};

class _FakeApi extends MobilePlatformApi {
  _FakeApi() : super(Dio());

  var listCalls = 0;
  final performanceCalls = <({String linkId, ReferralAnalyticsRange range})>[];
  Object? failure;
  List<ReferralCampaignLink> links = const [];

  @override
  Future<List<ReferralCampaignLink>> getReferralCampaignLinks({
    String? programId,
    ReferralCampaignLinkStatus? status,
  }) async {
    listCalls++;
    if (failure != null) throw failure!;
    return links;
  }

  @override
  Future<ReferralCampaignLinkPerformance> getReferralCampaignLinkPerformance(
    String linkId, {
    ReferralAnalyticsRange range = ReferralAnalyticsRange.thirtyDays,
  }) async {
    performanceCalls.add((linkId: linkId, range: range));
    return ReferralCampaignLinkPerformance(signups: range.days ?? 0);
  }
}

DioException _http(int status) {
  final request =
      RequestOptions(path: '/api/v1/mobile/rewards/referrals/links');
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
  test('lists the member links once and keeps an empty list as a list',
      () async {
    final api = _FakeApi();
    final container = _container(api);
    final links = await container.read(referralCampaignLinksProvider.future);
    expect(links, isEmpty);
    expect(links, isNotNull);
    await container.read(referralCampaignLinksProvider.future);
    expect(api.listCalls, 1);
  });

  test('a backend without the resource answers null, not an error', () async {
    final api = _FakeApi()..failure = _http(404);
    final container = _container(api);
    expect(await container.read(referralCampaignLinksProvider.future), isNull);
  });

  test('any other failure is still a failure', () async {
    final api = _FakeApi()..failure = _http(500);
    final container = _container(api);
    await expectLater(
      container.read(referralCampaignLinksProvider.future),
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
    expect(await container.read(referralCampaignLinksProvider.future), isNull);
    expect(api.listCalls, 0);
  });

  test('performance is keyed by link and period', () async {
    final api = _FakeApi();
    final container = _container(api);
    final week = await container.read(referralCampaignLinkPerformanceProvider(
      (linkId: 'link-1', range: ReferralAnalyticsRange.sevenDays),
    ).future);
    expect(week.signups, 7);
    await container.read(referralCampaignLinkPerformanceProvider(
      (linkId: 'link-1', range: ReferralAnalyticsRange.sevenDays),
    ).future);
    expect(api.performanceCalls, hasLength(1));
    await container.read(referralCampaignLinkPerformanceProvider(
      (linkId: 'link-1', range: ReferralAnalyticsRange.month),
    ).future);
    expect(api.performanceCalls, hasLength(2));
    expect(api.performanceCalls.last.range, ReferralAnalyticsRange.month);
  });
}

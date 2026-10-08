import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../banking/application/banking_providers.dart';
import '../../rewards/domain/rewards_models.dart';
import '../../rewards/domain/referral_lifecycle.dart';
import '../../rewards/domain/referral_member_status.dart';
import '../../signup/domain/referral_quote.dart';
import '../../wallets/domain/exchange_models.dart';
import '../data/mobile_platform_api.dart';
import '../../dashboard/domain/market_rates.dart';
import '../../dashboard/domain/dashboard_models.dart';
import '../../cards/domain/card_control_capabilities.dart';
import '../../cards/domain/card_limits.dart';

final mobilePlatformApiProvider = Provider<MobilePlatformApi>((ref) {
  return MobilePlatformApi(ref.watch(dioProvider));
});

final mobileTenantConfigProvider = FutureProvider<MobileTenantConfig>((ref) {
  return ref.watch(mobilePlatformApiProvider).getMobileConfig();
});

final marketRatesProvider = FutureProvider<MarketRateTable>((ref) {
  return ref.watch(mobilePlatformApiProvider).getMarketRates();
});

final portfolioEstimateProvider = FutureProvider<PortfolioEstimate>((ref) {
  return ref.watch(mobilePlatformApiProvider).getPortfolioEstimate();
});

final exchangeOverviewProvider = FutureProvider<BoomFiExchangeOverview>((ref) {
  return ref.watch(mobilePlatformApiProvider).getExchangeOverview();
});

final exchangeTransfersProvider = FutureProvider<List<BoomFiTransfer>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getExchangeTransfers();
});

final rewardsSnapshotProvider = FutureProvider<RewardsSnapshot>((ref) async {
  final api = ref.watch(mobilePlatformApiProvider);
  final config = await ref.watch(mobileTenantConfigProvider.future);
  Map<String, dynamic>? referralSummary;
  Map<String, dynamic>? voucherStatus;
  List<Map<String, dynamic>> assignedVouchers = const [];
  List<ReferralReward> referralRewards = const [];
  List<ReferralFriend> referralFriends = const [];
  ReferralSummary? summary;

  if (config.referralsEnabled) {
    try {
      referralSummary = await api.getReferralSummary();
      summary = ReferralSummary.fromJson(referralSummary);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      referralSummary = const {'enabled': false};
    }
    if (summary != null && summary.enabled) {
      // The ledger and the friends list are v2 resources; a backend that
      // does not serve them yet leaves the summary usable on its own.
      try {
        referralRewards = await api.getReferralRewards(
          programId: summary.programId,
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
      try {
        referralFriends = await api.getReferralFriends(
          programId: summary.programId,
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
    }
  }
  // Voucher status and assigned vouchers only matter when rewards are
  // delivered as vouchers; a wallet-credit programme pays the balance
  // directly and has nothing to redeem.
  final voucherDelivery = summary == null || summary.usesVouchers;
  if (config.vouchersEnabled && voucherDelivery) {
    try {
      voucherStatus = await api.getVoucherStatus();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != 401 && status != 403 && status != 404) rethrow;
      voucherStatus = const {'enabled': true, 'statusUnavailable': true};
    }
    if (config.referralsEnabled) {
      try {
        assignedVouchers = await api.getAssignedReferralVouchers();
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
    }
  }

  return RewardsSnapshot(
    config: config,
    referralSummary: referralSummary,
    assignedVouchers: assignedVouchers,
    voucherStatus: voucherStatus,
    referralRewards: referralRewards,
    referralFriends: referralFriends,
  );
});

/// The member's referral analytics for one period, or null when there are
/// none to show: referrals off, or a backend that does not serve the
/// resource yet (404). The screens hide their analytics blocks on null and
/// never show an error for it. Keyed by range so the workspace's period
/// switch and the phone's month line each hold their own value; scoped to
/// the summary's programme like the ledger and the friends list, and
/// refreshed with the snapshot (pull to refresh, terms accepted).
final referralAnalyticsProvider =
    FutureProvider.family<ReferralMemberAnalytics?, ReferralAnalyticsRange>(
        (ref, range) async {
  final snapshot = await ref.watch(rewardsSnapshotProvider.future);
  final summary = snapshot.summary;
  if (!snapshot.referralsEnabled || summary == null || !summary.enabled) {
    return null;
  }
  try {
    return await ref
        .watch(mobilePlatformApiProvider)
        .getReferralMemberAnalytics(
          programId: summary.programId,
          range: range,
        );
  } on DioException catch (error) {
    if (error.response?.statusCode != 404) rethrow;
    return null;
  }
});

/// The member's campaign links, or null when there are none to show: referrals
/// off, the member cannot invite, or a backend that does not serve the
/// resource (404). Null hides the Links tab and the phone's campaign list;
/// an empty list shows the tab with its empty state. Refreshed with the
/// snapshot (pull to refresh, terms accepted) and after every create or
/// status change.
final referralCampaignLinksProvider =
    FutureProvider<List<ReferralCampaignLink>?>((ref) async {
  final snapshot = await ref.watch(rewardsSnapshotProvider.future);
  final summary = snapshot.summary;
  if (!snapshot.referralsEnabled || summary == null || !summary.enabled) {
    return null;
  }
  try {
    return await ref
        .watch(mobilePlatformApiProvider)
        .getReferralCampaignLinks();
  } on DioException catch (error) {
    if (error.response?.statusCode != 404) rethrow;
    return null;
  }
});

/// One link's figures for one period, keyed by both so the performance
/// panel's period switch holds each value it has seen.
final referralCampaignLinkPerformanceProvider = FutureProvider.family<
    ReferralCampaignLinkPerformance,
    ({String linkId, ReferralAnalyticsRange range})>((ref, key) {
  return ref
      .watch(mobilePlatformApiProvider)
      .getReferralCampaignLinkPerformance(
        key.linkId,
        range: key.range,
      );
});

final kycDetailedStatusProvider = FutureProvider<KycDetailedStatus>((ref) {
  return ref.watch(mobilePlatformApiProvider).getDetailedKycStatus();
});

final providersProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getProviders();
});

final equalsBankingInfoProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getEqualsBankingInfos();
});

/// Equals Money budgets. On installations without Equals Money the provider
/// rejects the call (404), so answer with an empty list instead of asking.
final budgetsProvider = FutureProvider<List<PlatformResource>>((ref) async {
  bool equalsEnabled;
  try {
    equalsEnabled =
        (await ref.watch(mobileTenantConfigProvider.future)).equalsMoneyEnabled;
  } catch (_) {
    equalsEnabled = true;
  }
  if (!equalsEnabled) return const [];
  return ref.watch(mobilePlatformApiProvider).getBudgets();
});

final tiersProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getTiers();
});

final currentTierProvider = FutureProvider<PlatformResource?>((ref) async {
  final api = ref.watch(mobilePlatformApiProvider);
  // A transport/provider failure is unknown, never proof that no tier exists.
  final current = await api.getCurrentTier();
  final currentTierId = _tierId(current);
  if (currentTierId == null) return null;
  try {
    final tiers = await ref.watch(tiersProvider.future);
    for (final tier in tiers) {
      if (_tierId(tier) == currentTierId) return tier;
    }
  } catch (_) {
    // The selected ID remains valid even if its catalogue details fail to load.
  }
  return current;
});

final cardTierProvider =
    FutureProvider.family<PlatformResource, String>((ref, cardTierId) {
  return ref.watch(mobilePlatformApiProvider).getCardTier(cardTierId);
});

final bankingBalancesProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getBankingBalance();
});

final mandatesProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getMandates();
});

final paymentsProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getPayments();
});

final paymentRequestsProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getPaymentRequests();
});

final walletsProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getWallets();
});

final userWalletsProvider = FutureProvider<List<PlatformResource>>((ref) async {
  return ref.watch(mobilePlatformApiProvider).getUserWallets();
});

final assetsProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(mobilePlatformApiProvider).getAssets();
});

final userAssetsProvider = FutureProvider<List<PlatformResource>>((ref) async {
  return ref.watch(mobilePlatformApiProvider).getUserAssets();
});

final depositAddressesProvider =
    FutureProvider<List<PlatformResource>>((ref) async {
  try {
    final wallets = await ref.watch(userWalletsProvider.future);
    final addresses = depositAddressesFromWallets(wallets);
    if (addresses.isNotEmpty) {
      return addresses;
    }
  } catch (_) {
    // Fall back to the mobile backend address endpoint if Hoppa V2 wallet
    // data is unavailable for the current user.
  }

  return ref.watch(mobilePlatformApiProvider).getDepositAddresses();
});

final cryptoAddressesProvider = FutureProvider<List<PlatformResource>>((ref) {
  return ref.watch(depositAddressesProvider.future);
});

final cardDetailProvider =
    FutureProvider.family<PaymentCard, String>((ref, cardId) async {
  final detail =
      await ref.watch(mobilePlatformApiProvider).getCardDetail(cardId);
  final cards = await ref.watch(cardsProvider.future);
  for (final card in cards) {
    if (card.id == detail.id || card.id == cardId) {
      return detail.withFallback(card);
    }
  }

  return detail;
});

/// Overview balances must not fall back to potentially stale list balances.
final currentCardsProvider = FutureProvider<List<PaymentCard>>((ref) async {
  final cards = await ref.watch(cardsProvider.future);
  return Future.wait([
    for (final card in cards)
      if (card.status == CardStatus.cancelled || card.id.trim().isEmpty)
        Future.value(card)
      else
        ref.watch(cardDetailProvider(card.id).future),
  ]);
});

final cardTransactionsProvider =
    FutureProvider.family<List<PlatformResource>, String>((ref, cardId) {
  return ref.watch(mobilePlatformApiProvider).getCardTransactions(cardId);
});

/// Current card limits and the tier ceilings; the app enforces the ceilings
/// before calling the provider, which enforces them again.
final cardLimitsProvider =
    FutureProvider.family<CardLimitsInfo, String>((ref, cardId) {
  return ref.watch(mobilePlatformApiProvider).getCardLimits(cardId);
});

final cardControlCapabilitiesProvider =
    FutureProvider.family<CardControlCapabilities, String>((ref, cardId) {
  return ref.watch(mobilePlatformApiProvider).getCardControls(cardId);
});

final transactionStatsProvider =
    FutureProvider<TransactionStatusSummary>((ref) {
  return ref.watch(mobilePlatformApiProvider).getTransactionStats();
});

final platformActionControllerProvider =
    AsyncNotifierProvider<PlatformActionController, ActionResult?>(
  PlatformActionController.new,
);

class PlatformActionController extends AsyncNotifier<ActionResult?> {
  @override
  Future<ActionResult?> build() async {
    return null;
  }

  Future<void> run(
      Future<ActionResult> Function(MobilePlatformApi api) action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => action(ref.read(mobilePlatformApiProvider)),
    );
    _invalidateActionData();
  }

  Future<void> selectTier({
    required int tierId,
    String? tierCycle,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(mobilePlatformApiProvider);
      final result = await api.selectTier(
        tierId: tierId,
        tierCycle: tierCycle,
      );
      _invalidateTierProviders();

      try {
        final current = await api.getCurrentTier();
        _invalidateTierProviders();
        if (_tierId(current) == tierId) {
          return ActionResult(
            message: 'Tier selection confirmed.',
            reference: result.reference,
            metadata: {
              ...result.metadata,
              'confirmedTierId': tierId,
            },
          );
        }
      } catch (error) {
        if (_isAmbiguousTierResult(result)) {
          throw Exception(_tierRefreshErrorMessage(result, error));
        }
      }

      if (_isAmbiguousTierResult(result)) {
        return ActionResult(
          message: 'Tier selection received. Your tier status is updating.',
          reference: result.reference,
          metadata: result.metadata,
        );
      }

      return result;
    });
    _invalidateActionData();
  }

  void _invalidateActionData() {
    ref.invalidate(providersProvider);
    ref.invalidate(equalsBankingInfoProvider);
    ref.invalidate(budgetsProvider);
    ref.invalidate(portfolioEstimateProvider);
    _invalidateTierProviders();
    ref.invalidate(bankingBalancesProvider);
    ref.invalidate(mandatesProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(paymentRequestsProvider);
    ref.invalidate(walletsProvider);
    ref.invalidate(assetsProvider);
    ref.invalidate(userAssetsProvider);
    ref.invalidate(depositAddressesProvider);
    ref.invalidate(cryptoAddressesProvider);
    ref.invalidate(cardDetailProvider);
    ref.invalidate(cardTransactionsProvider);
    ref.invalidate(transactionStatsProvider);
    ref.invalidate(activityTransactionsProvider);
    ref.invalidate(activityAccountTransactionsProvider);
    ref.invalidate(activityCardTransactionsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(onboardingProvider);
    ref.invalidate(kycDetailedStatusProvider);
  }

  void _invalidateTierProviders() {
    ref.invalidate(tiersProvider);
    ref.invalidate(currentTierProvider);
  }
}

int? _tierId(PlatformResource tier) {
  final metadata = tier.metadata;
  final value = _textValue(metadata, const [
        'tierId',
        'TierId',
        'selectedTierId',
        'SelectedTierId',
        'id',
        'Id',
      ]) ??
      (tier.id.trim().isEmpty || tier.id == 'item' ? null : tier.id);

  return value == null ? null : int.tryParse(value);
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return null;
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }

  return null;
}

bool _isAmbiguousTierResult(ActionResult result) {
  final metadata = result.metadata;
  return _boolValue(metadata['success'] ?? metadata['Success']) == false ||
      _boolValue(metadata['isSuccess'] ?? metadata['IsSuccess']) == false;
}

String _tierRefreshErrorMessage(ActionResult result, Object refreshError) {
  final detail = _textValue(result.metadata, const [
    'errorMessage',
    'ErrorMessage',
    'failureReason',
    'FailureReason',
    'message',
    'Message',
    'detail',
    'Detail',
  ]);
  if (detail != null) {
    return detail;
  }

  return refreshError.toString();
}

/// Null means this server does not expose observations; never synthesize a
/// forecast from today's level or turn a network failure into a zero balance.
final referralLevelLifecycleProvider =
    FutureProvider<ReferralLevelLifecycle?>((ref) async {
  final summary = (await ref.watch(rewardsSnapshotProvider.future)).summary;
  if (summary == null || !summary.enabled) return null;
  try {
    return await ref
        .watch(mobilePlatformApiProvider)
        .getReferralLevelLifecycle(programId: summary.programId);
  } on DioException catch (error) {
    if (error.response?.statusCode == 404 ||
        error.response?.statusCode == 501) {
      return null;
    }
    rethrow;
  }
});

final referralGeoStatusProvider =
    FutureProvider<ReferralGeoStatus?>((ref) async {
  final snapshot = await ref.watch(rewardsSnapshotProvider.future);
  if (!snapshot.referralsEnabled) return null;
  try {
    return await ref.watch(mobilePlatformApiProvider).getReferralGeoStatus();
  } on DioException catch (error) {
    if (error.response?.statusCode == 404 ||
        error.response?.statusCode == 501) {
      return null;
    }
    rethrow;
  }
});

final referralAttributionOutcomeProvider =
    FutureProvider<ReferralSignupOutcome?>((ref) async {
  final snapshot = await ref.watch(rewardsSnapshotProvider.future);
  if (!snapshot.referralsEnabled) return null;
  try {
    return await ref
        .watch(mobilePlatformApiProvider)
        .getReferralAttributionOutcome();
  } on DioException catch (error) {
    if (error.response?.statusCode == 404 ||
        error.response?.statusCode == 501) {
      return null;
    }
    rethrow;
  }
});

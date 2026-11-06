import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/auth_token_provider.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/cache/display_snapshot.dart';
import '../../../core/models/platform_models.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/service_onboarding.dart';
import 'onboarding_notice_store.dart';

const _root = '/api/v1/mobile/onboarding/cdd';
final serviceOnboardingClockProvider =
    Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());
final onboardingNoticeStoreProvider =
    FutureProvider<OnboardingNoticeStore>((ref) async {
  final owner = ref.watch(displayCacheOwnerProvider);
  return OnboardingNoticeStore(await SharedPreferences.getInstance(), owner);
});

/// Read-only status lookup. Opening Home never creates/submits an application.
final serviceOnboardingStatusProvider =
    FutureProvider.autoDispose<List<ServiceOnboardingItem>>((ref) async {
  final generation = ref.watch(authSessionGenerationProvider);
  final owner = ref.watch(displayCacheOwnerProvider);
  if (owner == null) return const [];
  final config = await ref.watch(mobileTenantConfigProvider.future);
  final dio = ref.watch(dioProvider);
  final preferences = _map((await dio.get('$_root/preferences')).data);
  final cards = preferences['cryptoCard'] == true;
  final banking = config.equalsMoneyEnabled &&
      preferences['enabled'] == true &&
      preferences['banking'] == true;
  final exchange = config.boomFiExchangeEnabled &&
      preferences['enabled'] == true &&
      preferences['exchange'] == true;
  if (!cards && !banking && !exchange) return const [];
  final results = await Future.wait<Object?>([
    preferences['enabled'] == true
        ? _optional(() async => (await dio.get(_root)).data)
        : Future.value(null),
    cards || banking
        ? _optional(() => ref.watch(kycDetailedStatusProvider.future))
        : Future.value(null),
    exchange
        ? _optional(() => ref.watch(exchangeVerificationProvider.future))
        : Future.value(null),
  ]);
  final progress = results[0] is Map ? _map(results[0]) : <String, dynamic>{};
  if (ref.read(authSessionGenerationProvider) != generation) return const [];
  final detailed = results[1] as KycDetailedStatus?;
  if (cards) {
    final current = normalizedOnboardingStatus(detailed?.interlaceStatus);
    progress['interlace'] = detailed == null
        ? 'unavailable'
        : detailed.hasInterlaceAction
            ? 'need_update'
            : current.isNotEmpty &&
                    onboardingStage(current) != OnboardingStage.complete
                ? current
                : detailed.interlaceApproved == false &&
                        onboardingStage(detailed.cardIssuerStatus) ==
                            OnboardingStage.complete
                    ? 'in_progress'
                    : detailed.isCardIssuerApproved
                        ? 'complete'
                        : detailed.cardIssuerStatus;
    progress['interlaceCompletedAt'] =
        detailed?.interlaceCompletedAt?.toIso8601String();
  }
  if (banking) {
    final current =
        normalizedOnboardingStatus(detailed?.equalsMoneyStatus).isNotEmpty
            ? detailed!.equalsMoneyStatus
            : detailed?.equalsMoneyApplicationStatus;
    final currentStage = onboardingStage(current);
    progress['equalsMoney'] = detailed == null
        ? 'unavailable'
        : detailed.requiresEqualsMoneyAction ||
                currentStage == OnboardingStage.needUpdate
            ? 'need_update'
            : currentStage == OnboardingStage.rejected
                ? 'rejected'
                : detailed.equalsMoneyApproved == false &&
                        !detailed.hasEqualsMoneyAccount &&
                        currentStage == OnboardingStage.complete
                    ? 'in_progress'
                    : detailed.isEqualsMoneyOnboarded
                        ? 'complete'
                        : onboardingStage(progress['equalsMoney']) ==
                                OnboardingStage.needUpdate
                            ? 'need_update'
                            : detailed.hasEqualsMoneyReviewState
                                ? 'in_progress'
                                : current ??
                                    progress['equalsMoney'] ??
                                    detailed.bankStatus;
    progress['equalsMoneyCompletedAt'] =
        detailed?.equalsMoneyCompletedAt?.toIso8601String();
  }
  if (exchange) {
    final verification = results[2] is Map ? _map(results[2]) : null;
    if (verification == null ||
        verification['usesSharedStagingOrganization'] == true) {
      progress['boomFi'] = 'unavailable';
    } else {
      final provider = verification['provider'] is Map
          ? _map(verification['provider'])
          : <String, dynamic>{};
      final providerStatus = normalizedOnboardingStatus(provider['kycStatus']);
      final nextAction =
          normalizedOnboardingStatus(provider['nextAction']).split(':').first;
      final submitted = provider['actionSubmitted'] == true;
      final needsUpdate = !submitted &&
          (nextAction.endsWith('_required') ||
              const {'need_update', 'resubmission_required', 'action_required'}
                  .contains(providerStatus));
      progress['boomFi'] =
          const {'rejected', 'failed', 'declined'}.contains(providerStatus)
              ? 'rejected'
              : needsUpdate
                  ? 'need_update'
                  : providerStatus == 'accepted' &&
                          verification['hasProviderAccount'] == true
                      ? (submitted && nextAction.endsWith('_required')
                          ? 'in_progress'
                          : 'complete')
                      : providerStatus.isNotEmpty
                          ? providerStatus
                          : verification['status'] == 'approved'
                              ? progress['boomFi'] ?? 'not_started'
                              : verification['status'] ??
                                  progress['boomFi'] ??
                                  'not_started';
      progress['boomFiCompletedAt'] =
          provider['completedAt'] ?? provider['approvedAt'];
    }
  }
  return remainingServiceOnboarding(
          cardsEnabled: cards,
          bankingEnabled: banking,
          exchangeEnabled: exchange,
          preferences: preferences,
          progress: progress)
      .map((item) => item.forOwner(owner))
      .toList(growable: false);
});

final homeServiceOnboardingProvider =
    FutureProvider.autoDispose<List<ServiceOnboardingItem>>((ref) async {
  final owner = ref.watch(displayCacheOwnerProvider);
  if (owner == null) return const [];
  final now = ref.watch(serviceOnboardingClockProvider);
  // Capture both reads before awaiting so a session switch cannot pair an old
  // customer's response with the next customer's completion preferences.
  final itemsFuture = ref.watch(serviceOnboardingStatusProvider.future);
  final storeFuture = ref.watch(onboardingNoticeStoreProvider.future);
  final items = await itemsFuture;
  if (items.isEmpty || items.any((item) => item.owner != owner)) {
    return const [];
  }
  final store = await storeFuture;
  if (store.owner != owner) return const [];
  return store.visible(items, now());
});

final serviceOnboardingRefreshProvider = Provider<void Function()>((ref) => () {
      ref.invalidate(kycDetailedStatusProvider);
      ref.invalidate(exchangeVerificationProvider);
      ref.invalidate(serviceOnboardingStatusProvider);
      ref.invalidate(homeServiceOnboardingProvider);
    });

void refreshServiceOnboarding(WidgetRef ref) =>
    ref.read(serviceOnboardingRefreshProvider)();

Future<Object?> _optional(Future<Object?> Function() read) async {
  try {
    return await read();
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _map(Object? data) {
  if (data is! Map) throw const FormatException('Missing onboarding status');
  return data.map((key, value) {
    final name = key.toString();
    return MapEntry(
        name.isEmpty ? name : name[0].toLowerCase() + name.substring(1), value);
  });
}

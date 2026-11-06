import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart' show Response;

import '../../../core/api/auth_token_provider.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/models/platform_models.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/service_onboarding.dart';

const _root = '/api/v1/mobile/onboarding/cdd';

/// Home only reads existing progress. It never starts or submits onboarding.
final homeServiceOnboardingProvider =
    FutureProvider.autoDispose<List<ServiceOnboardingItem>>((ref) async {
  ref.watch(authSessionGenerationProvider);
  final config = await ref.watch(mobileTenantConfigProvider.future);
  if (!config.unifiedCddOnboardingEnabled ||
      (!config.equalsMoneyEnabled && !config.boomFiExchangeEnabled)) {
    return const [];
  }
  final dio = ref.watch(dioProvider);
  final preferences = _map((await dio.get('$_root/preferences')).data);
  if (preferences['enabled'] != true ||
      !(config.equalsMoneyEnabled && preferences['banking'] == true ||
          config.boomFiExchangeEnabled && preferences['exchange'] == true)) {
    return const [];
  }
  final bankingSelected =
      config.equalsMoneyEnabled && preferences['banking'] == true;
  final exchangeSelected =
      config.boomFiExchangeEnabled && preferences['exchange'] == true;
  final results = await Future.wait<Object?>([
    dio.get(_root),
    bankingSelected
        ? ref.watch(kycDetailedStatusProvider.future)
        : Future.value(null),
    exchangeSelected
        ? ref.watch(exchangeVerificationProvider.future)
        : Future.value(null),
  ]);
  final data = (results[0] as Response).data;
  // No CDD session yet means the selected services have not been started.
  final progress =
      data == null || data == '' ? <String, dynamic>{} : _map(data);
  // Dispatch records can remain submitted after a provider approves the user.
  // Use the same readiness checks as the Banking and Exchange screens.
  final banking = results[1] as KycDetailedStatus?;
  if (banking?.isEqualsMoneyOnboarded == true) {
    progress['equalsMoney'] = 'approved';
  } else if (banking?.requiresEqualsMoneyAction == true) {
    progress['equalsMoney'] = 'action_required';
  } else if (banking?.hasEqualsMoneyReviewState == true &&
      !const {
        'invite_required',
        'payment_required',
        'rejected',
        'action_required'
      }.contains(progress['equalsMoney'])) {
    progress['equalsMoney'] = 'submitted';
  }
  final verification = results[2] as Map<String, dynamic>?;
  final provider = verification?['provider'];
  if (verification?['hasProviderAccount'] == true &&
      provider is Map &&
      provider['kycStatus']?.toString().toLowerCase() == 'accepted') {
    progress['boomFi'] = 'approved';
  } else if (provider is Map) {
    final status = provider['kycStatus']?.toString().toLowerCase();
    if (const {'rejected', 'failed'}.contains(status)) {
      progress['boomFi'] = 'rejected';
    } else if (const {'submitted', 'pending', 'in_review', 'under_review'}
        .contains(status)) {
      progress['boomFi'] = 'submitted';
    }
  }
  return remainingServiceOnboarding(
    bankingEnabled: config.equalsMoneyEnabled,
    exchangeEnabled: config.boomFiExchangeEnabled,
    preferences: preferences,
    progress: progress,
  );
});

Map<String, dynamic> _map(Object? data) {
  if (data is! Map) throw const FormatException('Missing onboarding status');
  return data.map((key, value) {
    final name = key.toString();
    return MapEntry(
        name.isEmpty ? name : name[0].toLowerCase() + name.substring(1), value);
  });
}

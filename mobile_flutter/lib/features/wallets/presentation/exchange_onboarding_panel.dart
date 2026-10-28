import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/dio_provider.dart';
import '../../kyc/presentation/unified_cdd_screen.dart';
import '../../platform/application/platform_providers.dart';

/// A null result preserves the existing journey for customers who did not
/// select Exchange during unified onboarding. Never create an application here.
final unifiedExchangeProgressProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final config = await ref.watch(mobileTenantConfigProvider.future);
  if (!config.unifiedCddOnboardingEnabled) return null;
  final dio = ref.watch(dioProvider);
  final preferences = (await dio.get('$unifiedCddRoot/preferences')).data;
  if (preferences is! Map || preferences['enabled'] is! bool) {
    throw const FormatException('Missing onboarding preferences');
  }
  if (preferences['enabled'] != true || preferences['exchange'] != true) {
    return null;
  }
  final data = (await dio.get(unifiedCddRoot)).data;
  if (data == null) return <String, dynamic>{};
  if (data is! Map) throw const FormatException('Missing onboarding progress');
  return data.map((key, value) {
    final name = key.toString();
    return MapEntry(
        name.isEmpty ? name : name[0].toLowerCase() + name.substring(1), value);
  });
});

class ExchangeOnboardingPanel extends ConsumerWidget {
  const ExchangeOnboardingPanel({required this.legacy, super.key});
  final Widget legacy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void refresh() {
      ref.invalidate(unifiedExchangeProgressProvider);
      ref.invalidate(exchangeOverviewProvider);
    }

    return ref.watch(unifiedExchangeProgressProvider).when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => Card(
              child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Could not check your Exchange application.'),
              TextButton(onPressed: refresh, child: const Text('Check status')),
            ]),
          )),
          data: (progress) {
            if (progress == null) return legacy;
            final state = progress['boomFi']?.toString();
            final staging = state == 'disabled_in_staging';
            final submitted = progress['submissionRequested'] == true;
            final rejected = state == 'rejected';
            return Card(
                child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exchange',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(staging
                        ? 'Exchange is unavailable in staging.'
                        : rejected
                            ? 'Your Exchange application needs attention. Contact support.'
                            : submitted
                                ? 'Your Exchange application is in progress. You do not need to activate it again.'
                                : 'Complete your selected-services application to set up Exchange using your existing verification.'),
                    if (!staging && !submitted && !rejected) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () => context.push('/kyc'),
                          child: const Text('Continue onboarding')),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: refresh, child: const Text('Check status')),
                  ]),
            ));
          },
        );
  }
}

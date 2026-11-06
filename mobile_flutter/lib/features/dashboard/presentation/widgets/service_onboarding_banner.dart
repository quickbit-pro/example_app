import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../platform/application/platform_providers.dart';
import '../../data/service_onboarding_provider.dart';

/// A shared, theme-aware Home reminder for services selected at registration.
class ServiceOnboardingBanner extends ConsumerWidget {
  const ServiceOnboardingBanner({required this.isBusinessAccount, super.key});

  final bool isBusinessAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isBusinessAccount) return const SizedBox.shrink();
    final items = ref.watch(homeServiceOnboardingProvider).asData?.value;
    // An unanswered or failed read must not claim a service is incomplete.
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('Your service setup'),
                  style: Theme.of(context).textTheme.titleMedium),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          item.name == 'Equals Money banking'
                              ? Icons.account_balance_outlined
                              : Icons.currency_exchange,
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.tr(item.name),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text(context.tr(item.status),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () async {
                  await context.push(AppRoutes.kyc);
                  if (context.mounted) {
                    ref.invalidate(kycDetailedStatusProvider);
                    ref.invalidate(exchangeVerificationProvider);
                    ref.invalidate(homeServiceOnboardingProvider);
                  }
                },
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(context.tr(items.any((item) => item.needsAction)
                    ? 'Continue setup'
                    : 'Check status')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

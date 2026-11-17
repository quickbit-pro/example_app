import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';

import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../auth/application/auth_providers.dart';
import '../../banking/application/banking_providers.dart';
import '../../business/presentation/business_gate.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/platform_widgets.dart';
import '../../platform/presentation/tier_details_sheet.dart';
import '../../platform/presentation/tiers_screen.dart';

class RequiredTierScreen extends ConsumerWidget {
  const RequiredTierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentTierProvider);
    final profile = current.asData != null && current.asData?.value == null
        ? ref.watch(bankingProfileProvider).valueOrNull
        : null;
    if (profile?.isBusinessAccount == true) {
      return const BusinessGate(
        tierSelectionOnly: true,
        child: _TierSelectionPage(),
      );
    }

    return const _TierSelectionPage();
  }
}

class _TierSelectionPage extends ConsumerWidget {
  const _TierSelectionPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentTierProvider);
    final busy = ref.watch(platformActionControllerProvider).isLoading;

    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.tr('Account setup')),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => ref.read(authControllerProvider.notifier).logout(),
              child: Text(context.tr('Sign out')),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: current.when(
                skipLoadingOnRefresh: false,
                loading: () =>
                    LoadingState(label: context.tr('Checking your tier')),
                error: (error, _) => ErrorState(
                  error: error,
                  title: context.tr('Could not check your tier'),
                  onRetry: () => ref.invalidate(currentTierProvider),
                ),
                data: (tier) => tier == null
                    ? _TierChoices(busy: busy)
                    : LoadingState(label: context.tr('Checking your tier')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TierChoices extends ConsumerWidget {
  const _TierChoices({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(bankingProfileProvider);
    final tiers = ref.watch(tiersProvider);

    return profile.when(
      loading: () => LoadingState(label: context.tr('Loading tiers')),
      error: (error, _) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(bankingProfileProvider),
      ),
      data: (profile) => tiers.when(
        loading: () => LoadingState(label: context.tr('Loading tiers')),
        error: (error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(tiersProvider),
        ),
        data: (items) {
          final plans = items.where((tier) => tierIdOf(tier) != null).toList();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                context.tr('Choose your tier'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(context.tr('Choose a tier to continue.')),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              if (plans.isEmpty)
                Text(context.tr(
                  'No tiers are available right now. Contact support for help.',
                )),
              for (final tier in plans)
                Card(
                  child: ListTile(
                    title: Text(tierTitleOf(tier)),
                    subtitle: Text(tierDetailsOf(tier).take(2).join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy
                        ? null
                        : () => showTierDetailsSheet(
                              context,
                              tier: tier,
                              onChoose: () => _chooseTier(
                                ref,
                                tier,
                                isBusiness: profile.isBusinessAccount,
                              ),
                            ),
                  ),
                ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        ref.invalidate(tiersProvider);
                        ref.invalidate(currentTierProvider);
                      },
                child: Text(context.tr('Check status')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _chooseTier(
    WidgetRef ref,
    PlatformResource tier, {
    required bool isBusiness,
  }) {
    final id = tierIdOf(tier);
    if (id == null || ref.read(platformActionControllerProvider).isLoading) {
      return;
    }

    final controller = ref.read(platformActionControllerProvider.notifier);
    controller.selectTier(
      tierId: id,
      tierCycle: tierCycleOf(tier),
      onboarding: !isBusiness,
    );
  }
}

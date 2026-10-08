import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../platform/application/platform_providers.dart';
import '../application/referral_pager.dart';
import '../domain/referral_copy.dart';
import '../domain/rewards_models.dart';
import 'referral_phone_summary.dart';
import 'referral_widgets.dart';

/// `/rewards/earnings`: the whole reward ledger, server-paged, under the
/// totals strip, with a delivery-state filter. `?status=awaiting|paid|failed`
/// preselects the filter, which is how the summary tiles open it.
///
/// Every row states where it stands in the copy contract's words; a pending
/// reward never reads as paid. On the desktop shell the ledger is the
/// workspace's Earnings tab, so this route forwards there.
class ReferralEarningsScreen extends ConsumerStatefulWidget {
  const ReferralEarningsScreen({
    this.initialFilter = ReferralEarningsFilter.all,
    super.key,
  });

  final ReferralEarningsFilter initialFilter;

  @override
  ConsumerState<ReferralEarningsScreen> createState() =>
      _ReferralEarningsScreenState();
}

class _ReferralEarningsScreenState
    extends ConsumerState<ReferralEarningsScreen> {
  ReferralPager<ReferralReward>? _pager;
  late ReferralEarningsFilter _filter = widget.initialFilter;
  bool _forwarded = false;

  @override
  void didUpdateWidget(covariant ReferralEarningsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  ReferralPager<ReferralReward> _pagerFor(RewardsSnapshot data) {
    final programId = data.summary?.programId;
    return _pager ??= ReferralPager<ReferralReward>(
      fetch: (page, pageSize) =>
          ref.read(mobilePlatformApiProvider).getReferralRewards(
                programId: programId,
                page: page,
                pageSize: pageSize,
              ),
      initial: data.referralRewards,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    if (desktop) {
      if (!_forwarded) {
        _forwarded = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            GoRouter.maybeOf(context)?.go(AppRoutes.rewardsTab('earnings'));
          }
        });
      }
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ReferralListSkeleton(),
        ),
      );
    }
    final snapshot = ref.watch(rewardsSnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: isExample,
        leading: referralBackButton(context),
        title: Text(context.tr('Earnings')),
      ),
      body: ExampleAliveLayer(
        enabled: isExample,
        child: snapshot.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 110),
            children: const [ReferralListSkeleton()],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ExampleErrorState(
                error: error,
                onRetry: () => ref.invalidate(rewardsSnapshotProvider),
              ),
            ],
          ),
          data: (data) {
            final summary = data.summary;
            final programmeOn =
                data.referralsEnabled && (summary?.enabled ?? false);
            if (!programmeOn || summary == null) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  ExampleEmptyState(
                    icon: Icons.savings_outlined,
                    title: context.tr('Referrals are not enabled'),
                    body: context.tr(
                        'This section appears automatically when your company enables its referral programme.'),
                  ),
                ],
              );
            }
            final pager = _pagerFor(data);
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(rewardsSnapshotProvider);
                await pager.refresh();
              },
              child: ListenableBuilder(
                listenable: pager,
                builder: (context, _) => _EarningsList(
                  pager: pager,
                  summary: summary,
                  filter: _filter,
                  onFilter: (value) => setState(() => _filter = value),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EarningsList extends StatelessWidget {
  const _EarningsList({
    required this.pager,
    required this.summary,
    required this.filter,
    required this.onFilter,
  });

  final ReferralPager<ReferralReward> pager;
  final ReferralSummary summary;
  final ReferralEarningsFilter filter;
  final ValueChanged<ReferralEarningsFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final vouchers = summary.usesVouchers;
    final rows = sortReferralRewardsNewestFirst(
      pager.items.where(filter.matches),
    );
    final anyFailed =
        pager.items.any((reward) => reward.stage == ReferralRewardStage.failed);
    final List<Widget> body;
    if (pager.loading && !pager.loaded) {
      body = const [ReferralListSkeleton()];
    } else if (pager.error != null && !pager.loaded) {
      body = [
        ExampleErrorState(
          compact: true,
          error: pager.error,
          onRetry: pager.refresh,
        ),
      ];
    } else if (pager.items.isEmpty) {
      body = [
        ExampleEmptyState(
          key: const Key('referral_rewards_empty'),
          compact: true,
          icon: Icons.savings_outlined,
          title: context.tr('No rewards yet'),
          body: context
              .tr('Rewards appear here as your friends qualify and top up.'),
        ),
      ];
    } else if (rows.isEmpty) {
      body = [
        ExampleEmptyState(
          compact: true,
          icon: Icons.filter_list_rounded,
          title: context.tr('No rewards match this filter'),
          body: context.tr('Try another status.'),
        ),
      ];
    } else {
      // Rows straight into the list with dividers on, so a long ledger
      // builds as it scrolls rather than all at once inside one group.
      body = [
        for (var i = 0; i < rows.length; i++)
          ReferralRewardRow(
            key: ValueKey('referral_reward_${rows[i].id ?? i}_$i'),
            reward: rows[i],
            usesVouchers: vouchers,
            divider: i < rows.length - 1,
          ),
      ];
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 110),
      children: [
        ReferralTotalsStrip(summary: summary),
        const SizedBox(height: AppSpacing.md),
        ReferralFilterChips<ReferralEarningsFilter>(
          options: [
            (value: ReferralEarningsFilter.all, label: context.tr('All')),
            (
              value: ReferralEarningsFilter.awaiting,
              label: vouchers
                  ? context.tr('Ready to claim')
                  : context.tr('Awaiting credit'),
            ),
            (
              value: ReferralEarningsFilter.paid,
              label: vouchers
                  ? context.tr('Claimed')
                  : context.tr('Paid reward ledger'),
            ),
            if (anyFailed || filter == ReferralEarningsFilter.failed)
              (
                value: ReferralEarningsFilter.failed,
                label: context.tr('Failed')
              ),
          ],
          selected: filter,
          onChanged: onFilter,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (pager.error != null && pager.loaded) ...[
          ExampleErrorState(
            compact: true,
            error: pager.error,
            onRetry: pager.refresh,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ...body,
        const SizedBox(height: AppSpacing.md),
        ReferralLoadMore(pager: pager),
      ],
    );
  }
}

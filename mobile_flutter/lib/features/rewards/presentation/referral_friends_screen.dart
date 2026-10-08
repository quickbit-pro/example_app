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

/// `/rewards/friends`: every friend the member invited, server-paged, with
/// a stage filter and pull-to-refresh. The first page is the one the rewards
/// snapshot already holds, so the screen opens with content; "Load more"
/// fetches the next.
///
/// On the desktop shell the friends live on the workspace's Friends tab, so
/// this route forwards there and keeps one place for the list.
class ReferralFriendsScreen extends ConsumerStatefulWidget {
  const ReferralFriendsScreen({super.key});

  @override
  ConsumerState<ReferralFriendsScreen> createState() =>
      _ReferralFriendsScreenState();
}

class _ReferralFriendsScreenState extends ConsumerState<ReferralFriendsScreen> {
  ReferralPager<ReferralFriend>? _pager;
  ReferralFriendsFilter _filter = ReferralFriendsFilter.all;
  bool _forwarded = false;

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  ReferralPager<ReferralFriend> _pagerFor(RewardsSnapshot data) {
    final programId = data.summary?.programId;
    return _pager ??= ReferralPager<ReferralFriend>(
      fetch: (page, pageSize) =>
          ref.read(mobilePlatformApiProvider).getReferralFriends(
                programId: programId,
                page: page,
                pageSize: pageSize,
              ),
      initial: data.referralFriends,
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
          if (mounted) GoRouter.maybeOf(context)?.go(AppRoutes.rewardsTab('friends'));
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
        title: Text(context.tr('Friends')),
      ),
      body: ExampleAliveLayer(
        enabled: isExample,
        child: snapshot.when(
          loading: () => const _ListLoading(),
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
                    icon: Icons.people_outline,
                    title: context.tr('Referrals are not enabled'),
                    body: context.tr(
                        'This section appears automatically when your company enables its referral programme.'),
                  ),
                ],
              );
            }
            final pager = _pagerFor(data);
            final offer = effectiveReferralOffer(summary);
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(rewardsSnapshotProvider);
                await pager.refresh();
              },
              child: ListenableBuilder(
                listenable: pager,
                builder: (context, _) => _FriendsList(
                  pager: pager,
                  offer: offer,
                  filter: _filter,
                  onFilter: (value) => setState(() => _filter = value),
                  onInvite: () =>
                      GoRouter.maybeOf(context)?.go(AppRoutes.rewards),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ListLoading extends StatelessWidget {
  const _ListLoading();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 110),
        children: const [ReferralListSkeleton()],
      );
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({
    required this.pager,
    required this.offer,
    required this.filter,
    required this.onFilter,
    required this.onInvite,
  });

  final ReferralPager<ReferralFriend> pager;
  final ReferralOffer offer;
  final ReferralFriendsFilter filter;
  final ValueChanged<ReferralFriendsFilter> onFilter;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final rows = sortReferralFriendsNewestFirst(
      pager.items.where((friend) => filter.matches(friend, offer)),
    );
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
          key: const Key('referral_friends_empty'),
          compact: true,
          icon: Icons.people_outline_rounded,
          title: context.tr('No friends yet'),
          body: context.tr('Share your link to invite your first friend.'),
          actionLabel: context.tr('Share your link'),
          onAction: onInvite,
        ),
      ];
    } else if (rows.isEmpty) {
      body = [
        ExampleEmptyState(
          compact: true,
          icon: Icons.filter_list_rounded,
          title: context.tr('No friends match this filter'),
          body: context.tr('Try another stage.'),
        ),
      ];
    } else {
      // Rows straight into the list with dividers on, so a long list builds
      // as it scrolls rather than all at once inside one group.
      body = [
        for (var i = 0; i < rows.length; i++)
          ReferralFriendRow(
            key: ValueKey('referral_friend_${rows[i].id ?? rows[i].alias}_$i'),
            friend: rows[i],
            offer: offer,
            divider: i < rows.length - 1,
          ),
      ];
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 110),
      children: [
        ReferralFilterChips<ReferralFriendsFilter>(
          options: [
            (value: ReferralFriendsFilter.all, label: context.tr('All')),
            (
              value: ReferralFriendsFilter.inProgress,
              label: context.tr('In progress'),
            ),
            (value: ReferralFriendsFilter.earning, label: context.tr('Earning')),
            (
              value: ReferralFriendsFilter.ended,
              label: context.tr('Window ended'),
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

import 'dart:ui' show SemanticsRole;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart' show friendlyErrorMessage;
import '../../platform/application/platform_providers.dart';
import '../application/referral_pager.dart';
import '../domain/referral_copy.dart';
import '../domain/referral_share.dart';
import '../domain/rewards_models.dart';
import 'referral_actions.dart';
import 'referral_analytics.dart';
import 'referral_calculator.dart';
import 'referral_campaign_links.dart';
import 'referral_explanation.dart';
import 'referral_offer_card.dart';
import 'referral_phone_summary.dart';
import 'referral_level_lifecycle.dart';
import 'referral_member_status.dart';
import 'referral_sections.dart';
import 'referral_widgets.dart';

// ---------------------------------------------------------------------------
// The partner workspace (blueprint p14, p17, p19–20): everything the member
// API exposes, on the desktop shell, behind a small navigation with clear
// roles. Overview, Friends, Earnings, Offer & terms, Share. The tab lives in
// the URL query so a reload lands where the member was.
//
// "Everything" is bounded by the engine: summary, ledger with explanations,
// friends, terms, invitations, and — where the platform serves them —
// campaign links. Statements and exports are not in it and are not faked
// here.
// ---------------------------------------------------------------------------

/// One of the workspace's sections; [wire] is the `?tab=` value.
enum ReferralWorkspaceTab {
  overview('overview'),
  friends('friends'),
  earnings('earnings'),
  offer('offer'),
  share('share'),
  links('links');

  const ReferralWorkspaceTab(this.wire);

  final String wire;

  static ReferralWorkspaceTab fromWire(String? value) {
    for (final tab in values) {
      if (tab.wire == value?.trim().toLowerCase()) return tab;
    }
    return ReferralWorkspaceTab.overview;
  }
}

/// Sidebar width on a wide desktop (blueprint p34).
const double referralWorkspaceNavWidth = 224;

/// Content column ceiling (blueprint p34).
const double referralWorkspaceContentMaxWidth = 1280;

/// Below this content width a table becomes summary rows (blueprint p34).
const double _tableMinWidth = 860;

class ReferralWorkspace extends ConsumerStatefulWidget {
  const ReferralWorkspace({
    required this.snapshot,
    required this.summary,
    required this.tab,
    required this.onTabChanged,
    required this.hero,
    required this.funnel,
    required this.acceptingTerms,
    required this.onAcceptTerms,
    this.vouchers,
    super.key,
  });

  final RewardsSnapshot snapshot;
  final ReferralSummary summary;
  final ReferralWorkspaceTab tab;
  final ValueChanged<ReferralWorkspaceTab> onTabChanged;

  /// The screen's hero, mounted at the top of Overview.
  final Widget hero;

  /// The screen's funnel, mounted on Overview under the level progress.
  final Widget funnel;

  /// The voucher sections, when the programme delivers vouchers; mounted at
  /// the foot of Overview.
  final Widget? vouchers;

  final bool acceptingTerms;
  final ValueChanged<int> onAcceptTerms;

  @override
  ConsumerState<ReferralWorkspace> createState() => _ReferralWorkspaceState();
}

class _ReferralWorkspaceState extends ConsumerState<ReferralWorkspace> {
  ReferralPager<ReferralFriend>? _friendsPager;
  ReferralPager<ReferralReward>? _rewardsPager;
  ReferralFriendsFilter _friendsFilter = ReferralFriendsFilter.all;
  ReferralEarningsFilter _earningsFilter = ReferralEarningsFilter.all;
  ReferralAnalyticsRange _range = ReferralAnalyticsRange.thirtyDays;
  final _search = TextEditingController();
  bool _sendingInvitation = false;

  @override
  void didUpdateWidget(covariant ReferralWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh snapshot (pull to refresh, terms accepted) carries a fresh
    // first page; the pagers seeded from the old one are dropped.
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _friendsPager?.dispose();
      _rewardsPager?.dispose();
      _friendsPager = null;
      _rewardsPager = null;
    }
  }

  @override
  void dispose() {
    _friendsPager?.dispose();
    _rewardsPager?.dispose();
    _search.dispose();
    super.dispose();
  }

  ReferralPager<ReferralFriend> get _friends =>
      _friendsPager ??= ReferralPager<ReferralFriend>(
        fetch: (page, pageSize) =>
            ref.read(mobilePlatformApiProvider).getReferralFriends(
                  programId: widget.summary.programId,
                  page: page,
                  pageSize: pageSize,
                ),
        initial: widget.snapshot.referralFriends,
      );

  ReferralPager<ReferralReward> get _rewards =>
      _rewardsPager ??= ReferralPager<ReferralReward>(
        fetch: (page, pageSize) =>
            ref.read(mobilePlatformApiProvider).getReferralRewards(
                  programId: widget.summary.programId,
                  page: page,
                  pageSize: pageSize,
                ),
        initial: widget.snapshot.referralRewards,
      );

  ReferralSummary get _summary => widget.summary;

  String? get _code => _summary.referralCode;

  String? get _link {
    final code = _code;
    if (code == null) return null;
    return resolveReferralShareLink(
      referralCode: code,
      referralPath: _summary.referralPath,
      currentWebUri: kIsWeb ? Uri.base : null,
      webAppUrl: ref.watch(appConfigProvider).branding.webAppUrl,
    );
  }

  bool get _gated => _summary.mustAcceptTerms;

  Future<void> _share(BuildContext context) {
    final code = _code;
    if (code == null) return Future.value();
    return shareReferralInvite(
      context,
      appName: ref.read(appConfigProvider).branding.appName,
      summary: _summary,
      code: code,
      link: _link,
      origin: shareOriginOf(context),
    );
  }

  Future<void> _copyLink(BuildContext context) {
    final code = _code;
    if (code == null) return Future.value();
    return copyReferralInvite(context, code: code, link: _link);
  }

  Future<void> _sendInvitation(ReferralInvitationRequest request) async {
    setState(() => _sendingInvitation = true);
    try {
      await ref.read(mobilePlatformApiProvider).sendReferralInvitation(
            email: request.email,
            name: request.name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Invitation sent to {p0}', {'p0': request.email}),
          ),
        ),
      );
      ref.invalidate(rewardsSnapshotProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _sendingInvitation = false);
    }
  }

  Future<void> _inviteByEmail(BuildContext context) async {
    final submission = await showReferralInvitationDialog(context);
    if (submission == null || !mounted) return;
    await _sendInvitation(submission);
  }

  void _openDrawer(BuildContext context, ReferralReward reward) {
    showReferralRewardDrawer(
      context,
      reward,
      usesVouchers: _summary.usesVouchers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final sidebar = width >= ExampleBreakpoints.compactRail;
    final tabs = [
      (
        value: ReferralWorkspaceTab.overview,
        label: context.tr('Overview'),
        icon: Icons.dashboard_outlined,
      ),
      (
        value: ReferralWorkspaceTab.friends,
        label: context.tr('Friends'),
        icon: Icons.people_outline_rounded,
      ),
      (
        value: ReferralWorkspaceTab.earnings,
        label: context.tr('Earnings'),
        icon: Icons.savings_outlined,
      ),
      (
        value: ReferralWorkspaceTab.offer,
        label: context.tr('Offer & terms'),
        icon: Icons.description_outlined,
      ),
      (
        value: ReferralWorkspaceTab.share,
        label: context.tr('Share'),
        icon: Icons.ios_share_rounded,
      ),
      // Links exist once the platform serves campaign links; a 404 (null)
      // keeps the tab out, and a link to ?tab=links then lands on Overview.
      if (ref.watch(referralCampaignLinksProvider).asData?.value != null)
        (
          value: ReferralWorkspaceTab.links,
          label: context.tr('Links'),
          icon: Icons.link_rounded,
        ),
    ];
    final content = KeyedSubtree(
      key: Key('referral_workspace_${widget.tab.wire}'),
      child: switch (widget.tab) {
        ReferralWorkspaceTab.overview => _overview(context),
        ReferralWorkspaceTab.friends => _friendsTab(context),
        ReferralWorkspaceTab.earnings => _earningsTab(context),
        ReferralWorkspaceTab.offer => _offerTab(context),
        ReferralWorkspaceTab.share => _shareTab(context),
        ReferralWorkspaceTab.links => _linksTab(context),
      },
    );
    if (sidebar) {
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: referralWorkspaceContentMaxWidth +
                referralWorkspaceNavWidth +
                AppSpacing.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: referralWorkspaceNavWidth,
                child: _WorkspaceNav(
                  key: const Key('referral_workspace_nav'),
                  tabs: tabs,
                  selected: widget.tab,
                  onChanged: widget.onTabChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: referralWorkspaceContentMaxWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReferralFilterChips<ReferralWorkspaceTab>(
              key: const Key('referral_workspace_tabs'),
              options: [
                for (final tab in tabs) (value: tab.value, label: tab.label),
              ],
              selected: widget.tab,
              onChanged: widget.onTabChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            content,
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- overview

  Widget _overview(BuildContext context) {
    final summary = _summary;
    final rewards = sortReferralRewardsNewestFirst(
      widget.snapshot.referralRewards,
    ).take(5).toList();
    final earning = widget.snapshot.referralFriends
        .where((friend) => friend.isEarning)
        .toList();
    final activity = rewards.isEmpty
        ? ExampleEmptyState(
            key: const Key('referral_recent_activity_empty'),
            compact: true,
            icon: Icons.savings_outlined,
            title: context.tr('No rewards yet'),
            body: context
                .tr('Rewards appear here as your friends qualify and top up.'),
          )
        : ExampleListGroup(
            key: const Key('referral_recent_activity'),
            title: context.tr('Recent activity'),
            action: context.tr('See all'),
            onAction: () => widget.onTabChanged(ReferralWorkspaceTab.earnings),
            children: [
              for (final reward in rewards)
                ReferralRewardRow(
                  reward: reward,
                  usesVouchers: summary.usesVouchers,
                  onTap: () => _openDrawer(context, reward),
                ),
            ],
          );
    final earningNow = earning.isEmpty
        ? ExampleEmptyState(
            key: const Key('referral_friends_earning_empty'),
            compact: true,
            icon: Icons.people_outline_rounded,
            title: context.tr('No friends are earning yet'),
            body: context.tr('Share your link to invite your first friend.'),
            actionLabel: context.tr('Share your link'),
            onAction: () => widget.onTabChanged(ReferralWorkspaceTab.share),
          )
        : ExampleListGroup(
            key: const Key('referral_friends_earning'),
            title: context.tr('Friends earning now'),
            action: context.tr('See all'),
            onAction: () => widget.onTabChanged(ReferralWorkspaceTab.friends),
            children: [
              for (final friend in earning) _EarningFriendRow(friend: friend),
            ],
          );
    // The period's analytics. Null once the backend has said it does not
    // serve them (404): the selector and the blocks stay out and the tiles
    // keep their all-time figures. A failure shows a retry in the blocks'
    // place; a refresh keeps the previous period on screen.
    final analyticsValue = ref.watch(referralAnalyticsProvider(_range));
    final analytics = analyticsValue.when(
      data: (data) => data,
      error: (_, __) => null,
      loading: () => null,
    );
    final analyticsServed = analyticsValue.when(
      data: (data) => data != null,
      error: (_, __) => true,
      loading: () => true,
    );
    final Widget? analyticsBlocks = analyticsValue.when(
      data: (data) => data == null
          ? null
          : data.isEmpty
              ? ReferralAnalyticsEmpty(
                  onShare: () =>
                      widget.onTabChanged(ReferralWorkspaceTab.share),
                )
              : _analyticsBlocks(context, data),
      error: (error, _) => ExampleErrorState(
        key: const Key('referral_analytics_error'),
        compact: true,
        error: error,
        onRetry: () => ref.invalidate(referralAnalyticsProvider(_range)),
      ),
      loading: () => const ReferralAnalyticsSkeleton(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.hero,
        const SizedBox(height: AppSpacing.lg),
        if (analyticsServed) ...[
          ReferralPeriodSelector(
            selected: _range,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _KpiRow(summary: summary, analytics: analytics, range: _range),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.tr('Figures update after provider confirmation · {p0}',
              {'p0': summary.rewards.currency}),
          key: const Key('referral_reporting_note'),
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: ExampleInk.secondary(context),
          ),
        ),
        if (analyticsBlocks != null) ...[
          const SizedBox(height: AppSpacing.lg),
          analyticsBlocks,
        ],
        const SizedBox(height: AppSpacing.lg),
        ..._shareSection(context, compact: true),
        const SizedBox(height: AppSpacing.lg),
        const ReferralMemberStatusCard(),
        const SizedBox(height: 12),
        ReferralLevelLifecycleCard(currency: summary.rewards.currency),
        if (summary.showsLevels) ...[
          const SizedBox(height: AppSpacing.lg),
          ReferralLevelsCard(summary: summary),
        ],
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _tableMinWidth;
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                activity,
                const SizedBox(height: AppSpacing.lg),
                earningNow,
              ],
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  widget.funnel,
                  const SizedBox(height: AppSpacing.lg),
                  right,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: widget.funnel),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 3, child: right),
              ],
            );
          },
        ),
        if (widget.vouchers != null) ...[
          const SizedBox(height: AppSpacing.lg),
          widget.vouchers!,
        ],
      ],
    );
  }

  /// The journey strip over the trend panel and the top friends; the two
  /// side by side on a wide column, the friends left out when nobody
  /// earned anything in the period. The campaign performance table
  /// (blueprint p17) follows when any link had traffic in the period.
  Widget _analyticsBlocks(BuildContext context, ReferralMemberAnalytics data) {
    final trend = ReferralTrendPanel(analytics: data);
    final friends =
        data.topFriends.isEmpty ? null : ReferralTopFriends(analytics: data);
    return Column(
      key: const Key('referral_analytics'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReferralJourneyStrip(analytics: data),
        if (data.campaigns.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _campaignPerformance(context, data),
        ],
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            if (friends == null || constraints.maxWidth < _tableMinWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  trend,
                  if (friends != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    friends,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: trend),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 2, child: friends),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The share action, or what stands in for it: the terms gate until the
  /// current version is accepted, the email fallback when the summary
  /// carries no code, nothing when the member cannot invite.
  List<Widget> _shareSection(BuildContext context, {required bool compact}) {
    final summary = _summary;
    if (summary.residenceRestricted) {
      return [
        ExampleEmptyState(
          compact: true,
          icon: Icons.public_off_rounded,
          title: context.tr('Referral participation unavailable'),
          body: context.tr(summary.residenceRestrictionMessage),
        ),
      ];
    }
    if (_gated) {
      return [
        ReferralTermsGate(
          terms: summary.terms!,
          busy: widget.acceptingTerms,
          onAccept: widget.onAcceptTerms,
        ),
      ];
    }
    if (!summary.canInvite) return const [];
    final code = _code;
    if (code == null) {
      return [
        ExampleGlassPanel(
          radius: AppRadii.lg,
          borderAlpha: .30,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(
                    'Your invitation link is issued when you email an invitation.'),
                style: referralBodyStyle(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              ExampleGlassButton(
                label: context.tr('Invite friends'),
                icon: Icons.mail_outline_rounded,
                sheen: false,
                loading: _sendingInvitation,
                onPressed:
                    _sendingInvitation ? null : () => _inviteByEmail(context),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      _LinkRow(
        code: code,
        link: _link,
        onCopy: () => _copyLink(context),
        onShare: () => _share(context),
        onQr:
            _link == null ? null : () => showReferralQrDialog(context, _link!),
      ),
    ];
  }

  /// "Campaign performance" (blueprint p17): one row per link with traffic in
  /// the period — clicks, sign-ups, qualified and the rewards accrued
  /// through it.
  /// Selecting a row opens the link's own performance panel.
  Widget _campaignPerformance(
      BuildContext context, ReferralMemberAnalytics data) {
    final rows = [...data.campaigns]
      ..sort((a, b) => b.rewardsAccrued.compareTo(a.rewardsAccrued));
    final links = ref.watch(referralCampaignLinksProvider).asData?.value ??
        const <ReferralCampaignLink>[];
    ReferralCampaignLink? linkFor(ReferralCampaignRow row) {
      for (final link in links) {
        if (link.id == row.linkId) return link;
      }
      return null;
    }

    Widget cellFor(String text, {bool primary = false, bool end = false}) =>
        _cell(context, text, primary: primary, end: end);
    return ExampleGlassPanel(
      key: const Key('referral_campaign_performance'),
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.tr('CAMPAIGN PERFORMANCE'),
                    style: ExampleTextStyles.label(context)),
              ),
              ExamplePressable(
                onTap: () => widget.onTabChanged(ReferralWorkspaceTab.links),
                borderRadius:
                    const BorderRadius.all(Radius.circular(AppRadii.sm)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    context.tr('Manage links'),
                    key: const Key('referral_campaign_performance_manage'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ExampleInk.accent(context, ExampleColors.iris),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('What each of your links brought in {p0}.',
                {'p0': referralRangeCaption(context, _range)}),
            style: referralBodyStyle(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 640) {
                return _CompactRows(
                  children: [
                    for (final row in rows)
                      ExampleRow(
                        key: ValueKey('referral_campaign_row_${row.linkId}'),
                        title: row.name.isEmpty ? row.code : row.name,
                        subtitle: context.tr(
                            '{p0} clicks · {p1} sign-ups · {p2} qualified', {
                          'p0': row.clicks,
                          'p1': row.signups,
                          'p2': row.qualified,
                        }),
                        trailing: Text(
                          Money.formatAmount(data.currency, row.rewardsAccrued),
                          style: referralFigureStyle(context),
                        ),
                        onTap: linkFor(row) == null
                            ? null
                            : () => showReferralCampaignLinkPerformance(
                                context, linkFor(row)!),
                      ),
                  ],
                );
              }
              return ReferralTable(
                key: const Key('referral_campaign_performance_table'),
                columns: [
                  ReferralTableColumn(context.tr('Campaign'), flex: 3),
                  ReferralTableColumn(context.tr('Code'), flex: 2),
                  ReferralTableColumn(context.tr('Clicks'), flex: 1, end: true),
                  ReferralTableColumn(context.tr('Sign-ups'),
                      flex: 1, end: true),
                  ReferralTableColumn(context.tr('Qualified'),
                      flex: 1, end: true),
                  ReferralTableColumn(context.tr('Rewards accrued'),
                      flex: 2, end: true),
                ],
                rows: [
                  for (final row in rows)
                    ReferralTableRow(
                      key: ValueKey('referral_campaign_row_${row.linkId}'),
                      semanticsLabel:
                          '${row.name}, ${row.code}, ${row.clicks}, ${row.signups}, ${row.qualified}, ${Money.formatAmount(data.currency, row.rewardsAccrued)}',
                      onTap: linkFor(row) == null
                          ? null
                          : () => showReferralCampaignLinkPerformance(
                              context, linkFor(row)!),
                      cells: [
                        cellFor(row.name.isEmpty ? row.code : row.name,
                            primary: true),
                        cellFor(row.code),
                        cellFor('${row.clicks}', end: true),
                        cellFor('${row.signups}', end: true),
                        cellFor('${row.qualified}', end: true),
                        cellFor(
                          Money.formatAmount(data.currency, row.rewardsAccrued),
                          primary: true,
                          end: true,
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- links

  Widget _linksTab(BuildContext context) =>
      ReferralCampaignLinksTab(summary: _summary);

  // ----------------------------------------------------------------- friends

  Widget _friendsTab(BuildContext context) {
    final pager = _friends;
    final offer = effectiveReferralOffer(_summary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: context.tr('Friends'),
          subtitle: context.tr(
              'Friends are shown by pseudonym unless you named them in an email invitation. Their balances and card details are never visible.'),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ReferralFilterChips<ReferralFriendsFilter>(
              options: [
                (value: ReferralFriendsFilter.all, label: context.tr('All')),
                (
                  value: ReferralFriendsFilter.inProgress,
                  label: context.tr('In progress'),
                ),
                (
                  value: ReferralFriendsFilter.earning,
                  label: context.tr('Earning'),
                ),
                (
                  value: ReferralFriendsFilter.ended,
                  label: context.tr('Window ended'),
                ),
              ],
              selected: _friendsFilter,
              onChanged: (value) => setState(() => _friendsFilter = value),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('referral_friends_search'),
                controller: _search,
                style: TextStyle(
                  fontSize: 16,
                  color: ExampleInk.primary(context),
                ),
                decoration: InputDecoration(
                  hintText: context.tr('Search friends'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 12,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius:
                        BorderRadius.all(Radius.circular(AppRadii.sm)),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ListenableBuilder(
          listenable: pager,
          builder: (context, _) {
            final query = _search.text.trim().toLowerCase();
            final rows = sortReferralFriendsNewestFirst(
              pager.items.where((friend) {
                if (!_friendsFilter.matches(friend, offer)) return false;
                if (query.isEmpty) return true;
                return friend.displayName.toLowerCase().contains(query) ||
                    friend.alias.toLowerCase().contains(query);
              }),
            );
            final Widget body;
            if (pager.loading && !pager.loaded) {
              body = const ReferralListSkeleton();
            } else if (pager.error != null && !pager.loaded) {
              body = ExampleErrorState(
                compact: true,
                error: pager.error,
                onRetry: pager.refresh,
              );
            } else if (pager.items.isEmpty) {
              body = ExampleEmptyState(
                key: const Key('referral_friends_empty'),
                compact: true,
                icon: Icons.people_outline_rounded,
                title: context.tr('No friends yet'),
                body:
                    context.tr('Share your link to invite your first friend.'),
                actionLabel: context.tr('Share your link'),
                onAction: () => widget.onTabChanged(ReferralWorkspaceTab.share),
              );
            } else if (rows.isEmpty) {
              body = ExampleEmptyState(
                compact: true,
                icon: Icons.filter_list_rounded,
                title: context.tr('No friends match this filter'),
                body: context.tr('Try another stage or search.'),
              );
            } else {
              body = LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= _tableMinWidth
                        ? _friendsTable(context, rows, offer)
                        : _CompactRows(
                            children: [
                              for (var i = 0; i < rows.length; i++)
                                ReferralFriendRow(
                                  friend: rows[i],
                                  offer: offer,
                                  divider: i < rows.length - 1,
                                ),
                            ],
                          ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pager.error != null && pager.loaded) ...[
                  ExampleErrorState(
                    compact: true,
                    error: pager.error,
                    onRetry: pager.refresh,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                body,
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: ReferralLoadMore(pager: pager),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _friendsTable(
    BuildContext context,
    List<ReferralFriend> rows,
    ReferralOffer offer,
  ) {
    final localizations = MaterialLocalizations.of(context);
    return ReferralTable(
      key: const Key('referral_friends_table'),
      columns: [
        ReferralTableColumn(context.tr('Friend'), flex: 3),
        ReferralTableColumn(context.tr('Stage'), flex: 2),
        ReferralTableColumn(context.tr('Joined'), flex: 2),
        ReferralTableColumn(context.tr('Next requirement'), flex: 3),
        ReferralTableColumn(context.tr('Earning until'), flex: 2),
        ReferralTableColumn(context.tr('Earned'), flex: 1, end: true),
      ],
      rows: [
        for (final friend in rows)
          () {
            final stage = context.tr(friend.stage.label);
            final joined = friend.attributedAt == null
                ? '—'
                : localizations.formatShortDate(friend.attributedAt!.toLocal());
            final requirement =
                referralFriendRequirementLabel(context, friend, offer);
            final until = friend.earningUntil == null
                ? '—'
                : localizations.formatShortDate(friend.earningUntil!.toLocal());
            final earned =
                Money.formatAmount(friend.currency, friend.earnedAmount);
            return ReferralTableRow(
              key: ValueKey('referral_friend_${friend.id ?? friend.alias}'),
              semanticsLabel:
                  '${friend.displayName}, $stage, $requirement, $earned',
              cells: [
                _cell(context, friend.displayName, primary: true),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ReferralStageChip(
                    label: stage,
                    tone: referralFriendStageTone(friend.stage),
                  ),
                ),
                _cell(context, joined),
                _cell(context, requirement),
                _cell(context, until),
                _cell(context, earned, primary: true, end: true),
              ],
            );
          }(),
      ],
    );
  }

  // ---------------------------------------------------------------- earnings

  Widget _earningsTab(BuildContext context) {
    final pager = _rewards;
    final summary = _summary;
    final vouchers = summary.usesVouchers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: context.tr('Earnings'),
          subtitle: context.tr(
              'Every reward with where it stands. Select a row to see how it was calculated.'),
        ),
        const SizedBox(height: AppSpacing.md),
        ReferralTotalsStrip(summary: summary),
        const SizedBox(height: AppSpacing.md),
        ListenableBuilder(
          listenable: pager,
          builder: (context, _) {
            final anyFailed = pager.items
                .any((reward) => reward.stage == ReferralRewardStage.failed);
            final rows = sortReferralRewardsNewestFirst(
              pager.items.where(_earningsFilter.matches),
            );
            final Widget body;
            if (pager.loading && !pager.loaded) {
              body = const ReferralListSkeleton();
            } else if (pager.error != null && !pager.loaded) {
              body = ExampleErrorState(
                compact: true,
                error: pager.error,
                onRetry: pager.refresh,
              );
            } else if (pager.items.isEmpty) {
              body = ExampleEmptyState(
                key: const Key('referral_rewards_empty'),
                compact: true,
                icon: Icons.savings_outlined,
                title: context.tr('No rewards yet'),
                body: context.tr(
                    'Rewards appear here as your friends qualify and top up.'),
                actionLabel: context.tr('Share your link'),
                onAction: () => widget.onTabChanged(ReferralWorkspaceTab.share),
              );
            } else if (rows.isEmpty) {
              body = ExampleEmptyState(
                compact: true,
                icon: Icons.filter_list_rounded,
                title: context.tr('No rewards match this filter'),
                body: context.tr('Try another status.'),
              );
            } else {
              body = LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth >= _tableMinWidth
                        ? _earningsTable(context, rows, vouchers)
                        : _CompactRows(
                            children: [
                              for (var i = 0; i < rows.length; i++)
                                ReferralRewardRow(
                                  reward: rows[i],
                                  usesVouchers: vouchers,
                                  divider: i < rows.length - 1,
                                  onTap: () => _openDrawer(context, rows[i]),
                                ),
                            ],
                          ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReferralFilterChips<ReferralEarningsFilter>(
                  options: [
                    (
                      value: ReferralEarningsFilter.all,
                      label: context.tr('All'),
                    ),
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
                    if (anyFailed ||
                        _earningsFilter == ReferralEarningsFilter.failed)
                      (
                        value: ReferralEarningsFilter.failed,
                        label: context.tr('Failed'),
                      ),
                  ],
                  selected: _earningsFilter,
                  onChanged: (value) => setState(() => _earningsFilter = value),
                ),
                const SizedBox(height: AppSpacing.md),
                if (pager.error != null && pager.loaded) ...[
                  ExampleErrorState(
                    compact: true,
                    error: pager.error,
                    onRetry: pager.refresh,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                body,
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: ReferralLoadMore(pager: pager),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _earningsTable(
    BuildContext context,
    List<ReferralReward> rows,
    bool vouchers,
  ) {
    final localizations = MaterialLocalizations.of(context);
    return ReferralTable(
      key: const Key('referral_earnings_table'),
      columns: [
        ReferralTableColumn(context.tr('Date'), flex: 2),
        ReferralTableColumn(context.tr('Event'), flex: 3),
        ReferralTableColumn(context.tr('Friend'), flex: 2),
        ReferralTableColumn(context.tr('Basis · rate'), flex: 3),
        ReferralTableColumn(context.tr('Status'), flex: 2),
        ReferralTableColumn(context.tr('Amount'), flex: 1, end: true),
      ],
      rows: [
        for (final reward in rows)
          () {
            final when = reward.occurredAt ?? reward.createdAt;
            final date = when == null
                ? '—'
                : localizations.formatShortDate(when.toLocal());
            final event = context.tr(reward.eventLabel);
            final explanation = reward.explanation;
            final basis = explanation == null || explanation.basis.isEmpty
                ? '—'
                : explanation.rate == null
                    ? context.tr(explanation.basisLabel)
                    : '${context.tr(explanation.basisLabel)} · '
                        '${formatReferralPercent(explanation.rate!)}';
            final delivery =
                referralRewardEvidenceDelivery(reward, usesVouchers: vouchers);
            final status = referralDeliveryLabel(context, delivery,
                currency: reward.currency);
            final amount = Money.formatAmount(reward.currency, reward.amount);
            return ReferralTableRow(
              key: ValueKey(
                  'referral_reward_${reward.id ?? identityHashCode(reward)}'),
              semanticsLabel: '$event, $status, $amount',
              onTap: () => _openDrawer(context, reward),
              cells: [
                _cell(context, date),
                _cell(context, event, primary: true),
                _cell(context, reward.friendAlias ?? '—'),
                _cell(context, basis),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ReferralStatusPill(delivery: delivery),
                ),
                _cell(context, amount, primary: true, end: true),
              ],
            );
          }(),
      ],
    );
  }

  // ------------------------------------------------------------------- offer

  Widget _offerTab(BuildContext context) {
    final summary = _summary;
    final terms = summary.terms;
    final Widget? termsPanel;
    if (_gated) {
      termsPanel = ReferralTermsGate(
        terms: terms!,
        busy: widget.acceptingTerms,
        onAccept: widget.onAcceptTerms,
      );
    } else if (terms != null && terms.published) {
      termsPanel = ExampleGlassPanel(
        key: const Key('referral_terms_panel'),
        radius: AppRadii.lg,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('REWARD TERMS'),
                style: ExampleTextStyles.label(context)),
            const SizedBox(height: AppSpacing.xs),
            ReferralTermsView(terms: terms),
          ],
        ),
      );
    } else {
      termsPanel = null;
    }
    final calculator = ReferralRewardCalculator(
      offer: effectiveReferralOffer(summary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReferralOfferCard(summary: summary),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary.showsLevels) ...[
                  ReferralLevelsCard(summary: summary),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (termsPanel != null) termsPanel,
              ],
            );
            if (constraints.maxWidth < _tableMinWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  calculator,
                  const SizedBox(height: AppSpacing.lg),
                  left,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 2, child: calculator),
              ],
            );
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- share

  Widget _shareTab(BuildContext context) {
    final summary = _summary;
    final code = _code;
    final link = _link;
    final body = referralBodyStyle(context);
    final howItWorks = ExampleGlassPanel(
      key: const Key('referral_how_sharing_works'),
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('HOW SHARING WORKS'),
              style: ExampleTextStyles.label(context)),
          const SizedBox(height: AppSpacing.xs),
          for (final line in [
            context.tr(
                'One attribution per new person: a friend is linked to the first invitation they use.'),
            context.tr(
                'Your friend accepts the programme terms when they sign up.'),
            context.tr(
                'No automatic messages are sent. You choose what to share and where.'),
          ])
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ExampleInk.accent(context, ExampleColors.iris),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(line, style: body)),
                ],
              ),
            ),
        ],
      ),
    );
    final List<Widget> primary;
    if (summary.residenceRestricted || _gated) {
      primary = _shareSection(context, compact: false);
    } else if (!summary.canInvite) {
      primary = [
        ExampleEmptyState(
          compact: true,
          icon: Icons.ios_share_rounded,
          title: context.tr('Sharing is not available on this account'),
          body: context.tr(
              'This section appears automatically when your company enables its referral programme.'),
        ),
      ];
    } else if (code == null) {
      primary = _shareSection(context, compact: false);
    } else {
      final caption = buildReferralShareText(
        appName: ref.read(appConfigProvider).branding.appName,
        referralCode: code,
        link: link,
        offer: summary.offer,
        translate: AppLocalizations.of(context).translate,
      );
      primary = [
        _LinkRow(
          code: code,
          link: link,
          onCopy: () => _copyLink(context),
          onShare: () => _share(context),
          onQr: link == null ? null : () => showReferralQrDialog(context, link),
          showCode: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        ExampleGlassPanel(
          key: const Key('referral_share_caption'),
          radius: AppRadii.lg,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('SUGGESTED CAPTION'),
                  style: ExampleTextStyles.label(context)),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                caption,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: ExampleInk.primary(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ExampleGlassButton(
                  key: const Key('referral_copy_caption'),
                  label: context.tr('Copy caption'),
                  icon: Icons.copy_rounded,
                  tone: ExampleGlassButtonTone.neutral,
                  sheen: false,
                  expand: false,
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  onPressed: () =>
                      _copyText(context, caption, context.tr('Caption copied')),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    final email = !_gated && summary.canInvite
        ? ExampleGlassPanel(
            key: const Key('referral_email_panel'),
            radius: AppRadii.lg,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('INVITE BY EMAIL'),
                    style: ExampleTextStyles.label(context)),
                const SizedBox(height: AppSpacing.sm),
                ReferralInvitationForm(
                  onSend: _sendInvitation,
                  busy: _sendingInvitation,
                ),
              ],
            ),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: context.tr('Share'),
          subtitle: context.tr(
              'Your link, your code, a caption to go with them, and an email invitation the platform sends for you.'),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...primary,
                const SizedBox(height: AppSpacing.lg),
                howItWorks,
              ],
            );
            if (email == null || constraints.maxWidth < _tableMinWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  if (email != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    email,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 2, child: email),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _copyText(
      BuildContext context, String text, String confirmation) async {
    await copyToClipboard(text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(confirmation)));
  }
}

Widget _cell(
  BuildContext context,
  String text, {
  bool primary = false,
  bool end = false,
}) =>
    Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.35,
        fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
        color:
            primary ? ExampleInk.primary(context) : ExampleInk.secondary(context),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

/// A tab's heading: the section size from the blueprint's type ramp, and a
/// line that says what the section is.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
              color: ExampleInk.primary(context),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(subtitle!, style: referralBodyStyle(context)),
          ],
        ],
      );
}

/// The three figures a partner asks about first (blueprint p17): what has
/// landed, what is waiting, how many friends qualified. With [analytics]
/// the figures are the selected period's and the caption says so; without
/// them (not served, or not here yet) they are the summary's all-time
/// totals under their own notes.
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.summary, this.analytics, this.range});

  final ReferralSummary summary;
  final ReferralMemberAnalytics? analytics;
  final ReferralAnalyticsRange? range;

  @override
  Widget build(BuildContext context) {
    final totals = summary.rewards;
    final period = analytics;
    final currency = period?.currency ?? totals.currency;
    final vouchers = summary.usesVouchers;
    final caption = period == null || range == null
        ? null
        : referralRangeCaption(context, range!);
    final tiles = [
      _KpiTile(
        key: const Key('referral_kpi_paid'),
        label:
            vouchers ? context.tr('Claimed') : context.tr('Paid reward ledger'),
        value: Money.formatAmount(
          currency,
          period == null ? totals.paid : period.totals.rewardsPaid,
        ),
        note: caption ??
            (vouchers
                ? context.tr('Redeemed as vouchers')
                : context.tr('Already in your wallet')),
        emphasis: true,
      ),
      _KpiTile(
        key: const Key('referral_kpi_pending'),
        label: context.tr('Pending'),
        value: Money.formatAmount(
          currency,
          period == null ? totals.awaiting : period.totals.rewardsPending,
        ),
        note: caption ??
            (vouchers
                ? context.tr('Waiting for confirmation or claim')
                : context.tr('Waiting for provider confirmation')),
      ),
      _KpiTile(
        key: const Key('referral_kpi_qualified'),
        label: context.tr('Qualified friends'),
        value:
            '${period == null ? summary.referrals.qualified : period.totals.qualified}',
        note: caption ?? context.tr('Completed the referral requirements'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.note,
    this.emphasis = false,
    super.key,
  });

  final String label;
  final String value;
  final String note;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: emphasis
              ? ExampleInk.tint(context, ExampleColors.violet, alpha: .16)
              : ExampleSurface.of(context, 1),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: emphasis
              ? ExampleBorders.emphasisOf(context)
              : light
                  ? ExampleBorders.subtleLightAll
                  : ExampleBorders.subtleOf(context),
          boxShadow: ExampleShadows.ambientOf(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: ExampleInk.secondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: referralFigureStyle(context, size: 32)),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              note,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: ExampleInk.secondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The default referral link with its actions; the code beside it on the
/// Share tab.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.code,
    required this.link,
    required this.onCopy,
    required this.onShare,
    this.onQr,
    this.showCode = false,
  });

  final String code;
  final String? link;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onQr;
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    final address = link ?? code;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExampleGlassButton(
          key: const Key('referral_workspace_copy_link'),
          label: context.tr('Copy link'),
          icon: Icons.copy_rounded,
          tone: ExampleGlassButtonTone.neutral,
          sheen: false,
          expand: false,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          onPressed: onCopy,
        ),
        const SizedBox(width: AppSpacing.xs),
        ExampleGlassButton(
          key: const Key('referral_workspace_share'),
          label: context.tr('Share'),
          icon: Icons.ios_share_rounded,
          sheen: false,
          expand: false,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          onPressed: onShare,
        ),
        if (onQr != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            key: const Key('referral_workspace_qr'),
            tooltip: context.tr('Show QR code'),
            onPressed: onQr,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            color: ExampleInk.secondary(context),
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
        ],
      ],
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('YOUR DEFAULT REFERRAL LINK'),
          style: ExampleTextStyles.label(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          address,
          key: const Key('referral_workspace_link'),
          maxLines: 2,
          style: ExampleTextStyles.mono(
            context,
            size: 15,
            weight: FontWeight.w500,
          ),
        ),
        if (showCode) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('Code {p0}', {'p0': code}),
            key: const Key('referral_workspace_code'),
            style: ExampleTextStyles.mono(context, size: 12.5)
                .copyWith(color: ExampleInk.secondary(context)),
          ),
        ],
      ],
    );
    return ExampleGlassPanel(
      key: const Key('referral_link_row'),
      radius: AppRadii.lg,
      borderAlpha: .30,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: AppSpacing.sm),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              const SizedBox(width: AppSpacing.md),
              actions,
            ],
          );
        },
      ),
    );
  }
}

/// A friend inside their earning window: alias, earned, window end.
class _EarningFriendRow extends StatelessWidget {
  const _EarningFriendRow({required this.friend});

  final ReferralFriend friend;

  @override
  Widget build(BuildContext context) {
    final until = friend.earningUntil;
    final subtitle = until == null
        ? context.tr('Earning on eligible top-ups')
        : context.tr('Earning until {p0}', {
            'p0': MaterialLocalizations.of(context)
                .formatMediumDate(until.toLocal()),
          });
    final earned = Money.formatAmount(friend.currency, friend.earnedAmount);
    return ExampleRow(
      title: friend.displayName,
      subtitle: subtitle,
      leading: const ExampleIconTile(
        icon: Icons.trending_up_rounded,
        color: ExampleColors.success,
      ),
      trailing: Text(earned, style: referralFigureStyle(context)),
      semanticsLabel: '${friend.displayName}, $subtitle, $earned',
    );
  }
}

/// The left sub-navigation: one item per section, the selected one on the
/// emphasis edge. Items are `ExamplePressable`s, so they take keyboard focus
/// with a visible ring and announce themselves selected.
class _WorkspaceNav extends StatelessWidget {
  const _WorkspaceNav({
    required this.tabs,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<({ReferralWorkspaceTab value, String label, IconData icon})> tabs;
  final ReferralWorkspaceTab selected;
  final ValueChanged<ReferralWorkspaceTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tab in tabs)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: _NavItem(
              label: tab.label,
              icon: tab.icon,
              selected: tab.value == selected,
              onTap: () => onChanged(tab.value),
            ),
          ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    return Semantics(
      role: SemanticsRole.tab,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: ExamplePressable(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.sm)),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? ExampleInk.tint(context, ExampleColors.violet, alpha: .16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: selected
                ? ExampleBorders.emphasisOf(context)
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? accent : ExampleInk.secondary(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? ExampleInk.primary(context)
                        : ExampleInk.secondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows on a surface, for a table that has collapsed to summary rows.
class _CompactRows extends StatelessWidget {
  const _CompactRows({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ExampleListGroup(
        dividers: false,
        children: children,
      );
}

/// A column of a [ReferralTable].
class ReferralTableColumn {
  const ReferralTableColumn(this.label, {this.flex = 2, this.end = false});

  final String label;
  final int flex;

  /// Right-aligned, for amounts.
  final bool end;
}

/// A row of a [ReferralTable]; [cells] pair with the table's columns.
class ReferralTableRow {
  const ReferralTableRow({
    required this.cells,
    this.onTap,
    this.semanticsLabel,
    this.key,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final Key? key;
}

/// A plain data table on a level-1 surface: a header row, hairlines, and
/// rows that are buttons when they open something. Tabular figures and
/// 52 pt rows; it never scrolls sideways — the workspace collapses it to
/// summary rows before it would have to.
class ReferralTable extends StatelessWidget {
  const ReferralTable({
    required this.columns,
    required this.rows,
    super.key,
  });

  final List<ReferralTableColumn> columns;
  final List<ReferralTableRow> rows;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    final hairline = ExampleBorders.hairlineSideOf(context).color;
    Widget line() => SizedBox(height: 1, child: ColoredBox(color: hairline));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: light
            ? ExampleBorders.subtleLightAll
            : ExampleBorders.subtleOf(context),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: columns[i].flex,
                        child: Text(
                          columns[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign:
                              columns[i].end ? TextAlign.end : TextAlign.start,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            line(),
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) line(),
              _TableRow(row: rows[r], columns: columns),
            ],
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.row, required this.columns});

  final ReferralTableRow row;
  final List<ReferralTableColumn> columns;

  @override
  Widget build(BuildContext context) {
    final cells = Container(
      key: row.key,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: columns[i].flex,
              child: Align(
                alignment: columns[i].end
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: i < row.cells.length ? row.cells[i] : const SizedBox(),
              ),
            ),
          ],
        ],
      ),
    );
    if (row.onTap == null) {
      return MergeSemantics(child: cells);
    }
    return ExamplePressable(
      onTap: row.onTap,
      pressedScale: 1,
      semanticsLabel: row.semanticsLabel,
      child: cells,
    );
  }
}

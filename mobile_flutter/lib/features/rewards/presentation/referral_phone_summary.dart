import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../shared/shared.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/referral_copy.dart';
import '../domain/rewards_models.dart';
import 'referral_explanation.dart';
import 'referral_sections.dart' show ReferralStageChip;
import 'referral_widgets.dart';

// ---------------------------------------------------------------------------
// The phone's Invite & Earn summary (blueprint p18, p20): four figures, the
// three most recent friends with what they still have to do, the three most
// recent rewards with where they stand, and a way into each full list. The
// desktop workspace reuses the rows.
// ---------------------------------------------------------------------------

/// Qualified friends · Earned · Awaiting credit · Paid to wallet, in a 2×2
/// grid. Each tile opens the list that explains its figure. Voucher
/// programmes label the last two "Ready to claim" and "Claimed".
class ReferralSummaryTiles extends StatelessWidget {
  const ReferralSummaryTiles({
    required this.summary,
    required this.onFriends,
    required this.onEarnings,
    super.key,
  });

  final ReferralSummary summary;
  final VoidCallback onFriends;
  final ValueChanged<ReferralEarningsFilter> onEarnings;

  @override
  Widget build(BuildContext context) {
    final totals = summary.rewards;
    final currency = totals.currency;
    final vouchers = summary.usesVouchers;
    final tiles = [
      _SummaryTile(
        key: const Key('referral_tile_qualified'),
        label: context.tr('Qualified friends'),
        value: '${summary.referrals.qualified}',
        onTap: onFriends,
      ),
      _SummaryTile(
        key: const Key('referral_tile_earned'),
        label: context.tr('Earned'),
        value: Money.formatAmount(currency, totals.earned),
        onTap: () => onEarnings(ReferralEarningsFilter.all),
      ),
      _SummaryTile(
        key: const Key('referral_tile_awaiting'),
        label: vouchers
            ? context.tr('Ready to claim')
            : context.tr('Awaiting credit'),
        value: Money.formatAmount(currency, totals.awaiting),
        onTap: () => onEarnings(ReferralEarningsFilter.awaiting),
      ),
      _SummaryTile(
        key: const Key('referral_tile_paid'),
        label:
            vouchers ? context.tr('Claimed') : context.tr('Paid reward ledger'),
        value: Money.formatAmount(currency, totals.paid),
        onTap: () => onEarnings(ReferralEarningsFilter.paid),
      ),
    ];
    Widget pair(int first) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[first]),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: tiles[first + 1]),
            ],
          ),
        );
    return Column(
      key: const Key('referral_summary_tiles'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(0),
        const SizedBox(height: AppSpacing.xs),
        pair(2),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    return ExamplePressable(
      onTap: onTap,
      semanticsLabel: '$label, $value',
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: light
              ? ExampleBorders.subtleLightAll
              : ExampleBorders.subtleOf(context),
          boxShadow: ExampleShadows.ambientOf(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
              child: Text(value, style: referralFigureStyle(context, size: 22)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line under the tiles: "This month: 3 qualified friends · $4.50
/// earned", from the calendar-month analytics, beside a compact sparkline
/// of qualified friends per week over the last eight weeks (the 90-day
/// range, or the month's own weeks until it arrives). Tapping opens the
/// earnings list. Nothing is mounted when the backend does not serve
/// analytics; a placeholder line holds the space while they load.
class ReferralMonthLine extends ConsumerWidget {
  const ReferralMonthLine({required this.onTap, super.key});

  final VoidCallback onTap;

  /// Weeks on the sparkline.
  static const int weeks = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month =
        ref.watch(referralAnalyticsProvider(ReferralAnalyticsRange.month));
    final data = month.when(
      data: (data) => data,
      error: (_, __) => null,
      loading: () => null,
    );
    if (data == null) {
      if (!month.isLoading) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Semantics(
          key: const Key('referral_month_line_loading'),
          label: context.tr('Loading analytics'),
          child: const ExcludeSemantics(
            child: ExampleSkeleton.card(height: 48),
          ),
        ),
      );
    }
    final quarter = ref.watch(
      referralAnalyticsProvider(ReferralAnalyticsRange.ninetyDays),
    );
    final series = quarter.when(
          data: (data) => data?.weekly,
          error: (_, __) => null,
          loading: () => null,
        ) ??
        data.weekly;
    final recent =
        series.length > weeks ? series.sublist(series.length - weeks) : series;
    final values = [for (final week in recent) week.qualified];
    final qualified = data.totals.qualified;
    final earned =
        Money.formatAmount(data.currency, data.totals.rewardsAccrued);
    final text = qualified == 1
        ? context
            .tr('This month: 1 qualified friend · {p0} earned', {'p0': earned})
        : context.tr('This month: {p0} qualified friends · {p1} earned',
            {'p0': qualified, 'p1': earned});
    final trend = values.length < 2
        ? ''
        : '. ${context.tr('Qualified friends per week')}: ${values.join(', ')}';
    final light = ExampleTheme.isLight(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: ExamplePressable(
        key: const Key('referral_month_line'),
        onTap: onTap,
        semanticsLabel: '$text$trend',
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: light
                ? ExampleBorders.subtleLightAll
                : ExampleBorders.subtleOf(context),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  key: const Key('referral_month_line_text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.primary(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (values.length >= 2) ...[
                const SizedBox(width: AppSpacing.sm),
                ExcludeSemantics(
                  child: ReferralQualifiedSparkline(
                    key: const Key('referral_month_sparkline'),
                    values: values,
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              ExampleRow.chevronOf(context),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eight tiny bars, one per week, scaled against the busiest week. A week
/// with nobody keeps a stub so the axis stays legible; the bars are in the
/// success accent because a qualified friend is a landed outcome. Decorative
/// only — the line beside it carries the figures for a screen reader.
class ReferralQualifiedSparkline extends StatelessWidget {
  const ReferralQualifiedSparkline({
    required this.values,
    this.width = 72,
    this.height = 24,
    super.key,
  });

  final List<int> values;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _QualifiedSparklinePainter(
            values: values,
            bar: ExampleInk.accent(context, ExampleColors.success),
            well: ExampleInk.tint(context, ExampleColors.lavender, alpha: .22),
          ),
        ),
      );
}

class _QualifiedSparklinePainter extends CustomPainter {
  const _QualifiedSparklinePainter({
    required this.values,
    required this.bar,
    required this.well,
  });

  final List<int> values;
  final Color bar;
  final Color well;

  static const double _gap = 3;
  static const double _stub = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    var top = 0;
    for (final value in values) {
      if (value > top) top = value;
    }
    final slot = (size.width + _gap) / values.length;
    final width = (slot - _gap).clamp(1.0, size.width);
    final paint = Paint();
    for (var i = 0; i < values.length; i++) {
      final x = i * slot;
      final height = top == 0
          ? _stub
          : (values[i] / top * size.height).clamp(_stub, size.height);
      paint.color = values[i] > 0 ? bar : well;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, width, height),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_QualifiedSparklinePainter oldDelegate) =>
      oldDelegate.bar != bar ||
      oldDelegate.well != well ||
      !_sameValues(oldDelegate.values, values);

  static bool _sameValues(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// What a friend still has to do, or how their earning window stands.
String referralFriendRequirementLabel(
  BuildContext context,
  ReferralFriend friend,
  ReferralOffer offer, {
  DateTime? now,
}) {
  switch (referralFriendNextStep(friend, offer, now: now)) {
    case ReferralFriendNextStep.verifyIdentity:
      return context.tr('Next: verify their identity');
    case ReferralFriendNextStep.getPaidCard:
      return context.tr(offer.promoCodePolicyEnabled ? 'Next: get a paid or promo card' : 'Next: get a paid card');
    case ReferralFriendNextStep.firstTopup:
      final minimum = offer.minimumTopup;
      return minimum != null && minimum > 0
          ? context.tr('Next: first eligible external top-up of at least {p0}',
              {'p0': formatReferralAmount(offer.welcomeCurrency, minimum)})
          : context.tr('Next: make a first eligible external top-up');
    case ReferralFriendNextStep.earning:
      final days = referralEarningDaysLeft(friend, now: now);
      if (days == null) return context.tr('Earning on eligible top-ups');
      if (days == 0) return context.tr('Earning window ends today');
      return context.tr('{p0} days of earning left', {'p0': days});
    case ReferralFriendNextStep.windowEnded:
      return context.tr('Earning window ended');
    case ReferralFriendNextStep.inProgress:
      return context.tr('In progress');
  }
}

FinanceStatusTone referralFriendStageTone(ReferralFriendStage stage) {
  switch (stage) {
    case ReferralFriendStage.qualified:
      return FinanceStatusTone.success;
    case ReferralFriendStage.windowEnded:
      return FinanceStatusTone.neutral;
    case ReferralFriendStage.invited:
      return FinanceStatusTone.info;
    case ReferralFriendStage.verifying:
    case ReferralFriendStage.cardIssued:
    case ReferralFriendStage.unknown:
      return FinanceStatusTone.warning;
  }
}

/// One friend: the name the inviter typed or the pseudonym, what they still
/// have to do, what they have earned the inviter, and their stage as a chip.
/// Never the friend's own balances, card or top-ups (blueprint p20).
class ReferralFriendRow extends StatelessWidget {
  const ReferralFriendRow({
    required this.friend,
    required this.offer,
    this.onTap,
    this.now,
    this.divider = false,
    super.key,
  });

  final ReferralFriend friend;
  final ReferralOffer offer;
  final VoidCallback? onTap;

  /// Injected clock for the window countdown; the wall clock when null.
  final DateTime? now;

  /// A hairline under the row, for rows placed straight into a list rather
  /// than a [ExampleListGroup].
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final stage = context.tr(friend.stage.label);
    final requirement =
        referralFriendRequirementLabel(context, friend, offer, now: now);
    final earned = Money.formatAmount(friend.currency, friend.earnedAmount);
    return ExampleRow(
      title: friend.displayName,
      subtitle: requirement,
      subtitleMaxLines: 2,
      minHeight: 64,
      divider: divider,
      leading: ExampleIconTile(
        icon: friend.recipientName == null
            ? Icons.person_outline_rounded
            : Icons.mark_email_read_outlined,
        color: ExampleColors.iris,
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(earned, style: referralFigureStyle(context)),
          const SizedBox(height: 4),
          ReferralStageChip(
            label: stage,
            tone: referralFriendStageTone(friend.stage),
          ),
        ],
      ),
      onTap: onTap,
      semanticsLabel: '${friend.displayName}, $stage, $requirement, $earned',
    );
  }
}

/// One ledger row: the event, the friend and the date, the amount and where
/// the reward stands. Tapping opens the receipt.
class ReferralRewardRow extends StatelessWidget {
  const ReferralRewardRow({
    required this.reward,
    required this.usesVouchers,
    this.onTap,
    this.divider = false,
    super.key,
  });

  final ReferralReward reward;
  final bool usesVouchers;
  final VoidCallback? onTap;

  /// A hairline under the row, for rows placed straight into a list.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final delivery =
        referralRewardEvidenceDelivery(reward, usesVouchers: usesVouchers);
    final when = reward.occurredAt ?? reward.createdAt;
    final date = when == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(when.toLocal());
    final parts = <String>[
      if (reward.friendAlias != null && reward.friendAlias!.isNotEmpty)
        reward.friendAlias!,
      if (date != null) date,
    ];
    final title = context.tr(reward.eventLabel);
    final subtitle = parts.isEmpty ? null : parts.join(' · ');
    final amount = Money.formatAmount(reward.currency, reward.amount);
    final status =
        referralDeliveryLabel(context, delivery, currency: reward.currency);
    return ExampleRow(
      title: title,
      subtitle: subtitle,
      minHeight: 64,
      divider: divider,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(amount, style: referralFigureStyle(context)),
          const SizedBox(height: 4),
          ReferralStatusPill(delivery: delivery),
        ],
      ),
      onTap: onTap ??
          () => showReferralRewardExplanation(
                context,
                reward,
                usesVouchers: usesVouchers,
              ),
      semanticsLabel: '$title, $status, ${subtitle ?? ''}, $amount',
    );
  }
}

/// The three most recent friends and a way to all of them.
class ReferralFriendsPreview extends StatelessWidget {
  const ReferralFriendsPreview({
    required this.friends,
    required this.offer,
    required this.onSeeAll,
    this.limit = 3,
    super.key,
  });

  final List<ReferralFriend> friends;
  final ReferralOffer offer;
  final VoidCallback onSeeAll;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return ExampleEmptyState(
        key: const Key('referral_friends_empty'),
        compact: true,
        icon: Icons.people_outline_rounded,
        title: context.tr('No friends yet'),
        body: context.tr('Share your link to invite your first friend.'),
      );
    }
    final recent = sortReferralFriendsNewestFirst(friends).take(limit);
    return ExampleListGroup(
      key: const Key('referral_friends'),
      title: context.tr('Friends'),
      action: context.tr('See all'),
      onAction: onSeeAll,
      children: [
        for (final friend in recent)
          ReferralFriendRow(friend: friend, offer: offer),
      ],
    );
  }
}

/// The three most recent rewards and a way to the whole ledger.
class ReferralRecentRewards extends StatelessWidget {
  const ReferralRecentRewards({
    required this.rewards,
    required this.summary,
    required this.onSeeAll,
    this.limit = 3,
    super.key,
  });

  final List<ReferralReward> rewards;
  final ReferralSummary summary;
  final VoidCallback onSeeAll;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (rewards.isEmpty) {
      return ExampleEmptyState(
        key: const Key('referral_rewards_empty'),
        compact: true,
        icon: Icons.savings_outlined,
        title: context.tr('No rewards yet'),
        body: context
            .tr('Rewards appear here as your friends qualify and top up.'),
      );
    }
    final recent = sortReferralRewardsNewestFirst(rewards).take(limit);
    return ExampleListGroup(
      key: const Key('referral_rewards'),
      title: context.tr('Recent rewards'),
      action: context.tr('See all'),
      onAction: onSeeAll,
      children: [
        for (final reward in recent)
          ReferralRewardRow(reward: reward, usesVouchers: summary.usesVouchers),
      ],
    );
  }
}

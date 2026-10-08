import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart' show friendlyErrorMessage;
import '../application/referral_pager.dart';
import '../domain/referral_copy.dart';
import '../domain/rewards_models.dart';

// ---------------------------------------------------------------------------
// Small pieces the referral screens share: the status vocabulary (one label,
// one icon and one tone per delivery state, so a status is never colour
// alone), filter chips, the "Load more" foot of a paged list, its skeleton,
// and the totals strip. Example only — the white-label tree never mounts them.
// ---------------------------------------------------------------------------

/// Back from a rewards sub-screen: the previous page when there is one, the
/// Rewards page otherwise (a deep link has no history). Without a router —
/// a widget test hosting the screen directly — it pops the navigator.
void referralNavigateBack(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    Navigator.maybePop(context);
    return;
  }
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(AppRoutes.rewards);
  }
}

/// The app bar's back control on a rewards sub-screen.
Widget referralBackButton(BuildContext context) => IconButton(
      tooltip: context.tr('Back'),
      onPressed: () => referralNavigateBack(context),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
    );

/// Body copy inside a referral panel: 13 px on the secondary ink, which
/// clears the 4.5:1 body floor in both themes.
TextStyle referralBodyStyle(BuildContext context) => TextStyle(
      fontSize: 13,
      height: 1.45,
      color: ExampleInk.secondary(context),
    );

/// A figure: bold, tabular, on the primary ink.
TextStyle referralFigureStyle(BuildContext context, {double size = 14}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: size >= 20 ? -.3 : 0,
      color: ExampleInk.primary(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// The full sentence for a delivery state, in the words the copy contract
/// allows: "Added to USD balance" only once it is there, "Waiting for…"
/// otherwise.
String referralDeliveryLabel(
  BuildContext context,
  ReferralRewardDelivery delivery, {
  required String currency,
}) {
  switch (delivery) {
    case ReferralRewardDelivery.awaitingConfirmation:
      return context.tr('Waiting for provider confirmation');
    case ReferralRewardDelivery.awaitingCredit:
      return context.tr('Waiting for wallet credit');
    case ReferralRewardDelivery.readyToClaim:
      return context.tr('Ready to claim');
    case ReferralRewardDelivery.credited:
      return context.tr('Added to {p0} balance', {'p0': currency});
    case ReferralRewardDelivery.claimed:
      return context.tr('Claimed');
    case ReferralRewardDelivery.failed:
      return context.tr('Could not be credited');
    case ReferralRewardDelivery.held:
      return context.tr('Reward held');
    case ReferralRewardDelivery.offsetSettled:
      return context.tr('Settled against an adjustment; no wallet credit.');
    case ReferralRewardDelivery.settlementUnavailable:
      return context.tr('Cash settlement details unavailable');
    case ReferralRewardDelivery.underReview:
      return context.tr('Waiting for review or calculation');
  }
}

/// The one- or two-word form of [referralDeliveryLabel], for a pill.
String referralDeliveryShortLabel(
    BuildContext context, ReferralRewardDelivery delivery) {
  switch (delivery) {
    case ReferralRewardDelivery.awaitingConfirmation:
      return context.tr('Pending');
    case ReferralRewardDelivery.awaitingCredit:
      return context.tr('Crediting');
    case ReferralRewardDelivery.readyToClaim:
      return context.tr('Ready to claim');
    case ReferralRewardDelivery.credited:
      return context.tr('Credited');
    case ReferralRewardDelivery.claimed:
      return context.tr('Claimed');
    case ReferralRewardDelivery.failed:
      return context.tr('Failed');
    case ReferralRewardDelivery.held:
      return context.tr('Held');
    case ReferralRewardDelivery.offsetSettled:
      return context.tr('Offset');
    case ReferralRewardDelivery.settlementUnavailable:
      return context.tr('Details unavailable');
    case ReferralRewardDelivery.underReview:
      return context.tr('In review');
  }
}

IconData referralDeliveryIcon(ReferralRewardDelivery delivery) {
  switch (delivery) {
    case ReferralRewardDelivery.awaitingConfirmation:
    case ReferralRewardDelivery.underReview:
    case ReferralRewardDelivery.held:
    case ReferralRewardDelivery.offsetSettled:
    case ReferralRewardDelivery.settlementUnavailable:
      return Icons.schedule_rounded;
    case ReferralRewardDelivery.awaitingCredit:
      return Icons.hourglass_top_rounded;
    case ReferralRewardDelivery.readyToClaim:
      return Icons.redeem_rounded;
    case ReferralRewardDelivery.credited:
    case ReferralRewardDelivery.claimed:
      return Icons.check_circle_rounded;
    case ReferralRewardDelivery.failed:
      return Icons.error_outline_rounded;
  }
}

/// Brand token for a delivery state. Only a landed reward is green; anything
/// still with the provider stays in the accent, so a ledger of pending rows
/// never looks like a ledger of payments.
Color referralDeliveryColor(ReferralRewardDelivery delivery) {
  switch (delivery) {
    case ReferralRewardDelivery.credited:
    case ReferralRewardDelivery.claimed:
    case ReferralRewardDelivery.readyToClaim:
      return ExampleColors.success;
    case ReferralRewardDelivery.failed:
      return ExampleColors.warning;
    case ReferralRewardDelivery.awaitingConfirmation:
    case ReferralRewardDelivery.awaitingCredit:
    case ReferralRewardDelivery.underReview:
    case ReferralRewardDelivery.held:
    case ReferralRewardDelivery.offsetSettled:
    case ReferralRewardDelivery.settlementUnavailable:
      return ExampleColors.iris;
  }
}

/// A delivery state as icon plus sentence, on one line.
class ReferralStatusLine extends StatelessWidget {
  const ReferralStatusLine({
    required this.delivery,
    required this.currency,
    this.fontSize = 13,
    super.key,
  });

  final ReferralRewardDelivery delivery;
  final String currency;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = ExampleInk.accent(context, referralDeliveryColor(delivery));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(referralDeliveryIcon(delivery), size: 16, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            referralDeliveryLabel(context, delivery, currency: currency),
            style: TextStyle(
              fontSize: fontSize,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// The delivery state as a pill with its icon.
class ReferralStatusPill extends StatelessWidget {
  const ReferralStatusPill({required this.delivery, super.key});

  final ReferralRewardDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final color = referralDeliveryColor(delivery);
    final ink = ExampleInk.accent(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ExampleInk.tint(context, color),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(referralDeliveryIcon(delivery), size: 12, color: ink),
          const SizedBox(width: 4),
          Flexible(
              child: Text(
            referralDeliveryShortLabel(context, delivery),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .2,
              color: ink,
            ),
          )),
        ],
      ),
    );
  }
}

/// A horizontal row of single-choice filter chips. 44 pt targets; the active
/// chip carries the emphasis edge and a tint, and announces itself selected.
class ReferralFilterChips<T> extends StatelessWidget {
  const ReferralFilterChips({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            _FilterChip(
              label: options[i].label,
              active: options[i].value == selected,
              onTap: () => onChanged(options[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: ExamplePressable(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.sm)),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? ExampleInk.tint(context, ExampleColors.violet, alpha: .16)
                : ExampleSurface.of(context, 2),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: active
                ? ExampleBorders.emphasisOf(context)
                : ExampleBorders.subtleOf(context),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active
                  ? ExampleInk.primary(context)
                  : ExampleInk.secondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// The foot of a paged list: "Load more" while the last page was full, the
/// failure and a retry when a later page failed, nothing once the list is
/// complete.
class ReferralLoadMore extends StatelessWidget {
  const ReferralLoadMore({required this.pager, super.key});

  final ReferralPager<Object?> pager;

  @override
  Widget build(BuildContext context) {
    final failure = pager.moreError;
    if (failure != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            friendlyErrorMessage(failure),
            textAlign: TextAlign.center,
            style: referralBodyStyle(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExampleGlassButton(
            key: const Key('referral_load_more_retry'),
            label: context.tr('Try again'),
            tone: ExampleGlassButtonTone.neutral,
            sheen: false,
            onPressed: pager.loadMore,
          ),
        ],
      );
    }
    if (!pager.hasMore) return const SizedBox.shrink();
    return ExampleGlassButton(
      key: const Key('referral_load_more'),
      label: context.tr('Load more'),
      tone: ExampleGlassButtonTone.neutral,
      sheen: false,
      loading: pager.loadingMore,
      loadingSemanticsLabel: 'Loading more',
      onPressed: pager.loadingMore ? null : pager.loadMore,
    );
  }
}

/// Row placeholders under one sheen host, for a list that has not arrived.
class ReferralListSkeleton extends StatelessWidget {
  const ReferralListSkeleton({this.rows = 5, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) => Semantics(
        label: context.tr('Loading'),
        child: ExcludeSemantics(
          child: ExampleSheen.text(
            intensity: ExampleSheenIntensity.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ExampleSkeleton.line(width: 120, height: 14, sheen: false),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < rows; i++)
                  const ExampleSkeleton.row(sheen: false),
              ],
            ),
          ),
        ),
      );
}

/// Earned / awaiting / paid, in one strip, with the reporting note that
/// says what the figures are: confirmed by the provider, in the programme's
/// currency. Voucher programmes label the last two "Ready to claim" and
/// "Claimed".
class ReferralTotalsStrip extends StatelessWidget {
  const ReferralTotalsStrip({required this.summary, super.key});

  final ReferralSummary summary;

  @override
  Widget build(BuildContext context) {
    final totals = summary.rewards;
    final currency = totals.currency;
    final vouchers = summary.usesVouchers;
    final columns = [
      (
        label: context.tr('Earned'),
        value: Money.formatAmount(currency, totals.earned),
      ),
      (
        label: vouchers
            ? context.tr('Ready to claim')
            : context.tr('Awaiting credit'),
        value: Money.formatAmount(currency, totals.awaiting),
      ),
      (
        label:
            vouchers ? context.tr('Claimed') : context.tr('Paid reward ledger'),
        value: Money.formatAmount(currency, totals.paid),
      ),
    ];
    return ExampleGlassPanel(
      key: const Key('referral_totals'),
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          columns[i].label,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            columns[i].value,
                            style: referralFigureStyle(context, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr('Figures update after provider confirmation · {p0}',
                {'p0': currency}),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

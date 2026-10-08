import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../domain/referral_copy.dart';
import '../domain/rewards_models.dart';
import 'referral_offer_card.dart';
import 'referral_widgets.dart';

/// "What would I earn?" — a top-up amount in, the recurring reward at the
/// current level out.
///
/// The arithmetic is [estimateReferralReward]'s, so the figure here is the
/// same one the ledger will show: rate × the eligible part of the top-up
/// for a share of the top-up, the fixed amount per top-up, and for the fee
/// and margin modes the *most* the top-up can pay — the summary carries no
/// fee or margin data, so the rate is applied to the whole amount and the
/// result is labelled "up to". Both caps are applied and explained. The
/// whole panel is an illustration and says so; nothing here is a promise
/// of settlement.
class ReferralRewardCalculator extends StatefulWidget {
  const ReferralRewardCalculator({
    required this.offer,
    this.initialAmount = 100,
    super.key,
  });

  /// The offer as it pays this member now ([effectiveReferralOffer]).
  final ReferralOffer offer;

  /// Prefilled so the panel answers before anything is typed.
  final double initialAmount;

  @override
  State<ReferralRewardCalculator> createState() =>
      _ReferralRewardCalculatorState();
}

class _ReferralRewardCalculatorState extends State<ReferralRewardCalculator> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialAmount == widget.initialAmount.roundToDouble()
        ? widget.initialAmount.toInt().toString()
        : widget.initialAmount.toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _amount =>
      double.tryParse(_controller.text.replaceAll(',', '').trim());

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final currency = offer.welcomeCurrency;
    final basis = ReferralRecurringBasis.fromWire(offer.topupCalculationType);
    final amount = _amount;
    final estimate =
        amount == null ? null : estimateReferralReward(offer, amount);
    final body = referralBodyStyle(context);
    final quiet = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: ExampleInk.secondary(context),
    );

    final Widget result;
    if (!offer.hasTopupReward) {
      result = Text(
        context.tr('This offer pays no recurring reward on top-ups.'),
        key: const Key('referral_calculator_result'),
        style: body,
      );
    } else if (estimate == null) {
      result = Text(
        context.tr('Enter a top-up amount to see the reward.'),
        key: const Key('referral_calculator_result'),
        style: body,
      );
    } else {
      final money = formatReferralAmount(currency, estimate.amount);
      final headline = estimate.isUpperBound
          ? context.tr('Up to {p0}', {'p0': money})
          : context.tr('You receive {p0}', {'p0': money});
      final String detail;
      switch (basis) {
        case ReferralRecurringBasis.topup:
          detail = context.tr('{p0} of {p1} eligible credited top-up', {
            'p0': formatReferralPercent(estimate.rate),
            'p1': formatReferralAmount(currency, estimate.eligibleAmount),
          });
        case ReferralRecurringBasis.fee:
          detail = context.tr(
            'Depends on the settled fee after cost. Shown as the most this top-up can pay at {p0}.',
            {'p0': formatReferralPercent(estimate.rate)},
          );
        case ReferralRecurringBasis.margin:
          detail = context.tr(
            'Depends on the settled margin. Shown as the most this top-up can pay at {p0}.',
            {'p0': formatReferralPercent(estimate.rate)},
          );
        case ReferralRecurringBasis.fixed:
          detail = referralRecurringPhrase(context, offer, basis);
      }
      final volumeCap = offer.maxEligibleVolumePerRelationship;
      result = Column(
        key: const Key('referral_calculator_result'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            headline,
            key: const Key('referral_calculator_headline'),
            style: referralFigureStyle(context, size: 26),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(detail, style: body),
          if (estimate.volumeCapped && volumeCap != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr(
                'Only {p0} of this top-up would be eligible under the {p1} limit per friend.',
                {
                  'p0': formatReferralAmount(currency, estimate.eligibleAmount),
                  'p1': formatReferralAmount(currency, volumeCap),
                },
              ),
              key: const Key('referral_calculator_cap'),
              style: body,
            ),
          ],
          if (estimate.rewardCapped &&
              offer.maximumRecurringReward != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('Recurring rewards stop at {p0} per friend.', {
                'p0': formatReferralAmount(
                    currency, offer.maximumRecurringReward!),
              }),
              style: body,
            ),
          ],
        ],
      );
    }

    final volumeCap = offer.maxEligibleVolumePerRelationship;
    return ExampleGlassPanel(
      key: const Key('referral_calculator'),
      radius: AppRadii.lg,
      borderAlpha: .30,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('What would I earn?'),
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: ExampleInk.primary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.tr(
                'Enter one of your friend’s top-ups to see what it would pay you at your current level.'),
            style: body,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('referral_calculator_amount'),
            controller: _controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: TextStyle(
              fontSize: 16,
              color: ExampleInk.primary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              labelText: context.tr('Top-up amount'),
              prefixText: '$currency ',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          result,
          if (offer.hasTopupReward && volumeCap != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr(
                'Up to {p0} in eligible credited top-ups counts per friend.',
                {'p0': formatReferralAmount(currency, volumeCap)},
              ),
              key: const Key('referral_calculator_volume'),
              style: quiet,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr(
                "Illustration only. Actual rewards depend on settlement and your friend's eligible volume."),
            key: const Key('referral_calculator_disclaimer'),
            style: quiet.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

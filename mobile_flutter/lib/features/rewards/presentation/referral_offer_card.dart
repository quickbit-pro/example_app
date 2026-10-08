import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../profile/presentation/security_sheets.dart'
    show showExampleSheet, ExampleSheetHeader, ExampleSheetNote;
import '../domain/referral_copy.dart';
import '../domain/rewards_models.dart';
import 'referral_widgets.dart';

/// The offer, as one card a customer could explain to a friend.
///
/// Blueprint p18: state both rewards, then exactly how the friend qualifies,
/// then the window and the cap, then how the money arrives — and never fold
/// the conditions into a footnote. The two reward lines come from the
/// server-resolved offer without mixing in a later tier
/// ([effectiveReferralOffer]); the checklist comes from the offer's flags;
/// every figure is the API's.
///
/// [actions] is the card's foot: Share and Copy link on the phone, the
/// "Invite friends" email fallback when the summary carries no code, nothing
/// on the desktop Offer tab (which has its own Share tab). The terms gate is
/// never nested here; the screen mounts it right under this card, where the
/// share action would be.
class ReferralOfferCard extends StatelessWidget {
  const ReferralOfferCard({
    required this.summary,
    this.actions,
    super.key,
  });

  final ReferralSummary summary;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final published = summary.offer;
    final offer = effectiveReferralOffer(summary);
    final currency = offer.welcomeCurrency;
    final basis = ReferralRecurringBasis.fromWire(offer.topupCalculationType);
    final friendLine = published != null && offer.hasWelcome
        ? context.tr(offer.promoCodePolicyEnabled ? 'Friend gets {p0} without a promo code' : 'Friend gets {p0}', {
            'p0': formatReferralAmount(currency, offer.welcomeAmount),
          })
        : null;
    final youLine = published == null ? null : _youLine(context, offer, basis);
    final steps = published == null
        ? const <ReferralQualificationStep>[]
        : referralQualificationSteps(offer);
    final window = published != null && offer.hasTopupReward
        ? _windowLine(context, offer, basis)
        : null;
    final legal = <String>[
      if (published != null && (offer.requiresTopup || offer.hasTopupReward))
        context.tr(
            'Only external credited top-ups qualify. Reward funds and internal transfers are excluded.'),
      if (published != null && offer.customerRecurringRate > 0)
        context.tr('Your friend also receives {p0} of settled margin.', {
          'p0': formatReferralPercent(offer.customerRecurringRate),
        }),
      if (published != null && offer.maximumRecurringReward != null)
        context.tr(
          'Total recurring rewards across all recipients are capped at {p0} per friend. Refunds do not reopen this limit.',
          {
            'p0': formatReferralAmount(currency, offer.maximumRecurringReward!),
          },
        ),
    ];
    if (published != null && offer.hasTopupReward) {
      if (offer.maxEligibleVolumePerRelationship == null) {
        legal.add(context.tr('Eligible top-up volume: no cap per friend.'));
      }
      if (offer.maximumRecurringReward == null) {
        legal.add(context.tr('Recurring rewards: no cap per friend.'));
      }
      if (offer.volumeCapSource == 'PROGRAM_DEFAULT') {
        legal.add(context.tr('Volume cap inherited from program default'));
      }
      if (offer.recurringRewardCapSource == 'PROGRAM_DEFAULT') {
        legal.add(context.tr('Reward cap inherited from program default'));
      }
      legal.add(context.tr(
          'Each referral keeps the tier, rate, caps and earning window accepted at sign-up. Later tier changes apply to new referrals and do not reset existing counters.'));
    }
    final terms = summary.terms;
    final body = referralBodyStyle(context);
    final quiet = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: ExampleInk.secondary(context),
    );
    final actions = this.actions;

    return ExampleGlassPanel(
      key: const Key('referral_offer_card'),
      radius: AppRadii.lg,
      borderAlpha: .30,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('INVITE & EARN'),
              style: ExampleTextStyles.label(context)),
          if (friendLine != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              friendLine,
              key: const Key('referral_offer_friend'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
                height: 1.15,
                color: ExampleInk.primary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (youLine != null) ...[
            SizedBox(height: friendLine == null ? AppSpacing.xs : 6),
            Text(
              youLine,
              key: const Key('referral_offer_you'),
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: ExampleInk.primary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (summary.hasProgramDescription) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              summary.programDescription!.trim(),
              key: const Key('referral_offer_description'),
              style: body,
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr('How your friend qualifies'),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: ExampleInk.primary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ReferralQualificationChecklist(
              key: const Key('referral_offer_steps'),
              steps: steps,
              offer: offer,
            ),
          ],
          if (window != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              window,
              key: const Key('referral_offer_window'),
              style: body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          for (final line in legal) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(line, style: quiet),
          ],
          const SizedBox(height: AppSpacing.sm),
          ReferralDeliveryNote(summary: summary),
          if (terms != null && terms.published) ...[
            const SizedBox(height: AppSpacing.xxs),
            _TermsLink(terms: terms),
          ],
          if (actions != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 1,
              child: ColoredBox(
                color: ExampleBorders.hairlineSideOf(context).color,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            actions,
          ],
        ],
      ),
    );
  }

  /// "You get $1 + 0.25% of eligible credited top-ups", or the half of it
  /// the offer pays. Null when it pays the inviter nothing.
  static String? _youLine(
    BuildContext context,
    ReferralOffer offer,
    ReferralRecurringBasis basis,
  ) {
    final currency = offer.welcomeCurrency;
    final qualification = offer.hasQualificationReward
        ? (offer.qualificationCalculationType == 'PERCENT_OF_CARD_FEE'
            ? context.tr('{p0} of the card fee', {
                'p0': formatReferralPercent(offer.qualificationRate),
              })
            : formatReferralAmount(currency, offer.qualificationRate))
        : null;
    final recurring = offer.hasTopupReward
        ? referralRecurringPhrase(context, offer, basis)
        : null;
    if (qualification != null && recurring != null) {
      return context.tr('You get {p0} + {p1}', {
        'p0': qualification,
        'p1': recurring,
      });
    }
    if (qualification != null) {
      return context.tr('You get {p0} when your friend qualifies', {
        'p0': qualification,
      });
    }
    if (recurring != null) {
      return context.tr('You get {p0}', {'p0': recurring});
    }
    return null;
  }

  /// "0.25% for 90 days, up to $5,000 in eligible credited top-ups per
  /// friend", with each clause present only when the offer sets it.
  static String _windowLine(
    BuildContext context,
    ReferralOffer offer,
    ReferralRecurringBasis basis,
  ) {
    final rate = referralRateShort(context, offer, basis);
    final window = offer.earningWindowDays > 0
        ? context.tr('{p0} for {p1} days', {
            'p0': rate,
            'p1': offer.earningWindowDays,
          })
        : context.tr('{p0} with no end date', {'p0': rate});
    final cap = offer.maxEligibleVolumePerRelationship;
    if (cap == null) return window;
    return context.tr(
      '{p0}, up to {p1} in eligible credited top-ups per friend',
      {
        'p0': window,
        'p1': formatReferralAmount(offer.welcomeCurrency, cap),
      },
    );
  }
}

/// "0.25%" or "$0.50 per top-up".
String referralRateShort(
  BuildContext context,
  ReferralOffer offer,
  ReferralRecurringBasis basis,
) =>
    basis == ReferralRecurringBasis.fixed
        ? context.tr('{p0} per top-up', {
            'p0': formatReferralAmount(offer.welcomeCurrency, offer.topupRate),
          })
        : formatReferralPercent(offer.topupRate);

/// The recurring reward with its denominator named: "0.25% of eligible
/// credited top-ups", "of the top-up fee", "of settled margin", or the fixed
/// amount per top-up.
String referralRecurringPhrase(
  BuildContext context,
  ReferralOffer offer,
  ReferralRecurringBasis basis,
) {
  switch (basis) {
    case ReferralRecurringBasis.topup:
      return context.tr('{p0} of eligible credited top-ups', {
        'p0': formatReferralPercent(offer.topupRate),
      });
    case ReferralRecurringBasis.fee:
      return context.tr('{p0} of the top-up fee after cost', {
        'p0': formatReferralPercent(offer.topupRate),
      });
    case ReferralRecurringBasis.margin:
      return context.tr('{p0} of settled margin', {
        'p0': formatReferralPercent(offer.topupRate),
      });
    case ReferralRecurringBasis.fixed:
      return context.tr('{p0} per top-up', {
        'p0': formatReferralAmount(offer.welcomeCurrency, offer.topupRate),
      });
  }
}

/// The step's imperative, for the checklist.
String referralQualificationStepLabel(
  BuildContext context,
  ReferralQualificationStep step,
  ReferralOffer offer,
) {
  switch (step) {
    case ReferralQualificationStep.verifyIdentity:
      return context.tr('Verify their identity');
    case ReferralQualificationStep.getPaidCard:
      return context.tr(offer.promoCodePolicyEnabled ? 'Get a paid or promo card' : 'Get a paid card');
    case ReferralQualificationStep.firstTopup:
      final minimum = offer.minimumTopup;
      return minimum != null && minimum > 0
          ? context.tr('First eligible external top-up of at least {p0}', {
              'p0': formatReferralAmount(offer.welcomeCurrency, minimum),
            })
          : context.tr('Make a first eligible external top-up');
  }
}

/// The numbered qualification steps.
class ReferralQualificationChecklist extends StatelessWidget {
  const ReferralQualificationChecklist({
    required this.steps,
    required this.offer,
    super.key,
  });

  final List<ReferralQualificationStep> steps;
  final ReferralOffer offer;

  @override
  Widget build(BuildContext context) {
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          MergeSemantics(
            child: Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ExampleInk.tint(context, ExampleColors.iris),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        referralQualificationStepLabel(
                            context, steps[i], offer),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: ExampleInk.primary(context),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// How rewards arrive: wallet credits after provider confirmation (with the
/// minimum the programme credits at, when it sets one) or vouchers.
class ReferralDeliveryNote extends StatelessWidget {
  const ReferralDeliveryNote({required this.summary, super.key});

  final ReferralSummary summary;

  @override
  Widget build(BuildContext context) {
    final style = referralBodyStyle(context);
    if (summary.usesVouchers) {
      return Text(
        context.tr('Rewards are issued as vouchers you redeem from this page.'),
        key: const Key('referral_voucher_delivery'),
        style: style,
      );
    }
    final currency = summary.rewards.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
              'Wallet credits arrive automatically after provider confirmation.'),
          key: const Key('referral_offer_delivery'),
          style: style,
        ),
        if (summary.minimumCreditAmount > 0) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.tr(
              'Rewards are added to your {p0} balance automatically once they reach {p1}.',
              {
                'p0': currency,
                'p1':
                    formatReferralAmount(currency, summary.minimumCreditAmount),
              },
            ),
            key: const Key('referral_minimum_credit'),
            style: style,
          ),
        ],
      ],
    );
  }
}

class _TermsLink extends StatelessWidget {
  const _TermsLink({required this.terms});

  final ReferralTerms terms;

  @override
  Widget build(BuildContext context) {
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ExamplePressable(
        key: const Key('referral_offer_terms_link'),
        onTap: () => showReferralTermsSheet(context, terms),
        semanticsLabel: context.tr('View full reward terms'),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  context.tr('View full reward terms'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The terms text with its version and when this member accepted it.
class ReferralTermsView extends StatelessWidget {
  const ReferralTermsView({required this.terms, super.key});

  final ReferralTerms terms;

  @override
  Widget build(BuildContext context) {
    final acceptedAt = terms.acceptedAt;
    final meta = [
      context.tr('Terms version: {p0}', {'p0': terms.version}),
      acceptedAt == null
          ? context.tr('Not accepted yet')
          : context.tr('Accepted on {p0}', {
              'p0': MaterialLocalizations.of(context)
                  .formatMediumDate(acceptedAt.toLocal()),
            }),
    ].join(' · ');
    final privacy = terms.privacyNotice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          meta,
          key: const Key('referral_terms_meta'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: ExampleInk.secondary(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          terms.text ?? '',
          key: const Key('referral_terms_full_text'),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: ExampleInk.primary(context),
          ),
        ),
        if (privacy != null && privacy.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            context.tr('Privacy notice'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ExampleSheetNote(privacy),
        ],
      ],
    );
  }
}

/// Opens the full terms in a sheet.
Future<void> showReferralTermsSheet(BuildContext context, ReferralTerms terms) {
  return showExampleSheet<void>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(title: sheetContext.tr('Reward terms')),
        const SizedBox(height: AppSpacing.sm),
        ReferralTermsView(terms: terms),
        const SizedBox(height: AppSpacing.md),
        ExampleGlassButton(
          label: sheetContext.tr('Close'),
          tone: ExampleGlassButtonTone.neutral,
          sheen: false,
          onPressed: () => Navigator.pop(sheetContext),
        ),
      ],
    ),
  );
}

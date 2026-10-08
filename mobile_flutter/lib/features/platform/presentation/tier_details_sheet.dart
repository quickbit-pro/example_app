import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../profile/presentation/security_sheets.dart'
    show showExampleSheet, ExampleSheetHeader, ExampleSheetNote, ExampleSheetCta;
import '../application/platform_providers.dart';
import '../domain/tier_includes.dart';
import 'tiers_screen.dart';

/// Opens what a plan includes: its price, features, benefits and limits, and
/// the cards it carries with their allowances and fees.
///
/// Kept out of the plan list on purpose. The list is where a customer
/// compares and picks; this is where they read the contract, so it opens
/// only when asked. The cards come from their own call, made on the first
/// open and cached per plan.
///
/// [onChoose] adds the plan's "Choose this plan" action; the sheet closes
/// before it runs, so the caller's own progress and result are what the
/// customer sees.
Future<void> showTierDetailsSheet(
  BuildContext context, {
  required PlatformResource tier,
  bool isCurrent = false,
  VoidCallback? onChoose,
}) {
  return showExampleSheet<void>(
    context,
    builder: (sheetContext) => TierDetailsSheet(
      tier: tier,
      isCurrent: isCurrent,
      onChoose: onChoose == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onChoose();
            },
    ),
  );
}

/// The quiet control that opens [showTierDetailsSheet]. Text on the surface
/// on a 44 pt target, so it never competes with a plan's own action.
class TierDetailsButton extends StatelessWidget {
  const TierDetailsButton({
    required this.tierName,
    required this.onPressed,
    super.key,
  });

  final String tierName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = ExampleInk.accent(context, ExampleColors.iris);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wraps rather than overflowing a narrow station at large text
          // sizes or in a longer language.
          Flexible(
            child: Text(
              context.tr("What's included"),
              // The plan's name reaches assistive technology, so a list of
              // these reads as distinct controls.
              semanticsLabel:
                  context.tr('What the {p0} plan includes', {'p0': tierName}),
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 18, color: ink),
        ],
      ),
    );
  }
}

class TierDetailsSheet extends ConsumerWidget {
  const TierDetailsSheet({
    required this.tier,
    this.isCurrent = false,
    this.onChoose,
    super.key,
  });

  final PlatformResource tier;
  final bool isCurrent;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final includes = tierPlanIncludesOf(tier);
    final limits = _tierLimits(tier);
    final tierId = tierIdOf(tier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(
          title: tierTitleOf(tier),
          actions: [
            if (isCurrent)
              ExamplePill(
                label: context.tr('Current'),
                color: ExampleColors.success,
                dot: true,
              ),
          ],
        ),
        if (includes.hasPrice) ...[
          const SizedBox(height: AppSpacing.md),
          _PlanPrice(includes: includes),
        ],
        if (includes.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            includes.description,
            style: _bodyStyle(context),
          ),
        ],
        if (includes.features.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final feature in includes.features)
            _Bullet(text: feature, icon: false),
        ],
        if (includes.hasBenefits) ...[
          const _SectionGap(),
          _SectionHeading(context.tr('Plan benefits')),
          const SizedBox(height: AppSpacing.xs),
          if (includes.includesIban)
            _Bullet(text: context.tr('Account with IBAN included')),
          if (includes.dailyRewards)
            _Bullet(text: context.tr('Daily rewards enabled')),
          for (final benefit in includes.benefits) _Bullet(text: benefit),
        ],
        if (limits.isNotEmpty) ...[
          const _SectionGap(),
          _SectionHeading(context.tr('Limits')),
          const SizedBox(height: AppSpacing.xs),
          for (final row in limits)
            _FactRow(label: context.tr(row.label), value: row.value),
        ],
        const _SectionGap(),
        _SectionHeading(context.tr('Cards available with this plan')),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.tr(
              'The plan price and card fees are separate. Included card allowances are shown below.'),
          style: _captionStyle(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (tierId == null)
          _CardsMessage(context.tr('No cards are listed for this plan yet.'))
        else
          _PlanCards(tierId: '$tierId'),
        const _SectionGap(),
        const ExampleSheetNote(
            'Account and card activation are subject to verification.'),
        const SizedBox(height: AppSpacing.md),
        if (onChoose != null && !isCurrent) ...[
          ExampleSheetCta(
            label: context.tr('Choose this plan'),
            onPressed: onChoose,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        ExampleGlassButton(
          label: context.tr('Close'),
          tone: ExampleGlassButtonTone.neutral,
          ground: ExampleGlassGround.surface,
          sheen: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// The subscription, set once: the monthly figure large, the yearly option
/// under it. A published zero is "Free", as on the plan list.
class _PlanPrice extends StatelessWidget {
  const _PlanPrice({required this.includes});

  final TierPlanIncludes includes;

  @override
  Widget build(BuildContext context) {
    final monthly = includes.monthlyFee;
    final yearly = includes.yearlyFee;
    final headline = monthly ?? yearly!;
    final free = headline == 0 && (yearly == null || yearly == 0);
    final String? caption;
    if (free) {
      caption = null;
    } else if (monthly == null) {
      caption = context.tr('per year');
    } else if (yearly == null) {
      caption = context.tr('per month');
    } else {
      caption = context.tr('per month, or {p0} per year',
          {'p0': _money(yearly, includes.currency)});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Plan subscription').toUpperCase(),
          style: ExampleTextStyles.label(context),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          free ? context.tr('Free') : _money(headline, includes.currency),
          style: TextStyle(
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: ExampleInk.primary(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption, style: _captionStyle(context)),
        ],
      ],
    );
  }
}

/// The plan's cards, fetched when the sheet first opens.
class _PlanCards extends ConsumerWidget {
  const _PlanCards({required this.tierId});

  final String tierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExampleStateSwitch(
      alignment: Alignment.topCenter,
      child: ref.watch(cardTierProvider(tierId)).when(
            data: (cardTier) {
              final offers = tierCardOffersOf(cardTier);
              if (offers.isEmpty) {
                return _CardsMessage(
                  context.tr('No cards are listed for this plan yet.'),
                  key: const ValueKey('tier-cards-empty'),
                );
              }
              return Column(
                key: const ValueKey('tier-cards'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < offers.length; index++) ...[
                    if (index > 0)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: SizedBox(
                          height: 1,
                          child: ColoredBox(
                            color: ExampleBorders.hairlineSideOf(context).color,
                          ),
                        ),
                      ),
                    _CardOffer(offer: offers[index]),
                  ],
                ],
              );
            },
            error: (error, stackTrace) => Column(
              key: const ValueKey('tier-cards-error'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardsMessage(
                    context.tr('We could not load the cards for this plan.')),
                TextButton(
                  onPressed: () => ref.invalidate(cardTierProvider(tierId)),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        ExampleInk.accent(context, ExampleColors.iris),
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(context.tr('Try again')),
                ),
              ],
            ),
            loading: () => ExampleSkeleton.card(
              key: const ValueKey('tier-cards-loading'),
              height: 148,
              semanticsLabel: context.tr('Loading cards for this plan'),
            ),
          ),
    );
  }
}

/// One card programme: what it is, what it does, what it costs.
class _CardOffer extends StatelessWidget {
  const _CardOffer({required this.offer});

  final TierCardOffer offer;

  @override
  Widget build(BuildContext context) {
    final kind = offer.isVirtual && offer.isPhysical
        ? 'Virtual and physical'
        : offer.isPhysical
            ? 'Physical'
            : offer.isVirtual
                ? 'Virtual'
                : null;
    final fees = <({String label, String value})>[
      if (offer.freeCards != null)
        (
          label: 'Free cards included',
          value: _freeCardsText(context, offer),
        ),
      if (offer.maxCards != null)
        (label: 'Maximum cards you can order', value: '${offer.maxCards}'),
      (label: 'Issuance fee', value: _fee(context, offer.issuanceFee, offer)),
      (
        label: 'Plan card subscription / month',
        value: _fee(context, offer.planMonthlyFee, offer),
      ),
      (
        label: 'Card subscription / month',
        value: _fee(context, offer.cardMonthlyFee, offer),
      ),
      (
        label: 'Monthly card service fee',
        value: _fee(context, offer.serviceFee, offer),
      ),
    ];
    final additional = <({String label, String value})>[
      if (offer.planYearlyFee != null)
        (
          label: 'Plan card subscription / year',
          value: _fee(context, offer.planYearlyFee, offer),
        ),
      if (offer.cardYearlyFee != null)
        (
          label: 'Card subscription / year',
          value: _fee(context, offer.cardYearlyFee, offer),
        ),
      if (offer.replacementFee != null)
        (
          label: 'Replacement fee',
          value: _fee(context, offer.replacementFee, offer),
        ),
      if (offer.atmWithdrawalFee != null)
        (
          label: 'ATM withdrawal fee',
          value: _fee(context, offer.atmWithdrawalFee, offer),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _CardThumb(offer: offer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offer.name,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  if (kind != null)
                    Text(context.tr(kind), style: _captionStyle(context)),
                ],
              ),
            ),
          ],
        ),
        if (offer.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(offer.description, style: _bodyStyle(context)),
        ],
        if (offer.features.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr('Card features').toUpperCase(),
            style: ExampleTextStyles.label(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final feature in offer.features)
                _FeatureChip(label: feature),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        for (final row in fees)
          _FactRow(label: context.tr(row.label), value: row.value),
        if (additional.isNotEmpty) _AdditionalFees(rows: additional),
      ],
    );
  }
}

/// The card's rarer charges, folded away under the ones every customer pays.
class _AdditionalFees extends StatefulWidget {
  const _AdditionalFees({required this.rows});

  final List<({String label, String value})> rows;

  @override
  State<_AdditionalFees> createState() => _AdditionalFeesState();
}

class _AdditionalFeesState extends State<_AdditionalFees> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ink = ExampleInk.secondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('Additional fees'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: ExampleMotion.of(context, ExampleMotion.state),
                    child:
                        Icon(Icons.expand_more_rounded, size: 20, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: ExampleMotion.of(context, ExampleMotion.state),
          curve: ExampleMotion.arrive,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in widget.rows)
                      _FactRow(label: context.tr(row.label), value: row.value),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CardThumb extends StatelessWidget {
  const _CardThumb({required this.offer});

  final TierCardOffer offer;

  static const double _width = 52;
  static const double _height = 33;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: ExampleBorders.subtleOf(context),
      ),
      child: Icon(
        offer.isVirtual && !offer.isPhysical
            ? Icons.smartphone_rounded
            : Icons.credit_card_rounded,
        size: 18,
        color: ExampleInk.secondary(context),
      ),
    );
    if (offer.imageUrl.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Image.network(
        offer.imageUrl,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        width: _width,
        height: _height,
        fit: BoxFit.cover,
        semanticLabel:
            offer.imageAlt.isEmpty ? context.tr('Card design') : offer.imageAlt,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 2),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: ExampleBorders.subtleOf(context),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: ExampleInk.primary(context),
          ),
        ),
      );
}

/// Label left in secondary ink, value right in tabular figures, as in the
/// plan list's spec table, so a fee reads the same wherever it appears.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(label, style: _captionStyle(context))),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ExampleInk.primary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

/// One included thing. A check for a benefit the plan grants; a dot for a
/// line of the plan's own description of itself.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.icon = true});

  final String text;
  final bool icon;

  @override
  Widget build(BuildContext context) {
    final ink = ExampleInk.accent(context, ExampleColors.iris);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Padding(
              padding: EdgeInsets.only(top: icon ? 2 : 7),
              child: icon
                  // A real icon, never a check glyph: U+2713 is not in the
                  // bundled Geist subset and lands as a tofu box on web.
                  ? Icon(Icons.check_rounded, size: 14, color: ink)
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: ExampleInk.secondary(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text(text, style: _bodyStyle(context))),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: ExampleInk.primary(context),
          ),
        ),
      );
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: SizedBox(
          height: 1,
          child: ColoredBox(color: ExampleBorders.hairlineSideOf(context).color),
        ),
      );
}

class _CardsMessage extends StatelessWidget {
  const _CardsMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: _bodyStyle(context));
}

TextStyle _bodyStyle(BuildContext context) => TextStyle(
      fontSize: 13,
      height: 1.45,
      color: ExampleInk.secondary(context),
    );

TextStyle _captionStyle(BuildContext context) => TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: ExampleInk.secondary(context),
    );

String _money(double amount, String currency) =>
    Money.formatPlainAmount(currency, amount);

/// A card fee as the provider's own plan page words it: a missing or zero
/// charge is "Free".
String _fee(BuildContext context, double? amount, TierCardOffer offer) =>
    amount == null || amount == 0
        ? context.tr('Free')
        : _money(amount, offer.currency);

String _freeCardsText(BuildContext context, TierCardOffer offer) {
  final count = offer.freeCards ?? 0;
  if (count == 0) return '0';
  final period = offer.freeCardsPeriod.toLowerCase();
  return switch (period) {
    '' => '$count',
    'lifetime' ||
    'total' ||
    'once' ||
    'one_time' ||
    'onetime' =>
      context.tr('{p0} in total (lifetime)', {'p0': count}),
    'month' ||
    'monthly' ||
    'per_month' =>
      context.tr('{p0} per month', {'p0': count}),
    'year' ||
    'yearly' ||
    'annual' ||
    'annually' ||
    'per_year' =>
      context.tr('{p0} per year', {'p0': count}),
    _ => '$count (${offer.freeCardsPeriod})',
  };
}

/// The plan's limits, from the shared tier contract, in the words the plan
/// list's spec table uses.
List<({String label, String value})> _tierLimits(PlatformResource tier) {
  const labels = {
    'Monthly limit': 'Monthly limit',
    'Daily limit': 'Daily limit',
    'Transaction limit': 'Transaction limit',
    'ATM limit': 'ATM limit',
    'Daily free draws': 'Daily free draws',
    'Max cards': 'Cards included',
    'KYC': 'KYC level',
  };
  final rows = <({String label, String value})>[];
  for (final line in tierDetailsOf(tier)) {
    for (final entry in labels.entries) {
      if (line.startsWith('${entry.key} ')) {
        rows.add((
          label: entry.value,
          value: _grouped(line.substring(entry.key.length + 1)),
        ));
        break;
      }
    }
  }
  return rows;
}

String _grouped(String value) {
  final digits = value.trim();
  if (!RegExp(r'^\d{4,}$').hasMatch(digits)) return value;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../../brands/example/example.dart';
import '../../../../core/models/banking_models.dart';

/// Status ink for the active theme. Twilight keeps today's tokens; daylight
/// takes the re-darkened pair from [ExamplePalette], so a status never reads as
/// neon on paper.
Color exampleStatusInk(BuildContext context, CardStatus status) {
  final palette = ExamplePalette.of(context);
  return switch (status) {
    CardStatus.active => palette.success,
    CardStatus.frozen => palette.warning,
    CardStatus.pending => palette.accent,
    CardStatus.cancelled => palette.textTertiary,
  };
}

/// `•••• 4271 · Physical · Mastercard` — the card's identity in one line.
String cardMetaLine(PaymentCard card, {BuildContext? context}) => [
      if (card.last4.isNotEmpty) '•••• ${card.last4}',
      context?.tr(card.virtual ? 'Virtual' : 'Physical') ??
          (card.virtual ? 'Virtual' : 'Physical'),
      if (card.network.trim().isNotEmpty) cardNetworkName(card.network),
    ].join(' · ');

/// The same line for a screen reader: bullets are spoken as "ending", and the
/// digits are separated so the last four are read one by one.
String cardMetaSemantics(PaymentCard card, {BuildContext? context}) => [
      if (card.last4.isNotEmpty)
        context?.tr('ending {p0}', {'p0': card.last4.split('').join(' ')}) ??
            'ending ${card.last4.split('').join(' ')}',
      context?.tr(card.virtual ? 'Virtual' : 'Physical') ??
          (card.virtual ? 'virtual' : 'physical'),
      if (card.network.trim().isNotEmpty) cardNetworkName(card.network),
    ].join(', ');

String cardNetworkName(String network) {
  final normalized = network.trim().toLowerCase();
  if (normalized.contains('master')) return 'Mastercard';
  if (normalized.contains('visa')) return 'Visa';
  return network.trim();
}

/// Month-to-date against the card's limit, on a 2 pt hairline.
///
/// The only non-typographic data mark on the Cards screens, and it never
/// animates: the living card's specular pass is the one moment each of those
/// screens gets. The bar is drawn as a fraction of the row, so nothing here
/// depends on a measured width, and the whole block collapses to the spend
/// line alone when the card carries no limit.
class CardSpendMeter extends StatelessWidget {
  const CardSpendMeter({
    required this.spent,
    required this.limit,
    required this.currency,
    this.label = 'Spent this month',
    super.key,
  });

  /// Major units already spent this month.
  final double spent;

  /// Major units the card is allowed this month. Zero hides the bar.
  final double limit;

  final String currency;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final hasLimit = limit > 0;
    final ratio = hasLimit ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).round();
    final fill = ExampleInk.accent(
      context,
      ratio >= .9 ? palette.warning : palette.accent,
    );
    final limitText = Money(
      currency: currency,
      minorUnits: (limit * 100).round(),
    ).formatted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                context.tr(label),
                style: TextStyle(
                  fontSize: 12.5,
                  color: ExampleInk.secondary(context),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ExampleAmount(
              amount: spent,
              currency: currency,
              size: ExampleAmountSize.small,
              code: ExampleAmountCode.never,
              textAlign: TextAlign.end,
            ),
          ],
        ),
        if (hasLimit) ...[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: context.tr(
                'Spent {p0} percent of the {p1} monthly card limit',
                {'p0': percent, 'p1': limitText}),
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: SizedBox(
                height: 2,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: ExampleSurface.of(context, 2)),
                    ),
                    FractionallySizedBox(
                      // A hairline of fill so an untouched limit still reads
                      // as a track with a beginning.
                      widthFactor: ratio == 0 ? .004 : ratio,
                      child: ColoredBox(color: fill),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('{p0}% of {p1} monthly limit',
                {'p0': percent, 'p1': limitText}),
            style: TextStyle(
              fontSize: 11.5,
              color: ExampleInk.tertiary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

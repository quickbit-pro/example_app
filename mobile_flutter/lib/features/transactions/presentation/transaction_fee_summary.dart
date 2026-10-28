import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/group_activity_transactions.dart';
import '../../../shared/widgets/neo_banking_components.dart';

/// One padded summary for card and account fees. Grouped-card separators are
/// the only rules, so rows never add a second line or a trailing bottom border.
class TransactionFeeSummary extends StatelessWidget {
  const TransactionFeeSummary({required this.transaction, super.key});
  final LedgerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final funding = const {
      'card_topup',
      'fx_trade',
      'exchange',
    }.contains(transaction.rawType.toLowerCase());
    final isCard = transaction.type == TransactionType.card && !funding;
    final charged = transaction.cardFees.where(cardFeeWasCharged);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(isCard ? 'Card fees' : 'Transaction fees'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        NeoGroupedCard(
          children: [
            _FeeRow(
              label: context.tr(
                isCard ? 'Purchase amount' : 'Amount before fees',
              ),
              value:
                  (funding
                          ? activityPrincipalAmount(transaction)
                          : transaction.displayAmount)
                      .formatted,
            ),
            if (funding)
              _FeeRow(
                label: context.tr('Amount received'),
                value:
                    (transaction.secondarySettlementAmount ??
                            transaction.amount)
                        .formatted,
              ),
            for (final fee in transaction.cardFees)
              _FeeRow(
                label: context.tr(cardFeeLabel(fee)),
                value:
                    '${feeChargedAmount(fee).currency} ${feeChargedAmount(fee).decimalAmount.abs().toStringAsFixed(2)} · ${context.tr(cardFeeWasCharged(fee) ? 'Charged' : fee.status)}',
              ),
            if (charged.isNotEmpty &&
                charged.every(
                  (fee) =>
                      feeChargedAmount(fee).currency.toUpperCase() ==
                      activityPrincipalAmount(
                        transaction,
                      ).currency.toUpperCase(),
                ))
              _FeeRow(
                label: context.tr('Total including fees'),
                value: activityListAmount(transaction).formatted,
                total: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.value, this.total = false});
  final String label;
  final String value;
  final bool total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(
          label,
          style: total ? const TextStyle(fontWeight: FontWeight.w600) : null,
        );
        final amountText = Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: total ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labelText, const SizedBox(height: 6), amountText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: labelText),
            const SizedBox(width: 16),
            Expanded(child: amountText),
          ],
        );
      },
    ),
  );
}

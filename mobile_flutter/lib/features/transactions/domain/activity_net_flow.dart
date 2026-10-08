import '../../../core/models/banking_models.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/group_activity_transactions.dart';
import 'transaction_flow.dart';

class ActivityFlowTotals {
  const ActivityFlowTotals({
    required this.incoming,
    required this.outgoing,
    required this.eventCount,
  });

  final double? incoming;
  final double? outgoing;
  final int eventCount;
  double? get net =>
      incoming == null || outgoing == null ? null : incoming! - outgoing!;
}

/// Settled movements for the current Activity filters, all in one currency.
/// Missing rates leave amounts unavailable rather than displaying partial sums.
///
/// Sums [activityAccountingRows] so a movement surfaced twice is counted
/// once, and a fee counts on the row it
/// charges: a declined purchase moves nothing, but the decline fee it incurred
/// did, and an FX trade is an internal movement while its service fee is a
/// real cost.
ActivityFlowTotals activityFlowTotals(
  List<LedgerTransaction> rows, {
  required String currency,
  required Map<String, double> rates,
  bool includeRelated = false,
}) {
  final target = currency.trim().toUpperCase();
  final seen = <String>{};
  var incoming = BigInt.zero;
  var outgoing = BigInt.zero;
  var eventCount = 0;
  var complete = true;
  for (final row in activityAccountingRows(rows)) {
    if (row.id.isNotEmpty && !seen.add(row.id)) continue;
    final status =
        (row.status.isEmpty ? row.subtitle : row.status).trim().toLowerCase();
    final unsettled = transactionHasFailed(row) ||
        const {
          'fail',
          'pending',
          'created',
          'processing',
          'authorized',
          'authorised',
        }.contains(status);
    final related = !includeRelated &&
        (!row.isPrimary || transactionIsInternalMovement(row));
    final movements = <(Money, Money?)>[
      if (!unsettled && !related) (row.amount, row.transactionAmount),
      for (final fee in row.cardFees)
        if (cardFeeWasCharged(fee)) (feeChargedAmount(fee), null),
    ];
    var counted = false;
    for (final (money, local) in movements) {
      final amount = money.decimalAmount;
      if (amount == 0) continue;
      final code = money.currency.trim().toUpperCase();
      final rate = code == target ? 1.0 : rates[code];
      double? converted;
      if (rate != null && rate.isFinite && rate > 0) {
        converted = amount * rate;
      } else if (local?.currency.trim().toUpperCase() == target) {
        converted = local!.decimalAmount;
      }
      if (!counted) {
        counted = true;
        eventCount++;
      }
      if (converted == null || !converted.isFinite) {
        complete = false;
        continue;
      }
      final units =
          BigInt.parse(converted.toStringAsFixed(8).replaceAll('.', ''));
      if (units.isNegative) {
        outgoing -= units;
      } else {
        incoming += units;
      }
    }
  }
  return ActivityFlowTotals(
    incoming: complete ? incoming.toDouble() / 100000000 : null,
    outgoing: complete ? outgoing.toDouble() / 100000000 : null,
    eventCount: eventCount,
  );
}

double? activityNetFlow(
  List<LedgerTransaction> rows, {
  required String currency,
  required Map<String, double> rates,
  bool includeRelated = false,
}) =>
    activityFlowTotals(rows,
            currency: currency, rates: rates, includeRelated: includeRelated)
        .net;

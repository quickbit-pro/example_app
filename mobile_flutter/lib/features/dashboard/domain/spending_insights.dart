import 'dashboard_models.dart';

/// What Home's "Smart insights" says about the current calendar month.
///
/// Every number here is a fact the customer can check against the ledger:
/// what went out this month, how that compares with last month, what came
/// in, where most of it went, the single largest payment, and card payments
/// that look like a monthly subscription. Nothing is estimated across
/// currencies; one currency is chosen (the one most payments were made in)
/// and the rest are left out rather than added up as if they were the same.
class SpendingInsights {
  const SpendingInsights({
    required this.currency,
    required this.spent,
    required this.payments,
    required this.lastMonthSpent,
    required this.received,
    required this.receipts,
    required this.topMerchant,
    required this.largest,
    required this.recurring,
    required this.hasHistory,
  });

  /// The currency the totals are in; empty when there is nothing to total.
  final String currency;

  /// Completed outgoing payments in [currency] this month, as a positive sum.
  final double spent;
  final int payments;

  /// The same figure for the whole of last month, or null when the ledger
  /// window does not reach back to the start of last month, so the
  /// comparison would be against a month only partly seen.
  final double? lastMonthSpent;

  /// Completed incoming money in [currency] this month.
  final double received;
  final int receipts;

  /// The card merchant most was spent at this month, when paid more than once.
  final MerchantInsight? topMerchant;

  /// The single largest completed outgoing payment this month.
  final PaymentInsight? largest;

  /// Card merchants paid this month and last month for about the same amount.
  final List<PaymentInsight> recurring;

  /// Whether any completed outgoing payment exists at all, in any month.
  final bool hasHistory;

  double get net => received - spent;

  /// Percentage change against last month, or null when there is nothing to
  /// compare against.
  double? get changeFromLastMonth {
    final last = lastMonthSpent;
    if (last == null || last <= 0) return null;
    return (spent - last) / last * 100;
  }

  static SpendingInsights compute(
    List<HoppaActivity> activities, {
    required DateTime now,
  }) {
    final completed = activities
        .where((a) => a.isCompleted && a.amount != 0 && !a.isInternalMovement)
        .toList(growable: false);
    final dated = completed.where((a) => a.bookedAt != null).toList();
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    // Without a single date the month cannot be told from the rest, so the
    // whole window stands in for this month and nothing is compared. Once
    // dates exist, a row without one cannot be placed in any month and stays
    // out of the month figures.
    final undated = dated.isEmpty;
    bool inThisMonth(HoppaActivity a) {
      final at = a.bookedAt;
      if (at == null) return undated;
      return !at.isBefore(monthStart);
    }

    bool inLastMonth(HoppaActivity a) {
      final at = a.bookedAt;
      if (at == null) return false;
      return !at.isBefore(lastMonthStart) && at.isBefore(monthStart);
    }

    final outgoing = completed.where((a) => a.amount < 0).toList();
    final thisMonthOut = outgoing.where(inThisMonth).toList();
    final currency =
        _dominantCurrency(thisMonthOut.isEmpty ? outgoing : thisMonthOut);
    bool inCurrency(HoppaActivity a) => _currencyOf(a) == currency;

    final spentRows = thisMonthOut.where(inCurrency).toList();
    final spent = spentRows.fold<double>(0, (sum, a) => sum + a.amount.abs());

    DateTime? oldest;
    for (final a in dated) {
      if (oldest == null || a.bookedAt!.isBefore(oldest)) oldest = a.bookedAt;
    }
    final coversLastMonth = oldest != null && !oldest.isAfter(lastMonthStart);
    final lastMonthRows =
        outgoing.where(inLastMonth).where(inCurrency).toList();
    final lastMonthSpent = coversLastMonth
        ? lastMonthRows.fold<double>(0, (sum, a) => sum + a.amount.abs())
        : null;

    final receivedRows = completed
        .where((a) => a.amount > 0)
        .where(inThisMonth)
        .where(inCurrency)
        .toList();
    final received = receivedRows.fold<double>(0, (sum, a) => sum + a.amount);

    // Merchants are card payments: a transfer's title ("Bank transfer") names
    // a kind of movement, not a place money went.
    final cardRows = spentRows.where((a) => a.kind == HoppaActivityKind.card);
    final byMerchant = <String, MerchantInsight>{};
    for (final a in cardRows) {
      final key = a.title.trim().toLowerCase();
      if (key.isEmpty) continue;
      final seen = byMerchant[key];
      byMerchant[key] = MerchantInsight(
        title: seen?.title ?? a.title.trim(),
        total: (seen?.total ?? 0) + a.amount.abs(),
        count: (seen?.count ?? 0) + 1,
      );
    }
    MerchantInsight? topMerchant;
    for (final merchant in byMerchant.values) {
      if (merchant.count < 2) continue;
      if (topMerchant == null || merchant.total > topMerchant.total) {
        topMerchant = merchant;
      }
    }

    PaymentInsight? largest;
    for (final a in spentRows) {
      if (largest == null || a.amount.abs() > largest.amount) {
        largest = PaymentInsight(
          id: a.id,
          title: a.title.trim(),
          amount: a.amount.abs(),
        );
      }
    }

    final recurring = <PaymentInsight>[];
    final lastMonthCard = lastMonthRows
        .where((a) => a.kind == HoppaActivityKind.card)
        .toList(growable: false);
    final seenRecurring = <String>{};
    for (final a in cardRows) {
      final key = a.title.trim().toLowerCase();
      if (key.isEmpty || !seenRecurring.add(key)) continue;
      final amount = a.amount.abs();
      final match = lastMonthCard.any((b) =>
          b.title.trim().toLowerCase() == key &&
          (b.amount.abs() - amount).abs() <= 0.1 * amount);
      if (match) {
        recurring.add(
          PaymentInsight(id: a.id, title: a.title.trim(), amount: amount),
        );
      }
    }

    return SpendingInsights(
      currency: currency,
      spent: spent,
      payments: spentRows.length,
      lastMonthSpent: lastMonthSpent,
      received: received,
      receipts: receivedRows.length,
      topMerchant: topMerchant,
      largest: largest,
      recurring: List.unmodifiable(recurring),
      hasHistory: outgoing.isNotEmpty,
    );
  }

  static String _currencyOf(HoppaActivity a) => a.currency.trim().toUpperCase();

  /// The currency most of [rows] are in; ties go to the earliest seen.
  static String _dominantCurrency(List<HoppaActivity> rows) {
    final counts = <String, int>{};
    for (final a in rows) {
      final currency = _currencyOf(a);
      if (currency.isEmpty) continue;
      counts[currency] = (counts[currency] ?? 0) + 1;
    }
    var best = '';
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }
}

class MerchantInsight {
  const MerchantInsight({
    required this.title,
    required this.total,
    required this.count,
  });

  final String title;
  final double total;
  final int count;
}

class PaymentInsight {
  const PaymentInsight({
    required this.id,
    required this.title,
    required this.amount,
  });

  final String id;
  final String title;

  /// Always positive.
  final double amount;
}

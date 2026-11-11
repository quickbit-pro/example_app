import '../../../core/models/banking_models.dart';
import 'payment_balance_options.dart';

bool payoutQuoteMatches(PayoutQuote quote,
        {required double amount, required String currency}) =>
    quote.id.isNotEmpty &&
    quote.targetAmount.isFinite &&
    quote.targetAmount > 0 &&
    quote.targetAmount.toStringAsFixed(2) == amount.toStringAsFixed(2) &&
    quote.targetCurrency.toUpperCase() == currency.toUpperCase();

Money? payoutTotalDebit(PayoutQuote quote) {
  final fee = quote.fee;
  if (fee == null ||
      !fee.isFinite ||
      fee < 0 ||
      !quote.sourceAmount.isFinite ||
      quote.sourceAmount <= 0 ||
      quote.sourceCurrency.trim().isEmpty) {
    return null;
  }
  final total = quote.totalDebit ?? (quote.sourceAmount + fee);
  if (!total.isFinite || total < quote.sourceAmount) return null;
  return Money.fromJson({'currency': quote.sourceCurrency, 'amount': total});
}

String? payoutFundingError(PayoutQuote quote, AccountBalance account) {
  final total = payoutTotalDebit(quote);
  if (total == null) {
    return 'The complete payment fee is unavailable. Request a new quote.';
  }
  final available = fundedBalances(account)
          .where(
              (b) => b.currency.toUpperCase() == total.currency.toUpperCase())
          .firstOrNull ??
      Money(currency: total.currency, minorUnits: 0);
  if (total.minorUnits <= available.minorUnits) return null;
  return 'Insufficient funds. Total debit: ${total.formatted}. Available: ${available.formatted}. Reduce the amount or choose another account.';
}

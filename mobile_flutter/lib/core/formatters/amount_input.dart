/// Formats a balance for an amount field so that it never exceeds the real
/// balance: the value is truncated (not rounded) to [decimals] places.
///
/// `toStringAsFixed` rounds half-up, so 32.0395 USDC would become "32.04",
/// which is more than the customer holds and fails the balance check.
String maxAmountInput(double value, {required int decimals}) {
  if (value <= 0 || value.isNaN || value.isInfinite) return '0';
  // Work on the decimal text so binary floating point (32.0395 * 1e6 =
  // 32039499.999…) cannot shave a unit off the last digit.
  final text = value.toStringAsFixed(12);
  final dot = text.indexOf('.');
  var truncated = decimals == 0
      ? text.substring(0, dot)
      : text.substring(0, dot + 1 + decimals);
  if (truncated.contains('.')) {
    truncated = truncated
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return truncated.isEmpty ? '0' : truncated;
}

/// Amount fields always work in two decimals, rounded down, for fiat and
/// stablecoins alike.
int amountDecimalsFor(String currency) => 2;

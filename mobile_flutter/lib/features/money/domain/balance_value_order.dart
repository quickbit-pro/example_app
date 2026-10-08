/// Orders native balances by value in the rates' common currency. Unknown
/// currencies follow priced balances alphabetically; native numbers from
/// different currencies must never be compared directly.
int compareBalanceValues(String leftCurrency, double leftAmount,
    String rightCurrency, double rightAmount, Map<String, double> rates) {
  final left = leftCurrency.trim().toUpperCase();
  final right = rightCurrency.trim().toUpperCase();
  if (left == right) return rightAmount.abs().compareTo(leftAmount.abs());
  double? value(String currency, double amount) {
    final rate = rates[currency];
    if (rate == null || !rate.isFinite || rate <= 0) return null;
    final result = (amount * rate).abs();
    return result.isFinite ? result : null;
  }

  final leftValue = value(left, leftAmount);
  final rightValue = value(right, rightAmount);
  if (leftValue != null && rightValue != null) {
    final order = rightValue.compareTo(leftValue);
    if (order != 0) return order;
  } else if (leftValue != null) {
    return -1;
  } else if (rightValue != null) {
    return 1;
  }
  return left.compareTo(right);
}
